class AddWishToWishlist < ActiveRecord::Migration[7.0]
  def change
    add_reference :wlists, :wishes, null: false
    add_reference :wishes, :wlists, null: false
    add_reference :wishes, :user, null: false

  end
end
