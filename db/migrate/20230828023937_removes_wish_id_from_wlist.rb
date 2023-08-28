class RemovesWishIdFromWlist < ActiveRecord::Migration[7.0]
  def change
    remove_column :wlists, :wishes_id
  end
end
