class AddFulfilledToWishes < ActiveRecord::Migration[8.1]
  def change
    add_column :wishes, :fulfilled, :boolean, default: false, null: false
  end
end
