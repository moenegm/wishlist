class CreateWishes < ActiveRecord::Migration[7.0]
  def change
    create_table :wishes do |t|
      t.string :title
      t.string :location
      t.decimal :price

      t.timestamps
    end
  end
end
