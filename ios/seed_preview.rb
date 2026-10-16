# Run with bin/rails runner ios/seed_preview.rb against a local development database.
abort "Preview data is only allowed in development." unless Rails.env.development?
host = ActiveRecord::Base.connection_db_config.configuration_hash[:host]
abort "Preview data requires a local database." unless host.blank? || %w[localhost 127.0.0.1 ::1].include?(host) || host.start_with?("/")

owner = User.find_or_initialize_by(email: "ios-qa@example.test")
if owner.new_record?
  owner.assign_attributes(first_name: "Native", last_name: "QA", password: "LocalPreview123!")
  owner.save!
end
owner.wlists.find_or_create_by!(title: "Native QA")
friend = User.find_or_initialize_by(email: "ios-friend@example.test")
if friend.new_record?
  friend.assign_attributes(first_name: "Tomas", last_name: "Preview", password: "LocalPreview123!")
  friend.save!
end
list = friend.wlists.find_or_create_by!(title: "A cozy corner") { |record| record.is_public = true; record.wl_category = "Home" }
friend.wishes.find_or_create_by!(title: "Reading chair", wlist: list) { |wish| wish.location = "https://example.com/chair"; wish.price = 120 }
SocialActions.follow(owner, friend) unless owner.following?(friend)
SocialActions.follow(friend, owner) unless friend.following?(owner)
puts "Local preview account: ios-qa@example.test / LocalPreview123!"
