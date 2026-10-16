class HomeController < ApplicationController
  before_action :authenticate_user!
  def index
    @wlists = current_user.wlists.includes(:wishes).order(created_at: :desc)
    @wishes = current_user.wishes.includes(:wlist).order(created_at: :desc).limit(6)
    @public_wlists = current_user.wlists.publicly_visible.includes(:wishes).order(created_at: :desc)
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
    @followers = current_user.followers.includes(:avatar_attachment).order(:first_name, :last_name)
    @following = current_user.following_users.includes(:avatar_attachment).order(:first_name, :last_name)
  end
end
