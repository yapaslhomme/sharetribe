class ReprocessListingImages < ActiveRecord::Migration
  say "This migration will reprocess all the images from #{Listing.count} listings"

  def up
    Listing.all.each do |listing|
      listing.listing_images.each do |listing_image|
        listing_image.image.reprocess_without_delay!
        print "."
        STDOUT.flush
      end
    end
    puts ""
  end
end


