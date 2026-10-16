class MobileSession < ApplicationRecord
  belongs_to :user

  def self.issue!(user)
    token = SecureRandom.urlsafe_base64(48)
    session = create!(user: user, token_digest: Digest::SHA256.hexdigest(token), password_digest: Digest::SHA256.hexdigest(user.encrypted_password), expires_at: 30.days.from_now)
    [session, token]
  end

  def self.authenticate(token)
    return if token.blank? || token.bytesize > 256
    session = includes(:user).find_by(token_digest: Digest::SHA256.hexdigest(token))
    return unless session && session.expires_at.future?
    return unless ActiveSupport::SecurityUtils.secure_compare(session.password_digest, Digest::SHA256.hexdigest(session.user.encrypted_password))
    session
  end
end
