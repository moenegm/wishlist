class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :event_type, inclusion: { in: %w[followed added_wish liked_wish liked_wlist commented_wish commented_wlist] }

  scope :unread, -> { where(read_at: nil) }

  def message
    name = [actor.first_name, actor.last_name].compact_blank.join(" ").presence || "A Wishwell member"
    subject = case notifiable
    when Wish then "your wish ‘#{notifiable.title}’"
    when Wlist then "your wishlist ‘#{notifiable.title}’"
    when Comment
      commentable = notifiable.commentable
      commentable.is_a?(Wish) ? "your wish ‘#{commentable.title}’" : "your wishlist ‘#{commentable.title}’"
    else
      nil
    end

    case event_type
    when "followed" then "#{name} followed you"
    when "added_wish" then "#{name} added a wish to ‘#{notifiable&.wlist&.title || 'a public wishlist'}’"
    when "liked_wish" then "#{name} liked #{subject || 'your wish'}"
    when "liked_wlist" then "#{name} liked #{subject || 'your wishlist'}"
    when "commented_wish" then "#{name} commented on #{subject || 'your wish'}"
    when "commented_wlist" then "#{name} commented on #{subject || 'your wishlist'}"
    else "#{name} interacted with you"
    end
  end

  def destination_path
    return Rails.application.routes.url_helpers.user_path(actor) if event_type == "followed"

    target_list = case notifiable
    when Wlist then notifiable
    when Wish then notifiable.wlist
    when Comment
      commentable = notifiable.commentable
      commentable.is_a?(Wish) ? commentable.wlist : commentable
    end
    target_list ? Rails.application.routes.url_helpers.wlist_path(target_list) : Rails.application.routes.url_helpers.user_path(actor)
  end
end
