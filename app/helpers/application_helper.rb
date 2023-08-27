module ApplicationHelper
    def name(user_id)
        user = User.find(user_id)
        full_name = user.first_name + " " + user.last_name
        return full_name 
    end
end
