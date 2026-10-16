module Api
  module V1
    class NotificationsController < BaseController
      def index
        render json: { unread_count: @current_user.received_notifications.unread.count,
          notifications: page(@current_user.received_notifications.includes(:actor, :notifiable).order(created_at: :desc, id: :desc)).map { |notification|
            { id: notification.id, message: notification.message, event_type: notification.event_type,
              actor_id: notification.actor_id, wlist_id: notification.content_visible? ? notification.target_list&.id : nil,
              read: notification.read_at.present?, created_at: notification.created_at.iso8601 }
          } }
      end

      def read
        @current_user.received_notifications.where(id: Array(params.require(:ids)).first(100)).unread.update_all(read_at: Time.current)
        head :no_content
      end
    end
  end
end
