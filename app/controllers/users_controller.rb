class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    @own_profile = user_signed_in? && @user.id == current_user.id
    @public_wlists = @user.wlists.publicly_visible.includes(:wishes).order(created_at: :desc)

    raise ActiveRecord::RecordNotFound if !@own_profile && @public_wlists.empty?

    @wlists = if @own_profile
      @user.wlists.includes(:wishes).order(created_at: :desc)
    else
      @public_wlists
    end

    @follow = current_user&.follows_as_follower&.find_by(followed_user: @user) unless @own_profile
  end
end
