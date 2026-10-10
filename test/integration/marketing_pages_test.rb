require "test_helper"

class MarketingPagesTest < ActionDispatch::IntegrationTest
  test "marketing entry points render without creating a quote or buyer workspace" do
    [product_path, comparison_path].each do |path|
      assert_no_difference ["Quote.count", "Client.count"] do
        get path
      end
      assert_response :success
      assert_select "h1", count: 1
      assert_select "main#main[tabindex='-1']"
      assert_select 'nav[aria-label="Product"] a[aria-current="page"][href=?]', path
      assert_select 'nav[aria-label="Product"] a[href=?]', quotes_path
      assert_select ".sidebar", count: 0
      assert_select "form", count: 0
    end
  end

  test "product shows the local screenshot and comparison links directly to vendor evidence" do
    get product_path
    assert_select 'img.marketing-image[alt][width="1280"][height="720"]' do |images|
      assert_match %r{/assets/marketing-quote-review(?:-[a-f0-9]+)?\.png}, images.first["src"]
    end
    assert_select 'a[href=?]', comparison_path, minimum: 1
    get comparison_path
    %w[https://www.proton.ai/order-and-quote-entry https://www.canals.ai/ https://noxmetals.co/quote].each do |url|
      assert_select "a[href=?]", url, minimum: 1
    end
    assert_select "table caption"
    assert_select "table th[scope='row']", count: 4
  end
end
