class Wish < ApplicationRecord
    has_one :User
    belongs_to :Wlist, optional: true
end
