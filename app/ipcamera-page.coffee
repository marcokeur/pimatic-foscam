$(document).on("templateinit", (event) ->
    class IpCameraDeviceItem extends pimatic.DeviceItem
        constructor: (templData, @device) ->
          @socket = io.connect("#{document.location.host}/")

          super(templData, @device)

        afterRender: (elements) ->
          super(elements)
          client = new WebSocket( 'ws://' + "#{document.location.hostname}" + ':9500/' );
          canvas = document.getElementById('videoCanvas');
          player = new jsmpeg(client, {canvas:canvas});

        onSaveSnapshotPress: ->
          console.log('snapshot')
          $.get("/api/device/#{@deviceId}/saveSnapshot").fail(ajaxAlertFail)

        onToggleInfraredPress: ->
          console.log('IR')
          $.get("/api/device/#{@deviceId}/toggleInfrared").fail(ajaxAlertFail)

    pimatic.templateClasses['ipcamera'] = IpCameraDeviceItem
)
