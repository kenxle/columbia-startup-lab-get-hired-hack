require "test_helper"

class BrandHeaderTest < ActionDispatch::IntegrationTest
  test "sidebar alone uses the approved lockup and keeps keyboard navigation available" do
    get quotes_path
    assert_response :success

    assert_select "title", "Quotes · Quote Desk"
    assert_select 'meta[name="application-name"][content="RudCo Quote Desk"]'
    %w[icon apple-touch-icon].each do |relation|
      assert_select 'link[rel=?][type="image/png"]', relation, count: 1 do |icons|
        assert_match %r{/assets/rudco-favicon(?:-[a-f0-9]+)?\.png}, icons.first["href"]
      end
    end
    assert_select 'link[href="/icon.png"], link[href="/icon.svg"]', count: 0
    assert_select 'a.skip-link[href="#main"]', "Skip to content"
    assert_select 'main#main[tabindex="-1"]'
    assert_select "header.brand-header", count: 0
    assert_select 'nav[aria-label="Product"]', count: 0
    assert_select 'a.sidebar__brand[href=?][aria-label="RudCo Quote Desk home"]', root_path do
      assert_select 'img[src="/brand/rudco-mark.png"][width="32"][height="32"][alt=""]'
      assert_select ".sidebar__name", "RudCo"
      assert_select ".sidebar__product", "QUOTE DESK"
    end
    assert_select ".workspace-footer, .sidebar__note", count: 0
    assert_select ".sidebar__sample", "Load demo RFQ"
  end

  test "branding preserves catalog navigation and status words" do
    post demo_quotes_path
    get response.location, params: { status: "all" }
    assert_response :success

    assert_select ".sidebar__nav a[href=?]", catalog_matches_path, "Find catalog item"
    assert_select ".sidebar__nav a[href=?]", new_quote_path, "New RFQ"
    assert_select ".sidebar__mark", count: 0
    assert_select ".status--ready", text: "Ready", minimum: 1
    assert_select ".status--needs-buyer", text: "Question to send", minimum: 1
    assert_select ".status--no-match", text: "No match", minimum: 1
  end

  test "quote tab titles lead with buyer attention and keep the RFQ reference" do
    post demo_quotes_path
    quote = Quote.find(response.location[%r{/quotes/(\d+)}, 1])
    get quote_path(quote)
    assert_select "title", "1 question to send · #{quote.reference} · Quote Desk"

    quote.quote_lines.find_by!(state: "ready").update!(state: "needs_buyer")
    get quote_path(quote)
    assert_select "title", "2 questions to send · #{quote.reference} · Quote Desk"
  end

  test "title fallback preserves nonquote pages and handles unprocessed RFQs" do
    get new_quote_path
    assert_response :success
    assert_select "title", "New RFQ · Quote Desk"

    helper = ApplicationController.helpers
    assert_equal "Quote Desk", helper.workspace_document_title
    assert_equal "New RFQ · Quote Desk", helper.workspace_document_title(page_title: "New RFQ", quote: Quote.new)
    quote = Quote.create!(title: "New buyer request", source_text: "Please quote plate", workspace_token: "brand-title-test")
    assert_equal "Awaiting processing · #{quote.reference} · Quote Desk", helper.workspace_document_title(quote: quote)
  end

  test "shared status and flag components escape labels and constrain variants" do
    status = ApplicationController.render(partial: "shared/status_badge", locals: { label: "<script>Unrecognized</script>", state: "unexpected injected" })
    assert_includes status, 'class="status status--unknown"'
    assert_includes status, "&lt;script&gt;Unrecognized&lt;/script&gt;"
    refute_includes status, "<script>"

    flag = ApplicationController.render(partial: "shared/flag", locals: { label: "<b>Evidence</b>", tone: "unexpected injected" })
    assert_includes flag, 'class="flag flag--source"'
    assert_includes flag, "&lt;b&gt;Evidence&lt;/b&gt;"
  end

  test "catalog outcome labels use the same status component as quote lines" do
    { "match" => ["ready", "Match"], "candidates" => ["needs-buyer", "Needs the buyer"], "no_match" => ["no-match", "No match"] }.each do |outcome, (variant, label)|
      badge = ApplicationController.render(partial: "catalog_matches/outcome_badge", locals: { outcome: outcome })
      assert_includes badge, "class=\"status status--#{variant}\""
      assert_includes badge, ">#{label}</span>"
    end
  end
end
