require "test_helper"

class WishFulfillmentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @owner = User.create!(email: "owner@example.test", password: "password123")
    @other = User.create!(email: "other@example.test", password: "password123")
    @list = @owner.wlists.create!(title: "Birthday", is_public: true)
    @wish = @owner.wishes.create!(title: "Book", wlist: @list)
  end

  test "owner can fulfill and restore without deleting or notifying" do
    sign_in @owner, scope: :user
    assert_not @wish.fulfilled?
    assert_no_difference ["Wish.count", "Notification.count"] do
      patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: true } }, as: :json
    end
    assert_response :success
    assert_equal true, response.parsed_body["fulfilled"]
    assert @wish.reload.fulfilled?
    patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: true } }, as: :json
    assert @wish.reload.fulfilled?, "repeated requests must not toggle the state"
    patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: false } }, as: :json
    assert_response :success
    assert_not @wish.reload.fulfilled?
  end

  test "another member cannot change fulfillment even on a public wish" do
    sign_in @other, scope: :user
    patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: true } }
    assert_response :not_found
    assert_not @wish.reload.fulfilled?
  end

  test "anonymous visitors cannot change fulfillment" do
    patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: true } }
    assert_redirected_to new_user_session_path
    assert_not @wish.reload.fulfilled?
  end

  test "public visitors see status without controls and private wishes stay hidden" do
    @wish.update!(fulfilled: true)
    get wish_path(@wish)
    assert_response :success
    assert_select ".wish-fulfilled .fulfillment-status", text: /Fulfilled/
    assert_select "form[action=?]", fulfillment_wish_path(@wish), count: 0
    @list.update!(is_public: false)
    get wish_path(@wish)
    assert_response :not_found
  end

  test "owner sees controls on the card and detail" do
    sign_in @owner, scope: :user
    get wlist_path(@list)
    assert_response :success
    assert_select "form[action=?]", fulfillment_wish_path(@wish), count: 1
    get wish_path(@wish)
    assert_select "button[aria-pressed=false]", text: /Mark fulfilled/
  end

  test "invalid status cannot change a wish" do
    sign_in @owner, scope: :user
    patch fulfillment_wish_path(@wish), params: { wish: { fulfilled: "perhaps" } }, as: :json
    assert_response :unprocessable_entity
    assert_not @wish.reload.fulfilled?
  end
end
