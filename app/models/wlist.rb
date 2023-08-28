class Wlist < ApplicationRecord
  belongs_to :user
  has_many :wishes
end
