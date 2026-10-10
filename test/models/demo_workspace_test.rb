require "test_helper"
require "minitest/mock"

class DemoWorkspaceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def in_development(&block)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development"), &block)
  end

  test "empty development workspace gets twelve varied RFQs with constructed sent history" do
    quotes = in_development { QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a") }
    assert_equal 12, quotes.length
    assert_equal 12, quotes.map(&:title).uniq.length
    assert_operator quotes.map(&:buyer_name).uniq.length, :>=, 5
    assert quotes.all?(&:persisted?)
    assert quotes.all?(&:sample_data?)
    assert quotes.all? { |quote| quote.quote_lines.any? }
    assert_equal 2, quotes.count(&:sent?)
    assert_equal 4, quotes.count(&:approved?)
    assert_equal 2, quotes.count { |quote| quote.approved? && !quote.sent? && quote.held_count.zero? }
    assert quotes.select(&:sent?).all? { |quote| quote.sent_at >= quote.created_at && quote.sent_at <= Time.current && quote.held_count.zero? }
    assert quotes.any? { |quote| quote.created_at < 24.hours.ago }
    assert quotes.any? { |quote| quote.quote_lines.count >= 3 }
    assert quotes.any? { |quote| !quote.sent? && quote.held_count.zero? && quote.ready_count.positive? }
    assert quotes.flat_map(&:quote_lines).any? { |line| line.state == "no_match" }
    mixed = quotes.find { |quote| quote.title == "Shop materials and blasting media" }
    assert_includes mixed.source_text, "G-40 steel grit"
    assert_includes mixed.source_text, "P1020 aluminum ingot"
    assert_operator mixed.quote_lines.count, :>=, 5
    assert_equal BigDecimal("4640"), quotes.first.subtotal
    shot = quotes.find { |quote| quote.title == "Steel shot replenishment" }.quote_lines.sole
    assert shot.quotable?
    assert_equal "RC-STEELSHOT-S330", shot.catalog_sku
    assert shot.price_source.present?
    plate = quotes.find { |quote| quote.title == "Structural plate order" }.quote_lines.sole
    refute plate.quotable?
    assert_nil plate.unit_price
    assert plate.clarification_question.present?
  end

  test "refresh and explicit population are idempotent at twelve records" do
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
      assert_difference "Quote.count", 11 do
        QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      end
    end
    assert_equal before_quote, existing.reload.attributes
    assert_equal before_lines, existing.quote_lines.map(&:attributes)
    assert_operator Quote.for_workspace("seed-a").find_by!(title: "Aerospace sheet request").created_at, :<, 24.hours.ago
  end

  test "workspaces are independent and production and test never seed" do
    in_development do
      QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a")
      QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-b")
    end
    assert_equal 12, Quote.for_workspace("seed-a").count
    assert_equal 12, Quote.for_workspace("seed-b").count
    %w[production test].each do |environment|
      Rails.stub(:env, ActiveSupport::StringInquirer.new(environment)) do
        assert_no_difference "Quote.count" do
          assert_empty QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "unseeded")
          assert_empty QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "unseeded")
        end
      end
    end
  end

  test "explicit population counts arbitrary existing RFQs toward the desk target" do
    existing = Quote.create!(title: "Rep's own request", buyer_name: "Real buyer",
      workspace_token: "seed-a", source_text: "Please call to discuss materials")
    before_quote = existing.attributes
    in_development do
      assert_difference "Quote.count", 11 do
        QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      end
      assert_empty QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
    end
    assert_equal before_quote, existing.reload.attributes
    assert_equal 12, Quote.for_workspace("seed-a").count
  end

  test "explicit topup restores the missing recipe instead of duplicating another" do
    in_development do
      QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      Quote.for_workspace("seed-a").find_by!(title: "Steel shot replenishment").destroy!
      surviving_ids = Quote.for_workspace("seed-a").ids
      created = QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "seed-a")
      assert_equal 1, created.length
      assert_equal "Hudson Surface Prep", created.first.buyer_name
      assert_equal 12, Quote.for_workspace("seed-a").count
      assert_equal 1, Quote.for_workspace("seed-a").where(title: "Structural plate order").count
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
      assert_no_difference "ActionMailer::Base.deliveries.count" do
        assert_no_enqueued_jobs only: ProcessRfqJob do
          in_development { QuoteWorkspace::DemoWorkspace.seed_if_empty!(workspace_token: "seed-a") }
        end
      end
    end
    assert_equal 11, calls.length
    assert calls.all? { |arguments| arguments[:llm] == false && arguments[:sample_data] == true }
    assert_empty ProcessingRun.where(quote_id: Quote.for_workspace("seed-a").select(:id))
    assert_empty Client.for_workspace("seed-a")
  end

  test "explicit timing refresh preserves content revisions and constructed sent history on repeated runs" do
    in_development do
      quotes = QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "refresh")
      before = quotes.to_h { |quote| [quote.id, quote.attributes.except("created_at", "approved_at", "sent_at")] }
      lines = quotes.to_h { |quote| [quote.id, quote.quote_lines.map(&:attributes)] }
      now = Time.current + 3.days
      2.times do
        assert_equal({ refreshed: 12, skipped: 0 }, QuoteWorkspace::DemoWorkspace.refresh_timing!(workspace_token: "refresh", now: now))
      end
      quotes.each do |quote|
        quote.reload
        assert_equal before[quote.id], quote.attributes.except("created_at", "approved_at", "sent_at")
        assert_equal lines[quote.id], quote.quote_lines.map(&:attributes)
        assert quote.valid?
      end
      assert_equal 2, quotes.count(&:sent?)
      assert quotes.select(&:sent?).all? { |quote| quote.sent_at >= quote.created_at && quote.approved_at <= quote.sent_at }
      assert_equal now - 30.minutes, quotes.find { |quote| quote.title == "Afternoon media order" }.created_at
    end
  end

  test "timing refresh skips human edits unknown fixtures and changed approval history" do
    in_development do
      quotes = QuoteWorkspace::DemoWorkspace.populate!(workspace_token: "refresh")
      edited = quotes.find { |quote| quote.title == "Structural plate order" }
      edited.quote_lines.first.apply_manual_edit("notes" => "Keep my reviewed RFQ")
      human = quotes.find { |quote| quote.title == "Afternoon media order" }
      human.update!(sample_data: false)
      unknown = quotes.find { |quote| quote.title == "Aerospace sheet request" }
      unknown.update!(title: "Rep renamed this RFQ")
      approved = quotes.find { |quote| quote.title == "Blast room media restock" }
      approved.approve!
      stale_sent = quotes.find(&:sent?)
      stale_sent.touch(time: 1.minute.from_now)
      protected_quotes = [edited, human, unknown, approved, stale_sent]
      before = protected_quotes.to_h { |quote| [quote.id, quote.reload.attributes] }
      counts = QuoteWorkspace::DemoWorkspace.refresh_timing!(workspace_token: "refresh", now: 2.days.from_now)
      assert_equal 7, counts[:refreshed]
      assert_equal 4, counts[:skipped]
      protected_quotes.each { |quote| assert_equal before[quote.id], quote.reload.attributes }
    end
  end

  test "explicit timing refresh refuses nondevelopment environments" do
    %w[test production].each do |environment|
      Rails.stub(:env, ActiveSupport::StringInquirer.new(environment)) do
        assert_raises(ArgumentError) { QuoteWorkspace::DemoWorkspace.refresh_timing! }
      end
    end
  end
end
