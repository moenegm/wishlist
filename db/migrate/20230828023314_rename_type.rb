class RenameType < ActiveRecord::Migration[7.0]
  def change
    rename_column :wlists, :type, :wl_category
  end
end
