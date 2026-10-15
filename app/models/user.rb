class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one_attached :avatar

  has_many :wishes, dependent: :destroy
  has_many :wlists, dependent: :destroy

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :following_users, through: :follows_as_follower, source: :followed_user
  has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_user_id, dependent: :destroy
  has_many :followers, through: :follows_as_followed, source: :follower

  def following?(user)
    follows_as_follower.exists?(followed_user: user)
  end
end
