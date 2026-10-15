class Wlist < ApplicationRecord
  belongs_to :user
  has_many :wishes, foreign_key: :wlists_id, dependent: :restrict_with_error

  scope :publicly_visible, -> { where(is_public: true) }

  validates :title, presence: true
end
