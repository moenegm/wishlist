module Api
  module V1
    class BaseController < ActionController::API
      before_action :require_api_enabled
      before_action :authenticate_mobile!
      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "Not found." }, status: :not_found
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
      rescue_from ActionController::ParameterMissing do |error|
        render json: { error: error.message }, status: :bad_request
      end

      private

      def require_api_enabled
        head :not_found if Rails.env.production? && ENV["MOBILE_API_ENABLED"] != "true"
      end

      def authenticate_mobile!
        scheme, token = request.authorization.to_s.split(" ", 2)
        @mobile_session = MobileSession.authenticate(token) if scheme == "Bearer"
        @current_user = @mobile_session&.user
        render json: { error: "Please sign in again." }, status: :unauthorized unless @current_user
      end

      def page(scope)
        scope.limit(40).offset([params[:page].to_i - 1, 0].max * 40)
      end

      def person(user, own: false)
        result = { id: user.id, first_name: user.first_name.to_s, last_name: user.last_name.to_s,
          avatar_url: user.avatar.attached? ? rails_blob_url(user.avatar) : nil,
          following: @current_user&.following?(user) || false,
          followers_count: user.followers.count, following_count: user.following_users.count }
        result[:email] = user.email if own
        result
      end

      def social(target)
        { likes_count: target.likes.count, liked: @current_user.likes.exists?(likeable: target), comments_count: target.comments.count }
      end

      def wish_json(wish)
        { id: wish.id, title: wish.title, user_id: wish.user_id, wlist_id: wish.wlists_id,
          fulfilled: wish.fulfilled?, purchase_options: wish.purchase_options,
          updated_at: wish.updated_at.iso8601 }.merge(social(wish))
      end

      def list_json(list, detail: false)
        result = { id: list.id, title: list.title, user_id: list.user_id, category: list.wl_category.to_s,
          is_public: list.is_public?, wishes_count: list.wishes.count, owner: person(list.user) }.merge(social(list))
        result[:wishes] = list.wishes.order(created_at: :desc).map { |wish| wish_json(wish) } if detail
        result
      end

      def target
        model = { "Wish" => Wish, "Wlist" => Wlist }[params.require(:target_type)]
        raise ActiveRecord::RecordNotFound unless model
        ContentAccess.ensure!(model.find(params.require(:target_id)), @current_user)
      end
    end
  end
end
