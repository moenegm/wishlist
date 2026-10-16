require "test_helper"

class WishOptionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @owner = User.create!(email: "options@example.test", password: "password123")
    @other = User.create!(email: "visitor@example.test", password: "password123")
    @list = @owner.wlists.create!(title: "Home", is_public: true)
    @wish = @owner.wishes.create!(title: "Chair", wlist: @list, location: "Original store", price: 120)
    sign_in @owner, scope: :user
  end

  test "existing details remain option one and three options save and serialize" do
    assert_equal [{ location: "Original store", price: BigDecimal("120") }], @wish.purchase_options
    patch wish_path(@wish), params: { wish: { location_2: "https://example.com/chair", price_2: "99.95", location_3: "Other store", price_3: "0" } }, as: :json
    assert_response :success
    assert_equal 3, response.parsed_body["purchase_options"].size
    assert_equal "Original store", @wish.reload.location
    assert_equal BigDecimal("99.95"), @wish.price_2
    assert_equal BigDecimal("0"), @wish.price_3
    get wish_path(@wish)
    assert_response :success
    assert_select "a[href=?][rel=?]", "https://example.com/chair", "noopener noreferrer"
    assert_select ".wish-purchase-option", count: 3
  end

  test "extra options can be removed and do not leave empty rows" do
    @wish.update!(location_2: "Store two", price_2: 50)
    patch wish_path(@wish), params: { wish: { location_2: "", price_2: "" } }, as: :json
    assert_response :success
    assert_nil @wish.reload.price_2
    assert_equal 1, @wish.purchase_options.size
  end

  test "negative alternative prices fail without changing saved data" do
    [2, 3].each do |number|
      patch wish_path(@wish), params: { wish: { "price_#{number}" => "-1" } }, as: :json
      assert_response :unprocessable_entity
      assert_nil @wish.reload.public_send("price_#{number}")
    end
  end

  test "other members cannot edit options" do
    sign_in @other, scope: :user
    patch wish_path(@wish), params: { wish: { location_2: "Unauthorized" } }, as: :json
    assert_response :not_found
    assert_nil @wish.reload.location_2
  end

  test "unsafe link schemes render as text and private options are inaccessible" do
    @wish.update!(location_2: "javascript:alert(1)")
    sign_out :user
    get wish_path(@wish)
    assert_response :success
    assert_select "a[href^='javascript:']", count: 0
    assert_select ".wish-option-location", text: "javascript:alert(1)"
    @list.update!(is_public: false)
    get wish_path(@wish)
    assert_response :not_found
  end

  test "new wish accepts all three options" do
    assert_difference "Wish.count", 1 do
      post wishes_path, params: { wish: { title: "Lamp", wlists_id: @list.id, location: "First", price: "30", location_2: "Second", price_2: "40", location_3: "Third", price_3: "50" } }, as: :json
    end
    assert_response :created
    assert_equal 3, Wish.find(response.parsed_body["id"]).purchase_options.size
  end
end
