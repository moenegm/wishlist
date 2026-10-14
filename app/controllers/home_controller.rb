class HomeController < ApplicationController
  before_action :authenticate_user!
  def index
    @wlists = current_user.wlists.includes(:wishes).order(created_at: :desc)
    @wishes = current_user.wishes.includes(:wlist).order(created_at: :desc).limit(6)
  end
end
