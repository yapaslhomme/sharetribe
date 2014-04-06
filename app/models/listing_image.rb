class ListingImage < ActiveRecord::Base

  belongs_to :listing
  belongs_to :author, :class_name => "Person"

  has_attached_file :image, :styles => {
        :small_3x2 => "240x160#",
        :medium => "360x270#",
        :thumb => "120x120#",
        :original => "#{APP_CONFIG.original_image_width}x#{APP_CONFIG.original_image_height}>",
        :big => "800x800>",
        :big_cropped => Proc.new { |instance| instance.crop_big },
        :email => "150x100#"}

  before_save :set_dimensions!

  process_in_background :image, :processing_image_url => "/assets/listing_image/processing.png"
  validates_attachment_size :image, :less_than => APP_CONFIG.max_image_filesize.to_i, :unless => Proc.new {|model| model.image.nil? }

  validates_attachment_content_type :image,
                                    :content_type => ["image/jpeg", "image/png", "image/gif", "image/pjpeg", "image/x-png"], # the two last types are sent by IE.
                                    :unless => Proc.new {|model| model.image.nil? }


  def set_dimensions!
    # Silently return, if there's no `width` and `height`
    # Prevents old migrations from crashing
    return unless self.respond_to?(:width) && self.respond_to?(:height)

    geometry = extract_dimensions

    if geometry
      self.width = geometry.width.to_i
      self.height = geometry.height.to_i
    end
  end

  def crop_big
    geometry = extract_dimensions
    max_landscape_crop_percentage = 0.2
    ListingImage.construct_big_style({:width => geometry.width.round, :height => geometry.height.round}, max_landscape_crop_percentage)
  end

  # Retrieves dimensions for image assets
  # @note Do this after resize operations to account for auto-orientation.
  # https://github.com/thoughtbot/paperclip/wiki/Extracting-image-dimensions
  def extract_dimensions
    return unless image_downloaded?
    tempfile = image.queued_for_write[:original]

    # Works with uploaded files and existing files
    path_or_url = if !tempfile.nil? then
      # Uploading new file
      tempfile.path
    else
      if image.options[:storage] === :s3
        image.url
      else
        image.path
      end
    end

    geometry = Paperclip::Geometry.from_file(path_or_url)
  end

  def authorized?(user)
    author == user || (listing && listing.author == user)
  end

  def correct_size?(aspect_ratio)
    ListingImage.correct_size? self.width, self.height, aspect_ratio
  end

  def too_narrow?(aspect_ratio)
    ListingImage.too_narrow? self.width, self.height, aspect_ratio
  end

  def too_wide?(aspect_ratio)
    ListingImage.too_wide? self.width, self.height, aspect_ratio
  end

  def self.correct_size?(width, height, aspect_ratio)
    width.to_f / height.to_f == aspect_ratio.to_f
  end

  def self.too_narrow?(width, height, aspect_ratio)
    width.to_f / height.to_f < aspect_ratio.to_f
  end

  def self.too_wide?(width, height, aspect_ratio)
    width.to_f / height.to_f > aspect_ratio.to_f
  end

  def download_from_url(url)
    self.image = URI.parse(url)
    self.update_attribute(:image_downloaded, true)
  end

  def image_ready?
    image_downloaded && !image_processing
  end

  def self.portrait?(dimensions)
    dimensions[:height] > dimensions[:width]
  end

  def self.scale_height_down(dimensions, desired_height)
    if dimensions[:height] > desired_height
      scale_factor = dimensions[:height] / desired_height.to_f
      {
        :width => (dimensions[:width] / scale_factor).round,
        :height => (dimensions[:height] / scale_factor).round
      }
    else
      dimensions
    end
  end

  # Assumes:
  # - Landscape image
  # - Height is scaled already
  def self.crop_landscape_sides(dimensions, desired_width, max_crop_percentage)
    crop_need = dimensions[:width] - desired_width
    crop_need_percentage = crop_need.to_f / dimensions[:width]

    if(crop_need_percentage <= max_crop_percentage)
      {:width => desired_width, :height => dimensions[:height]}
    else
      cropped_width = ((1 - max_crop_percentage) * dimensions[:width]).round
      {:width => cropped_width, :height => dimensions[:height]}
    end
  end

  def self.construct_big_style(dimensions, max_landscape_crop_percentage)
    default = "660x440>"

    if self.portrait? dimensions
      default
    else
      scaled = self.scale_height_down(dimensions, 440)
      cropped = self.crop_landscape_sides(scaled, 660, 0.2)

      "#{cropped[:width]}x#{cropped[:height]}#"
    end
  end
end
