require "test_helper"

class WlistsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @wlist = wlists(:one)
  end

  test "should get index" do
    get wlists_url
    assert_response :success
  end

  test "should get new" do
    get new_wlist_url
    assert_response :success
  end

  test "should create wlist" do
    assert_difference("Wlist.count") do
      post wlists_url, params: { wlist: { title: @wlist.title, type: @wlist.wl_category, user_id: @wlist.user_id } }
    end

    assert_redirected_to wlist_url(Wlist.last)
  end

  test "should show wlist" do
    get wlist_url(@wlist)
    assert_response :success
  end

  test "should get edit" do
    get edit_wlist_url(@wlist)
    assert_response :success
  end

  test "should update wlist" do
    patch wlist_url(@wlist), params: { wlist: { title: @wlist.title, type: @wlist.wl_category, user_id: @wlist.user_id } }
    assert_redirected_to wlist_url(@wlist)
  end

  test "should destroy wlist" do
    assert_difference("Wlist.count", -1) do
      delete wlist_url(@wlist)
    end

    assert_redirected_to wlists_url
  end
end
