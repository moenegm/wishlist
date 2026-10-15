class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @notifications = current_user.received_notifications.includes(:actor, :notifiable).order(created_at: :desc).limit(100)
    current_user.received_notifications.unread.update_all(read_at: Time.current)
  end
end
