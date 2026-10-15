class AddSocialInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :likes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :likeable, polymorphic: true, null: false, index: false
      t.timestamps
    end
    add_index :likes, [:user_id, :likeable_type, :likeable_id], unique: true

    create_table :comments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.text :body, null: false
      t.timestamps
    end

    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.references :notifiable, polymorphic: true
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [:recipient_id, :read_at, :created_at]
  end
end
