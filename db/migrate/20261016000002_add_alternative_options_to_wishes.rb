class AddAlternativeOptionsToWishes < ActiveRecord::Migration[8.1]
  def change
    add_column :wishes, :location_2, :string
    add_column :wishes, :price_2, :decimal
    add_column :wishes, :location_3, :string
    add_column :wishes, :price_3, :decimal
  end
end
