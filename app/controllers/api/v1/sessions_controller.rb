module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_mobile!, only: %i[create register recover]
      rate_limit to: 10, within: 1.minute, only: %i[create register recover], store: ActiveSupport::Cache::MemoryStore.new

      def create
        user = User.find_for_database_authentication(email: params.require(:email).to_s.strip.downcase)
        unless user&.valid_password?(params.require(:password))
          return render json: { error: "Email or password is incorrect." }, status: :unauthorized
        end
        issue(user)
      end

      def register
        user = User.create!(params.permit(:email, :password, :password_confirmation, :first_name, :last_name))
        issue(user)
      end

      def recover
        User.send_reset_password_instructions(email: params.require(:email))
        render json: { message: "If that account exists, password recovery instructions will be sent." }
      end

      def destroy
        @mobile_session.destroy!
        head :no_content
      end

      private

      def issue(user)
        session, token = MobileSession.issue!(user)
        @current_user = user
        response.set_header("Cache-Control", "no-store")
        render json: { token: token, expires_at: session.expires_at.iso8601, user: person(user, own: true) }
      end
    end
  end
end
