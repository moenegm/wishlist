class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    @own_profile = user_signed_in? && @user.id == current_user.id
    @public_wlists = @user.wlists.publicly_visible.includes(:wishes).order(created_at: :desc)

    raise ActiveRecord::RecordNotFound if !@own_profile && @public_wlists.empty? && !user_signed_in?

    @wlists = if @own_profile
      @user.wlists.includes(:wishes).order(created_at: :desc)
    else
      @public_wlists
    end

    @follow = current_user&.follows_as_follower&.find_by(followed_user: @user) unless @own_profile

    if @own_profile
      @query = params[:q].to_s.strip
      @people = if @query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        User.where.not(id: current_user.id)
          .where("first_name ILIKE :query OR last_name ILIKE :query", query: pattern)
          .includes(:avatar_attachment)
          .order(:first_name, :last_name)
          .limit(12)
      else
        User.none
      end
      @followers = @user.followers.includes(:avatar_attachment).order(:first_name, :last_name)
      @following = @user.following_users.includes(:avatar_attachment).order(:first_name, :last_name)
    end
  end
end
