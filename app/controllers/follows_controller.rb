class FollowsController < ApplicationController
  before_action :authenticate_user!

  def create
    person = User.find(params[:followed_user_id])
    SocialActions.follow(current_user, person)
    redirect_back fallback_location: user_path(current_user), notice: "You’re now following #{person.first_name.presence || 'this person'}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: user_path(current_user), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    follow = current_user.follows_as_follower.find(params[:id])
    follow.destroy!
    redirect_back fallback_location: user_path(current_user), notice: "You unfollowed #{follow.followed_user.first_name.presence || 'this person'}."
  end
end
