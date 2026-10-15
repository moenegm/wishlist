class PeopleController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = params[:q].to_s.strip
    people = User.where.not(id: current_user.id)
    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      people = people.where("users.first_name ILIKE :query OR users.last_name ILIKE :query", query: pattern)
    end
    @people = people.includes(:wlists, :avatar_attachment).order(:first_name, :last_name).limit(30)
    @following = current_user.following_users.includes(wlists: :wishes).order(:first_name, :last_name)
  end
end
