supported_flash_version = '9'

if !window.swfobject
  throw "JpegCamera: SWFObject is not loaded"

if !window.JpegCamera &&
   window.swfobject &&
   swfobject.hasFlashPlayerVersion(supported_flash_version)

  # JpegCamera implementation that uses Flash to capture, display and upload
  # snapshots.
  #
  # @private
  class JpegCameraFlash extends JpegCamera
    # Used by flash object to send message to our instance.
    @_send_message: (id, method) ->
      instance = @_instances[parseInt(id)]

      return unless instance

      args = Array.prototype.slice.call arguments, 2

      @prototype[method].apply instance, args
    @_instances: {}
    @_next_id: 1

    _engine_init: ->
      @_debug "Using Flash engine"

      # register our instance
      @_id = @constructor._next_id++
      @constructor._instances[@_id] = @

      if @view_width < 215 || @view_height < 138
        @_got_error "camera is too small to display privacy dialog"
        return

      flash_object_id = "flash_object_" + @_id

      params =
        loop: "false"
        allowScriptAccess: "always"
        allowFullScreen: "false"
        quality: "best"
        wmode: "opaque"
        menu: "false"
      attributes =
        id: flash_object_id
        align: "middle"
      flashvars =
        id: @_id
        width: @view_width
        height: @view_height
        shutter_url: @options.shutter_url
      that = this
      callback = (event) ->
        if !event.success
          that._got_error "Flash loading failed."
        else
          that._debug "Flash loaded"
          that._flash = document.getElementById flash_object_id

      container_to_be_replaced = document.createElement "div"
      container_to_be_replaced.id = "jpeg_camera_flash_" + @_id
      container_to_be_replaced.style.width = "100%"
      container_to_be_replaced.style.height = "100%"

      @container.appendChild container_to_be_replaced

      swfobject.embedSWF @options.swf_url, container_to_be_replaced.id,
        @view_width, @view_height, '9', null, flashvars, params, attributes,
        callback

    _engine_play_shutter_sound: ->
      @_flash._play_shutter()

    _engine_capture: (snapshot, mirror, quality, scale) ->
      @_flash._capture snapshot.id, mirror, quality, scale

    _engine_display: (snapshot) ->
      @_flash._display snapshot.id

    _engine_get_canvas: (snapshot) ->
      snapshot._image_data ||= @_engine_get_image_data snapshot
      canvas = document.createElement("canvas")
      canvas.width = snapshot._image_data.width
      canvas.height = snapshot._image_data.height
      context = canvas.getContext "2d"
      context.putImageData snapshot._image_data, 0, 0
      canvas

    _engine_get_image_data: (snapshot) ->
      flash_data = @_flash._get_image_data snapshot.id

      if JpegCamera.canvas_supported()
        canvas = document.createElement("canvas")
        canvas.width = flash_data.width
        canvas.height = flash_data.height
        context = canvas.getContext "2d"
        result = context.createImageData flash_data.width, flash_data.height
      else
        result =
          data: []
          width: flash_data.width
          height: flash_data.height

      for pixel, i in flash_data.data
        index = i * 4

        red = pixel >> 16 & 0xff
        green = pixel >> 8 & 0xff
        blue = pixel & 0xff

        result.data[index + 0] = red
        result.data[index + 1] = green
        result.data[index + 2] = blue
        result.data[index + 3] = 255
      result

    _engine_discard: (snapshot) ->
      @_flash._discard snapshot.id

    _engine_show_stream: ->
      @_flash._show_stream()

    _engine_upload: (snapshot, api_url, csrf_token, timeout) ->
      @_flash._upload snapshot.id, api_url, csrf_token, timeout

    _flash_prepared: ->
      @_block_element_access()
      @_prepared()

    # Called on both - upload success and error
    _flash_upload_complete: (snapshot_id, status_code, error, response) ->
      snapshot_id = parseInt(snapshot_id)
      snapshot = @_snapshots[snapshot_id]

      snapshot._status = parseInt(status_code)
      snapshot._response = response

      if snapshot._status >= 200 && snapshot._status < 300
        snapshot._upload_done()
      else
        snapshot._error_message = error
        snapshot._upload_fail()

  window.JpegCamera = JpegCameraFlash
