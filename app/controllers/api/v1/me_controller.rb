module Api
  module V1
    class MeController < BaseController
      def show
        render json: person(@current_user, own: true)
      end

      def update
        @current_user.update!(params.permit(:first_name, :last_name))
        render json: person(@current_user, own: true)
      end

      def credentials
        attributes = params.permit(:email, :password, :password_confirmation, :current_password)
        User.transaction do
          unless @current_user.update_with_password(attributes)
            raise ActiveRecord::RecordInvalid, @current_user
          end
          @current_user.mobile_sessions.destroy_all
          session, token = MobileSession.issue!(@current_user)
          response.set_header("Cache-Control", "no-store")
          render json: { token: token, expires_at: session.expires_at.iso8601, user: person(@current_user, own: true) }
        end
      end

      def avatar
        file = params.require(:avatar)
        unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.size <= 5.megabytes && %w[image/jpeg image/png image/webp image/heic].include?(Marcel::MimeType.for(file.tempfile))
          return render json: { error: "Choose a JPEG, PNG, WebP, or HEIC photo under 5 MB." }, status: :unprocessable_entity
        end
        @current_user.avatar.attach(file)
        render json: person(@current_user, own: true)
      end

      def destroy
        unless @current_user.valid_password?(params.require(:password))
          return render json: { error: "Password is incorrect." }, status: :unprocessable_entity
        end
        @current_user.destroy!
        head :no_content
      end
    end
  end
end
