module WishesHelper
  def wish_option_location(location)
    uri = URI.parse(location.to_s)
    if uri.is_a?(URI::HTTP) && uri.host.present?
      link_to location, location, target: "_blank", rel: "noopener noreferrer", class: "wish-option-link"
    else
      location
    end
  rescue URI::InvalidURIError
    location
  end
end
