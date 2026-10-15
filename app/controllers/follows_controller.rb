class FollowsController < ApplicationController
  before_action :authenticate_user!

  def create
    person = User.find(params[:followed_user_id])
    follow = current_user.follows_as_follower.find_or_initialize_by(followed_user: person)
    new_follow = follow.new_record?

    if follow.save
      if new_follow && person != current_user
        Notification.create!(recipient: person, actor: current_user, event_type: "followed", notifiable: follow)
      end
      redirect_back fallback_location: user_path(current_user), notice: "You’re now following #{person.first_name.presence || 'this person'}."
    else
      redirect_back fallback_location: user_path(current_user), alert: "You can’t follow your own profile."
    end
  end

  def destroy
    follow = current_user.follows_as_follower.find(params[:id])
    follow.destroy!
    redirect_back fallback_location: user_path(current_user), notice: "You unfollowed #{follow.followed_user.first_name.presence || 'this person'}."
  end
end
