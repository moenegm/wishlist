class SocialActions
  def self.follow(actor, person)
    actor.with_lock do
      follow = actor.follows_as_follower.find_or_initialize_by(followed_user: person)
      fresh = follow.new_record?
      follow.save!
      Notification.create!(recipient: person, actor: actor, event_type: "followed", notifiable: follow) if fresh && actor != person
      follow
    end
  end

  def self.like(actor, target)
    ContentAccess.ensure!(target, actor)
    actor.with_lock do
      like = actor.likes.find_or_initialize_by(likeable: target)
      fresh = like.new_record?
      like.save!
      Notification.create!(recipient: target.user, actor: actor, event_type: target.is_a?(Wish) ? "liked_wish" : "liked_wlist", notifiable: target) if fresh && actor != target.user
      like
    end
  end

  def self.comment(actor, target, body)
    ContentAccess.ensure!(target, actor)
    Comment.transaction do
      comment = actor.comments.create!(commentable: target, body: body)
      Notification.create!(recipient: target.user, actor: actor, event_type: target.is_a?(Wish) ? "commented_wish" : "commented_wlist", notifiable: comment) if actor != target.user
      comment
    end
  end

  def self.notify_public_wish(wish)
    return unless wish.wlist.is_public?
    wish.wlist.user.followers.where.not(id: wish.user_id).find_each do |follower|
      Notification.create!(recipient: follower, actor: wish.user, event_type: "added_wish", notifiable: wish)
    end
  end
end
