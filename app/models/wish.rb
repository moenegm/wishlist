class Wish < ApplicationRecord
  belongs_to :user
  belongs_to :wlist, class_name: "Wlist", foreign_key: :wlists_id

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
