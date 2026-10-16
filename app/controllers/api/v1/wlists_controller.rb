module Api
  module V1
    class WlistsController < BaseController
      def index
        scope = params[:feed] == "following" ? Wlist.publicly_visible.where(user_id: @current_user.following_users.select(:id)) : @current_user.wlists
        render json: page(scope.order(created_at: :desc)).map { |list| list_json(list) }
      end

      def show
        render json: list_json(ContentAccess.ensure!(Wlist.find(params[:id]), @current_user), detail: true)
      end

      def create
        render json: list_json(@current_user.wlists.create!(list_params), detail: true), status: :created
      end

      def update
        list = @current_user.wlists.find(params[:id])
        list.update!(list_params)
        render json: list_json(list, detail: true)
      end

      def destroy
        list = @current_user.wlists.find(params[:id])
        if list.destroy
          head :no_content
        else
          render json: { error: "Delete the wishes before deleting this wishlist." }, status: :unprocessable_entity
        end
      end

      private

      def list_params
        params.require(:wlist).permit(:title, :wl_category, :is_public)
      end
    end
  end
end
