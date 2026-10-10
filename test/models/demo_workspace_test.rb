require "test_helper"
require "minitest/mock"

class DemoWorkspaceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def in_development(&block)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development"), &block)
  end

  test "empty development workspace gets three distinct persisted labeled RFQs" do
    quotes = in_development { QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a") }
    assert_equal 3, quotes.length
    assert_equal 3, quotes.map(&:title).uniq.length
    assert_equal 3, quotes.map(&:buyer_name).uniq.length
    assert quotes.all?(&:persisted?)
    assert quotes.all?(&:sample_data?)
    assert quotes.all? { |quote| quote.quote_lines.any? }
    assert quotes.none?(&:approved?)
    assert_equal BigDecimal("4640"), quotes.first.subtotal
    shot = quotes.find { |quote| quote.buyer_name == "Hudson Surface Prep" }.quote_lines.sole
    assert shot.quotable?
    assert_equal "RC-STEELSHOT-S330", shot.catalog_sku
    assert shot.price_source.present?
    plate = quotes.find { |quote| quote.buyer_name == "Harbor Fabrication" }.quote_lines.sole
    refute plate.quotable?
    assert_nil plate.unit_price
    assert plate.clarification_question.present?
  end

  test "refresh and explicit population are idempotent at three records" do
    in_development do
      QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a")
      ids = Quote.for_workspace("seed-a").ids
      assert_no_difference "Quote.count" do
        assert_empty QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a")
        assert_empty QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      end
      assert_equal ids, Quote.for_workspace("seed-a").ids
    end
  end

  test "automatic seeding leaves existing RFQs untouched and explicit topup preserves them" do
    existing = QuoteWorkspace::Demo.create!(workspace_token: "seed-a")
    existing.quote_lines.first.apply_manual_edit("notes" => "Rep reviewed")
    before_quote = existing.reload.attributes
    before_lines = existing.quote_lines.map(&:attributes)
    in_development do
      assert_no_difference "Quote.count" do
        assert_empty QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a")
      end
      assert_difference "Quote.count", 2 do
        QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      end
    end
    assert_equal before_quote, existing.reload.attributes
    assert_equal before_lines, existing.quote_lines.map(&:attributes)
  end

  test "workspaces are independent and production and test never seed" do
    in_development do
      QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a")
      QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-b")
    end
    assert_equal 3, Quote.for_workspace("seed-a").count
    assert_equal 3, Quote.for_workspace("seed-b").count
    %w[production test].each do |environment|
      Rails.stub(:env, ActiveSupport::StringInquirer.new(environment)) do
        assert_no_difference "Quote.count" do
          assert_empty QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "unseeded")
          assert_empty QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "unseeded")
        end
      end
    end
  end

  test "explicit topup restores the missing recipe instead of duplicating another" do
    in_development do
      QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      Quote.for_workspace("seed-a").find_by!(buyer_name: "Hudson Surface Prep").destroy!
      surviving_ids = Quote.for_workspace("seed-a").ids
      created = QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      assert_equal 1, created.length
      assert_equal "Hudson Surface Prep", created.first.buyer_name
      assert_equal 3, Quote.for_workspace("seed-a").count
      assert_equal 1, Quote.for_workspace("seed-a").where(buyer_name: "Harbor Fabrication").count
      assert surviving_ids.all? { |id| Quote.exists?(id) }
      Quote.for_workspace("seed-a").find_by!(buyer_name: QuoteWorkspace::Demo::BUYER_NAME).destroy!
      replacement = QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      assert_equal 1, replacement.length
      assert_equal "Sheet and plate sourcing", replacement.first.title
      assert_equal BigDecimal("4640"), replacement.first.subtotal
    end
  end

  test "rules seeding explicitly disables providers and queues no work or mail" do
    processor = RfqProcessing.method(:process)
    calls = []
    RfqProcessing.stub(:process, lambda { |**arguments|
      calls << arguments
      processor.call(**arguments)
    }) do
      assert_no_enqueued_jobs do
        in_development { QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a") }
      end
    end
    assert_equal 2, calls.length
    assert calls.all? { |arguments| arguments[:llm] == false && arguments[:sample_data] == true }
    assert_empty ProcessingRun.where(quote_id: Quote.for_workspace("seed-a").select(:id))
    assert_empty Client.for_workspace("seed-a")
  end
end
