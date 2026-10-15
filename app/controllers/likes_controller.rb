class LikesController < ApplicationController
  before_action :authenticate_user!

  def create
    likeable = find_likeable
    ensure_likeable_is_visible!(likeable)
    like = current_user.likes.find_or_initialize_by(likeable: likeable)
    new_like = like.new_record?

    if like.save
      owner = likeable_owner(likeable)
      if new_like && owner != current_user
        event_type = likeable.is_a?(Wish) ? "liked_wish" : "liked_wlist"
        Notification.create!(recipient: owner, actor: current_user, event_type: event_type, notifiable: likeable)
      end
      redirect_back fallback_location: social_fallback(likeable)
    else
      redirect_back fallback_location: social_fallback(likeable), alert: "That like couldn’t be saved."
    end
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
    list = likeable.is_a?(Wlist) ? likeable : likeable.wlist
    return if list.is_public? || list.user_id == current_user.id

    raise ActiveRecord::RecordNotFound
  end

  def likeable_owner(likeable)
    likeable.is_a?(Wlist) ? likeable.user : likeable.user
  end

  def social_fallback(likeable)
    list = likeable.is_a?(Wlist) ? likeable : likeable.wlist
    wlist_path(list)
  end
end
