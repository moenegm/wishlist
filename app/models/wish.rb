class Wish < ApplicationRecord
    has_one :User
    belongs_to :Wlist, optional: true

    has_and_belongs_to_many :friendships, 
    class_name: "User", 
    join_table:  :friendships, 
    foreign_key: :user_id, 
    association_foreign_key: :friend_user_id

    

end
