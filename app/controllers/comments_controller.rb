class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    commentable = find_commentable
    ensure_commentable_is_visible!(commentable)
    SocialActions.comment(current_user, commentable, params.dig(:comment, :body))
    redirect_back fallback_location: social_fallback(commentable)
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: social_fallback(commentable), alert: error.record.errors.full_messages.to_sentence
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
    ContentAccess.ensure!(commentable, current_user)
  end

  def commentable_owner(commentable)
    commentable.is_a?(Wlist) ? commentable.user : commentable.user
  end

  def social_fallback(commentable)
    list = commentable.is_a?(Wlist) ? commentable : commentable.wlist
    wlist_path(list)
  end
end
