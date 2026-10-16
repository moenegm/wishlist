require "test_helper"

class MobileApiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @owner = User.create!(email: "mobile-owner@example.test", password: "password123", first_name: "Owner")
    @other = User.create!(email: "mobile-other@example.test", password: "password123", first_name: "Other")
    @private = @owner.wlists.create!(title: "Secret", is_public: false)
    @public = @owner.wlists.create!(title: "Public", is_public: true)
    @wish = @owner.wishes.create!(title: "Private chair", wlist: @private)
    @session, @token = MobileSession.issue!(@owner)
    @other_session, @other_token = MobileSession.issue!(@other)
  end

  def auth(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "existing credentials sign in and token is hashed revocable and expires" do
    post "/api/v1/session", params: { email: @owner.email, password: "password123" }, as: :json
    assert_response :success
    token = response.parsed_body["token"]
    assert token.present?
    assert_not MobileSession.exists?(token_digest: token)
    get "/api/v1/me", headers: auth(token)
    assert_response :success
    assert_equal @owner.email, response.parsed_body["email"]
    delete "/api/v1/session", headers: auth(token)
    assert_response :no_content
    get "/api/v1/me", headers: auth(token)
    assert_response :unauthorized
    @session.update!(expires_at: 1.second.ago)
    get "/api/v1/me", headers: auth
    assert_response :unauthorized
  end

  test "password changes invalidate mobile sessions" do
    @owner.update!(password: "newPassword123")
    get "/api/v1/me", headers: auth
    assert_response :unauthorized
  end

  test "private records cannot be guessed by another user" do
    ["/api/v1/wlists/#{@private.id}", "/api/v1/wishes/#{@wish.id}"].each do |path|
      get path, headers: auth(@other_token)
      assert_response :not_found
    end
    patch "/api/v1/wishes/#{@wish.id}", params: { wish: { fulfilled: true } }, headers: auth(@other_token), as: :json
    assert_response :not_found
    post "/api/v1/like", params: { target_type: "Wish", target_id: @wish.id }, headers: auth(@other_token), as: :json
    assert_response :not_found
    get "/api/v1/people/#{@owner.id}", headers: auth(@other_token)
    assert_equal [@public.id], response.parsed_body["wlists"].map { |l| l["id"] }
    assert_nil response.parsed_body["user"]["email"]
  end

  test "creation shares records and three options with website" do
    post "/api/v1/wishes", params: { wish: { title: "Lamp", wlists_id: @private.id, location: "First", price: "10", location_2: "Second", price_2: "20", location_3: "Third", price_3: "30" } }, headers: auth, as: :json
    assert_response :created
    id = response.parsed_body["id"]
    assert_equal 3, response.parsed_body["purchase_options"].size
    patch "/api/v1/wishes/#{id}", params: { wish: { fulfilled: true } }, headers: auth, as: :json
    assert_response :success
    assert Wish.find(id).fulfilled?
    patch "/api/v1/wishes/#{id}", params: { wish: { wlists_id: @other.wlists.create!(title: "Other").id } }, headers: auth, as: :json
    assert_response :not_found
  end

  test "follow like and comment create one notification and reading is explicit" do
    post "/api/v1/people/#{@owner.id}/follow", headers: auth(@other_token)
    assert_response :no_content
    post "/api/v1/people/#{@owner.id}/follow", headers: auth(@other_token)
    assert_equal 1, @owner.received_notifications.count
    2.times { post "/api/v1/like", params: { target_type: "Wlist", target_id: @public.id }, headers: auth(@other_token), as: :json; assert_response :no_content }
    assert_equal 2, @owner.received_notifications.count
    post "/api/v1/comments", params: { target_type: "Wlist", target_id: @public.id, body: "Lovely" }, headers: auth(@other_token), as: :json
    assert_response :created
    get "/api/v1/notifications", headers: auth
    assert_response :success
    assert_equal 3, response.parsed_body["unread_count"]
    assert_equal 3, @owner.received_notifications.unread.count
    patch "/api/v1/notifications/read", params: { ids: @owner.received_notifications.pluck(:id) }, headers: auth, as: :json
    assert_response :no_content
    assert_equal 0, @owner.received_notifications.unread.count
  end

  test "historical notification hides newly private content" do
    @other.following_users << @owner
    post "/api/v1/wishes", params: { wish: { title: "Surprise", wlists_id: @public.id } }, headers: auth, as: :json
    assert_response :created
    @public.update!(is_public: false)
    get "/api/v1/notifications", headers: auth(@other_token)
    row = response.parsed_body["notifications"].first
    assert_equal "An update is no longer available.", row["message"]
    assert_nil row["wlist_id"]
  end

  test "unauthenticated calls and empty list deletion are handled" do
    get "/api/v1/wlists"
    assert_response :unauthorized
    delete "/api/v1/wlists/#{@private.id}", headers: auth
    assert_response :unprocessable_entity
    delete "/api/v1/wlists/#{@public.id}", headers: auth
    assert_response :no_content
  end
  test "credential changes require current password and revoke old sessions" do
    patch "/api/v1/me/credentials", params: { email: "changed@example.test", current_password: "wrong" }, headers: auth, as: :json
    assert_response :unprocessable_entity
    assert_equal "mobile-owner@example.test", @owner.reload.email
    patch "/api/v1/me/credentials", params: { email: "changed@example.test", current_password: "password123", password: "newPassword123", password_confirmation: "newPassword123" }, headers: auth, as: :json
    assert_response :success
    fresh = response.parsed_body["token"]
    get "/api/v1/me", headers: auth
    assert_response :unauthorized
    get "/api/v1/me", headers: auth(fresh)
    assert_response :success
    assert_equal "changed@example.test", response.parsed_body["email"]
  end

  test "comments and read markers cannot mutate another members data" do
    comment = SocialActions.comment(@other, @public, "Hello")
    delete "/api/v1/comments/#{comment.id}", headers: auth
    assert_response :not_found
    notification = @owner.received_notifications.last
    patch "/api/v1/notifications/read", params: { ids: [notification.id] }, headers: auth(@other_token), as: :json
    assert_response :no_content
    assert_nil notification.reload.read_at
  end

  test "web and API social actions share notification semantics" do
    sign_in @other, scope: :user
    post "/likes", params: { likeable_type: "Wlist", likeable_id: @public.id }
    assert_response :redirect
    post "/api/v1/like", params: { target_type: "Wlist", target_id: @public.id }, headers: auth(@other_token), as: :json
    assert_response :no_content
    assert_equal 1, @owner.received_notifications.where(event_type: "liked_wlist").count
    post "/comments", params: { commentable_type: "Wlist", commentable_id: @public.id, comment: { body: "From the website" } }
    assert_response :redirect
    get "/api/v1/comments", params: { target_type: "Wlist", target_id: @public.id }, headers: auth
    assert_equal "From the website", response.parsed_body.first["body"]
  end

  test "invalid visibility and fulfillment are validation errors" do
    patch "/api/v1/wishes/#{@wish.id}", params: { wish: { fulfilled: nil } }, headers: auth, as: :json
    assert_response :unprocessable_entity
    patch "/api/v1/wlists/#{@private.id}", params: { wlist: { is_public: nil } }, headers: auth, as: :json
    assert_response :unprocessable_entity
  end

  test "account deletion needs password and removes associated content and sessions" do
    delete "/api/v1/me", params: { password: "wrong" }, headers: auth, as: :json
    assert_response :unprocessable_entity
    delete "/api/v1/me", params: { password: "password123" }, headers: auth, as: :json
    assert_response :no_content
    assert_not User.exists?(@owner.id)
    assert_not Wish.exists?(@wish.id)
    assert_not MobileSession.exists?(@session.id)
  end

  test "profile photo upload stays behind Rails and validates image bytes" do
    image = Rack::Test::UploadedFile.new(Rails.root.join("ios/Wishwell/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), "image/png")
    post "/api/v1/me/avatar", params: { avatar: image }, headers: auth
    assert_response :success
    assert @owner.reload.avatar.attached?
    assert response.parsed_body["avatar_url"].include?("/rails/active_storage/")
    fake = Rack::Test::UploadedFile.new(Rails.root.join("README.md"), "image/jpeg")
    post "/api/v1/me/avatar", params: { avatar: fake }, headers: auth
    assert_response :unprocessable_entity
    post "/api/v1/me/avatar", params: { avatar: "not an upload" }, headers: auth, as: :json
    assert_response :unprocessable_entity
  end

  test "registration joins the existing Rails user community" do
    post "/api/v1/register", params: { email: "new-mobile@example.test", first_name: "New", password: "password123", password_confirmation: "password123" }, as: :json
    assert_response :success
    token = response.parsed_body["token"]
    user = User.find_by!(email: "new-mobile@example.test")
    assert user.valid_password?("password123")
    get "/api/v1/people", params: { q: "Owner" }, headers: auth(token)
    assert_response :success
    assert_equal [@owner.id], response.parsed_body.map { |person| person["id"] }
  end

end
