class ListingImageJSAdapter
  include ApplicationController::DefaultURLOptions
  
  # Due to the way Rails includes the url helpers, this has to be AFTER DefaultURLOptions.
  include Rails.application.routes.url_helpers

  def initialize(listing_image)
    @id = listing_image.id
    @listing_id = listing_image.listing_id
    @processing = listing_image.image_processing
    @downloaded = listing_image.image_downloaded
    @images = {
      thumb: listing_image.image.url(:thumb)
    }
    @urls = {
      remove: listing_image_path(listing_image.id),
      status: image_status_listing_image_path(listing_image)
    }
  end
end