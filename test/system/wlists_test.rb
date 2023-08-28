require "application_system_test_case"

class WlistsTest < ApplicationSystemTestCase
  setup do
    @wlist = wlists(:one)
  end

  test "visiting the index" do
    visit wlists_url
    assert_selector "h1", text: "Wlists"
  end

  test "should create wlist" do
    visit wlists_url
    click_on "New wlist"

    fill_in "Title", with: @wlist.title
    fill_in "Type", with: @wlist.wl_category
    fill_in "User", with: @wlist.user_id
    click_on "Create Wlist"

    assert_text "Wlist was successfully created"
    click_on "Back"
  end

  test "should update Wlist" do
    visit wlist_url(@wlist)
    click_on "Edit this wlist", match: :first

    fill_in "Title", with: @wlist.title
    fill_in "Type", with: @wlist.wl_category
    fill_in "User", with: @wlist.user_id
    click_on "Update Wlist"

    assert_text "Wlist was successfully updated"
    click_on "Back"
  end

  test "should destroy Wlist" do
    visit wlist_url(@wlist)
    click_on "Destroy this wlist", match: :first

    assert_text "Wlist was successfully destroyed"
  end
end
