module Api
  module V1
    class PeopleController < BaseController
      def index
        scope = case params[:group]
        when "followers" then @current_user.followers
        when "following" then @current_user.following_users
        else
          query = params[:q].to_s.strip
          if query.empty?
            User.none
          else
            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
            User.where.not(id: @current_user.id).where("first_name ILIKE :q OR last_name ILIKE :q", q: pattern)
          end
        end
        render json: page(scope.order(:first_name, :id)).map { |user| person(user) }
      end

      def show
        user = User.find(params[:id])
        lists = user == @current_user ? user.wlists : user.wlists.publicly_visible
        render json: { user: person(user), wlists: page(lists.order(created_at: :desc)).map { |list| list_json(list) } }
      end

      def follow
        SocialActions.follow(@current_user, User.find(params[:id]))
        head :no_content
      end

      def unfollow
        @current_user.follows_as_follower.find_by(followed_user_id: params[:id])&.destroy!
        head :no_content
      end
    end
  end
end
