class Wlist < ApplicationRecord
  belongs_to :user
  has_many :wishes, foreign_key: :wlists_id, dependent: :restrict_with_error
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  scope :publicly_visible, -> { where(is_public: true) }

  validates :title, presence: true
end
