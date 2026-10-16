class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    likeable = find_likeable
    ensure_likeable_is_visible!(likeable)
    SocialActions.like(current_user, likeable)
    redirect_back fallback_location: social_fallback(likeable)
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: social_fallback(likeable), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    like = current_user.likes.find(params[:id])
    likeable = like.likeable
    like.destroy!
    redirect_back fallback_location: social_fallback(likeable)
  end

  private

  def find_likeable
    model = { "Wish" => Wish, "Wlist" => Wlist }[params[:likeable_type]]
    raise ActiveRecord::RecordNotFound unless model

    model.find(params[:likeable_id])
  end

  def ensure_likeable_is_visible!(likeable)
    ContentAccess.ensure!(likeable, current_user)
  end

  def likeable_owner(likeable)
    likeable.is_a?(Wlist) ? likeable.user : likeable.user
  end

  def social_fallback(likeable)
    list = likeable.is_a?(Wlist) ? likeable : likeable.wlist
    wlist_path(list)
  end
end
