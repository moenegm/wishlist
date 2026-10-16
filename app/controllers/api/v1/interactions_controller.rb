module Api
  module V1
    class InteractionsController < BaseController
      def like
        SocialActions.like(@current_user, target)
        head :no_content
      end

      def unlike
        @current_user.likes.find_by(likeable: target)&.destroy!
        head :no_content
      end

      def comments
        render json: page(target.comments.order(created_at: :desc)).map { |comment| comment_json(comment) }
      end

      def comment
        render json: comment_json(SocialActions.comment(@current_user, target, params.require(:body))), status: :created
      end

      def destroy_comment
        @current_user.comments.find(params[:id]).destroy!
        head :no_content
      end

      private

      def comment_json(comment)
        { id: comment.id, body: comment.body, user: person(comment.user), created_at: comment.created_at.iso8601 }
      end
    end
  end
end
