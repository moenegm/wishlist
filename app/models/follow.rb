class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed_user, class_name: "User"

  validates :followed_user_id, uniqueness: { scope: :follower_id }
  validate :cannot_follow_self

  private

  def cannot_follow_self
    errors.add(:followed_user, "can't be yourself") if follower_id.present? && follower_id == followed_user_id
  end
end
