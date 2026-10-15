class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  has_many :notifications, as: :notifiable, dependent: :nullify

  validates :body, presence: true, length: { maximum: 500 }
end
