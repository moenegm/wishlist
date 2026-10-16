class Wish < ApplicationRecord
  belongs_to :user
  belongs_to :wlist, class_name: "Wlist", foreign_key: :wlists_id
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :title, presence: true
  validates :price, :price_2, :price_3, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # Retain the original fields as option one so existing wishes need no backfill.
  def purchase_options
    (1..3).filter_map do |number|
      suffix = number == 1 ? "" : "_#{number}"
      location = public_send("location#{suffix}")
      price = public_send("price#{suffix}")
      { location: location, price: price } if location.present? || price.present?
    end
  end
end
