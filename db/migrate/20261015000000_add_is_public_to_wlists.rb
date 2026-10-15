class AddIsPublicToWlists < ActiveRecord::Migration[8.1]
  def change
    add_column :wlists, :is_public, :boolean, default: false, null: false
  end
end
