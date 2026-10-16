json.extract! wish, :id, :title, :location, :price, :fulfilled, :created_at, :updated_at
json.url wish_url(wish, format: :json)
json.purchase_options wish.purchase_options do |option|
  json.location option[:location]
  json.price option[:price]
end
