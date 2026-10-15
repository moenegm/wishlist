class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    commentable = find_commentable
    ensure_commentable_is_visible!(commentable)
    comment = current_user.comments.new(commentable: commentable, body: params.dig(:comment, :body))

    if comment.save
      owner = commentable_owner(commentable)
      if owner != current_user
        event_type = commentable.is_a?(Wish) ? "commented_wish" : "commented_wlist"
        Notification.create!(recipient: owner, actor: current_user, event_type: event_type, notifiable: comment)
      end
      redirect_back fallback_location: social_fallback(commentable)
    else
      redirect_back fallback_location: social_fallback(commentable), alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    comment = current_user.comments.find(params[:id])
    commentable = comment.commentable
    comment.destroy!
    redirect_back fallback_location: social_fallback(commentable)
  end

  private

  def find_commentable
    model = { "Wish" => Wish, "Wlist" => Wlist }[params[:commentable_type]]
    raise ActiveRecord::RecordNotFound unless model

    model.find(params[:commentable_id])
  end

  def ensure_commentable_is_visible!(commentable)
    list = commentable.is_a?(Wlist) ? commentable : commentable.wlist
    return if list.is_public? || list.user_id == current_user.id

    raise ActiveRecord::RecordNotFound
  end

  def commentable_owner(commentable)
    commentable.is_a?(Wlist) ? commentable.user : commentable.user
  end

  def social_fallback(commentable)
    list = commentable.is_a?(Wlist) ? commentable : commentable.wlist
    wlist_path(list)
  end
end
