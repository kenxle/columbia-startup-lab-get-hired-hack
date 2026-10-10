require "test_helper"

class BrandHeaderTest < ActionDispatch::IntegrationTest
  test "workspace header identifies the concept and keeps keyboard navigation available" do
    get quotes_path
    assert_response :success

    assert_select "title", /RudCo Quote Desk/
    assert_select 'meta[name="application-name"][content="RudCo Quote Desk"]'
    %w[icon apple-touch-icon].each do |relation|
      assert_select 'link[rel=?][type="image/png"]', relation, count: 1 do |icons|
        assert_match %r{/assets/rudco-favicon(?:-[a-f0-9]+)?\.png}, icons.first["href"]
      end
    end
    assert_select 'link[href="/icon.png"], link[href="/icon.svg"]', count: 0
    assert_select 'a.skip-link[href="#main"]', "Skip to content"
    assert_select 'main#main[tabindex="-1"]'
    assert_select "header.brand-header" do
      assert_select "a.brand-header__lockup[href=?][aria-label=?]", root_path, "RudCo Quote Desk home" do
        assert_select 'img[alt="RudCo Industrial Materials Platform logo"][width="32"][height="32"]' do |images|
          assert_match %r{/assets/rudco-mark(?:-[a-f0-9]+)?\.png}, images.first["src"]
        end
        assert_select ".brand-header__name", "RudCo"
        assert_select ".brand-header__tagline", "Industrial Materials Platform"
      end
      assert_select 'nav[aria-label="Product"] a[href=?]', quotes_path, "Quote Desk"
    end
    assert_select ".workspace-footer", "Concept built for RudCo · Get Hired Hack, 2026-10-10"
  end

  test "branding preserves catalog navigation and sample status words" do
    post demo_quotes_path
    follow_redirect!
    assert_response :success

    assert_select ".sidebar__nav a[href=?]", catalog_matches_path, "Find catalog item"
    assert_select ".sidebar__nav a[href=?]", new_quote_path, "New RFQ"
    assert_select ".sidebar__mark", count: 0
    assert_select ".status--ready", text: "Ready", minimum: 1
    assert_select ".status--needs-buyer", text: "Needs the buyer", minimum: 1
    assert_select ".status--no-match", text: "No match", minimum: 1
    assert_select ".sample-banner", minimum: 1
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
