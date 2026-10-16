module Api
  module V1
    class WishesController < BaseController
      def show
        render json: wish_json(ContentAccess.ensure!(Wish.find(params[:id]), @current_user))
      end

      def create
        wish = @current_user.wishes.new(wish_params.except(:wlists_id))
        wish.wlist = @current_user.wlists.find(wish_params[:wlists_id])
        Wish.transaction do
          wish.save!
          SocialActions.notify_public_wish(wish)
        end
        render json: wish_json(wish), status: :created
      end

      def update
        wish = @current_user.wishes.find(params[:id])
        attributes = wish_params
        wish.wlist = @current_user.wlists.find(attributes[:wlists_id]) if attributes.key?(:wlists_id)
        wish.update!(attributes.except(:wlists_id))
        render json: wish_json(wish)
      end

      def destroy
        @current_user.wishes.find(params[:id]).destroy!
        head :no_content
      end

      private

      def wish_params
        params.require(:wish).permit(:title, :wlists_id, :location, :price, :location_2, :price_2, :location_3, :price_3, :fulfilled)
      end
    end
  end
end
