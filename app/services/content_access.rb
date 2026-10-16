class ContentAccess
  def self.visible?(record, user)
    list = record.is_a?(Wish) ? record.wlist : record
    list.is_a?(Wlist) && (list.is_public? || list.user_id == user&.id)
  end

  def self.ensure!(record, user)
    raise ActiveRecord::RecordNotFound unless visible?(record, user)
    record
  end
end
