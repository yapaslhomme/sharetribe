window.ST = window.ST || {};

window.ST.imageUploader = function(listings, containerSelector, uploadSelector, thumbnailSelector, createFromFilePath, s3options, s3createFromFilePath) {
  var $container = $(containerSelector);

  function renderUploader() {
    var uploadTmpl = _.template($(uploadSelector).html());

    $container.html(uploadTmpl);

    function processing() {
      $(".fileupload-text", $container).text(ST.t("listings.form.images.processing"));
      $(".fileupload-small-text", $container).text(ST.t("listings.form.images.this_may_take_a_while"));
    }

    function updatePreview(result, delay) {
      $.get(result.processedPollingUrl, function(images_result) {
        if(images_result.processing) {
          processing();
          _.delay(function() {
            updatePreview(result, delay + 500);
          }, delay + 500);
        } else {
          renderThumbnail({thumbnailUrl: images_result.thumb, removeUrl: result.removeUrl});
        }
      });
    }

    function megabytes(mb) {
      return mb * 1024 * 1024;
    }

    $(function() {
      $('#fileupload').fileupload({
        dataType: 'json',
        url: s3createFromFilePath,
        dropZone: $('#fileupload'),
        formData: s3options,
        //             // The maximum width of resized images:
        imageMaxWidth: 1920,
            // The maximum height of resized images:
        imageMaxHeight: 1080,
        loadImageMaxFileSize: megabytes(50),
        disableImageResize: false,
        progress: function(e, data) {
          if(data.total === data.loaded) {
            processing();
          } else {
            var percentage = Math.round((data.loaded / data.total) * 100);
            $(".fileupload-text", $container).text(ST.t("listings.form.images.percentage_loaded", {percentage: percentage}));
            $(".fileupload-small-text", $container).empty();
          }
        },
        done: function (e, data) {
          debugger;
          var url = [s3createFromFilePath, data.formData.key.replace("${filename}", data.files[0].name)].join("");
          $.ajax({
            type: "POST",
            url: createFromFilePath,
            data: {
              listing_image: {
                image_url: url
              }
            },
            success: function(result) {
              updatePreview(result, 2000);
              $("#listing-image-id").val(result.id);
            },
          });

          // var result = data.result;
          // $('#listing-image-upload-status').text(result.filename);

          // updatePreview(result, 2000);
        },
        fail: function() {
          $(".fileupload-text", $container).text(ST.t("listings.form.images.uploading_failed"));
          $(".fileupload-small-text", $container).empty();
        }
      }).on('dragenter', function() {
        $(this).addClass('hover');
      }).on('dragleave', function() {
        $(this).removeClass('hover');
      });
    });
  }

  function renderThumbnail(listing) {
    var $thumbnail = $(_.template($(thumbnailSelector).html(), {thumbnailUrl: listing.thumbnailUrl}));

    $('.fileupload-preview-remove-image', $thumbnail).click(function(e) {
      e.preventDefault();

      $(".fileupload-removing").show();

      $.ajax({
        url: listing.removeUrl,
        type: 'DELETE',
        success: function() {
          $container.empty();
          $(".fileupload-removing").hide();
          renderUploader();
        },
      });
    });

    $container.html($thumbnail);
  }

  if(listings.length === 0) {
    renderUploader();
  } else {
    listings.forEach(renderThumbnail);
  }
};