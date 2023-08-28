class CreateWlists < ActiveRecord::Migration[7.0]
  def change
    create_table :wlists do |t|
      t.string :title
      t.references :user, null: false, foreign_key: true
      t.string :type

      t.timestamps
    end
  end
end
