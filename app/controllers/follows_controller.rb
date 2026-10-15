class FollowsController < ApplicationController
  before_action :authenticate_user!

  def create
    person = User.find(params[:followed_user_id])
    follow = current_user.follows_as_follower.find_or_initialize_by(followed_user: person)

    if follow.save
      redirect_back fallback_location: people_path, notice: "You’re now following #{person.first_name.presence || 'this person'}."
    else
      redirect_back fallback_location: people_path, alert: "You can’t follow your own profile."
    end
  end

  def destroy
    follow = current_user.follows_as_follower.find(params[:id])
    follow.destroy!
    redirect_back fallback_location: people_path, notice: "You unfollowed #{follow.followed_user.first_name.presence || 'this person'}."
  end
end
