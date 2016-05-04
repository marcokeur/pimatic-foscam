module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  request = env.require 'request'
  fs = env.require 'fs'
  path = env.require 'path'
  #Stream = env.require 'node-rtsp-stream'
  Stream = require(__dirname + '/lib/videoStream.js');

  {parseString} = env.require 'xml2js'
  M = env.matcher
  _ = env.require('lodash')

  class Foscam extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      deviceConfigDef = require("./device-config-schema")

      @framework.ruleManager.addActionProvider(new FoscamActionProvider(@framework))

      @framework.deviceManager.registerDeviceClass("IpCamera", {
        configDef: deviceConfigDef.IpCamera,
        createCallback: (config) =>
          camera = new IpCamera(@framework, config)
          return camera
      })

      @framework.on "after init", =>
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-foscam/app/jsmpg.js"
          mobileFrontend.registerAssetFile 'js', "pimatic-foscam/app/ipcamera-page.coffee"
          mobileFrontend.registerAssetFile 'html', "pimatic-foscam/app/ipcamera-template.html"
        else
          env.logger.warn "pimatic-foscam could not find the mobile-frontend. No gui will be available"

  class IpCamera extends env.devices.Device

    attributes:
      username:
        description: "User name for the access"
        type: "string"
        default: ""
      password:
        description: "password for the access"
        type: "string"
        default: ""
      cameraIp:
        description: "IP of Camera"
        type: "string"
        default: ""
      cameraPort:
        description: "Port of Camera"
        type: "number"
        default : 88

    actions:
      saveSnapshot:
        description: "Command to save the current image"
      toggleInfrared:
        description: "Command to toggle the IR mode"

    template: "ipcamera"

    self: null

    constructor: (framework, @config) ->
      @id         = @config.id
      @name       = @config.name
      @username   = @config.username
      @password   = @config.password
      @cameraIp   = @config.cameraIp
      @cameraPort = @config.cameraPort 
      @wsPort     = @config.wsPort
      @io         = framework.io
      
      self = @

      @url = "http://" + @cameraIp + ":" + @cameraPort + 
            "/cgi-bin/CGIProxy.fcgi?cmd=snapPicture2&usr=" + 
            @username + "&pwd=" + @password

      @rtspUrl = 'rtsp://' + @username + ':' + @password + '@' + 
            @cameraIp + '/videoSub'

      @createImgDirectory

      @getCGIResponse('getDevState', 
        (obj) -> 
          console.dir obj
          if obj != null
            if obj.infraLedState == '1'
              @irEnabled = true
            else
              @irEnabled = false
        )

      stream = new Stream({
        name: @name,
        streamUrl: @rtspUrl,
        width: 320,
        height: 180,
        wsPort: @wsPort
        })

      env.logger.info('Started WS stream at port ' + @wsPort + ' from origin ' + @rtspUrl)

      super()

    getCGIResponse: (command, cb) ->
      cgiUrl = 'http://' + @cameraIp + ':' + @cameraPort + 
          '/cgi-bin/CGIProxy.fcgi?cmd=' + command + 
          '&usr=' + @username + '&pwd=' + @password
      
      request cgiUrl, (err, res, body) ->
        console.log "err " + err
        if err?.length
          parseString body, (err, parsedObj) ->
            cb? parsedObj.CGI_Result
        else
            cb? null

    getImgPath: ->
      imgPath = ""
      if process.platform in ['win32', 'win64']
        imgPath = path.dirname(fs.realpathSync(__filename+"\\..\\"))+"\\pimatic-mobile-frontend\\public\\foscam\\"
      else
        imgPath = path.dirname(fs.realpathSync(__filename+"/../"))+"/pimatic-mobile-frontend/public/foscam/"
      return imgPath

    createImgDirectory: ->
      @imgPath = @getImgPath()

      fs.exists(@imgPath,(exists)=>
        if !exists 
          fs.mkdir(@imgPath,(stat)=>
            @plugin.info "Create directory for the first time"
          )
      )

    getDateTime: ->
      date = new Date();

      hour = date.getHours();
      hour = (hour < 10 ? "0" : "") + hour;

      min  = date.getMinutes();
      min = (min < 10 ? "0" : "") + min;

      sec  = date.getSeconds();
      sec = (sec < 10 ? "0" : "") + sec;

      year = date.getFullYear();

      month = date.getMonth() + 1;
      month = (month < 10 ? "0" : "") + month;

      day  = date.getDate();
      day = (day < 10 ? "0" : "") + day;

      return year + month + day + "_" + hour + min + sec;

    saveSnapshot: =>
      filename = @getDateTime() + '_snapshot.jpg'

      req = request(@url).pipe(fs.createWriteStream(@getImgPath() + filename))
      setTimeout =>
        fs.createReadStream(@getImgPath() + filename).pipe(fs.createWriteStream(@getImgPath() + 'last_snapshot.jpg'))
      , 500  

      env.logger.info('Snapshot from ' + @url + 'stored at ' + @getImgPath() + filename)
      @io.emit("snapshotSaved", filename)
      return

    toggleInfrared: =>
      if @irEnabled
        @getCGIResponse 'closeInfraLed'
        @irEnabled = false
        env.logger.info('Infrared off')
      else  
        @getCGIResponse 'openInfraLed'
        @irEnabled = true
        env.logger.info('Infrared on')

      setTimeout =>
        @getCGIResponse 'setInfraLedConfig&mode=0'
      , 60000
      return

    getUsername   : -> Promise.resolve(@username)
    getPassword   : -> Promise.resolve(@password)
    getCameraIp   : -> Promise.resolve(@cameraIp)
    getCameraPort : -> Promise.resolve(@cameraPort)

  class FoscamActionProvider extends env.actions.ActionProvider

    constructor: (@framework, @config) ->

    parseAction: (input, context) =>

      device = null
      match = null

      cameras = _(@framework.deviceManager.devices).values().filter(
        (device) => device.hasAction("saveSnapshot")
      ).value()

      if cameras.length is 0
        env.logger.info "no cameras with saveSnapshot action found"
        return

      m = M(input, context)
        .match("take a", optional: yes)
        .match("snapshot of ")
        .matchDevice(cameras, (next, d) =>
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          device = d
        )

      if m.hadMatch()
        console.log('MATCH!!!!')
        match = m.getFullMatch()

        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new FoscamActionHandler(@framework, @config, device)
        }
      else
        return null

  class FoscamActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @config, @device) ->
      assert @device?

    executeAction: (simulate) =>
      if simulate
        return Promise.resolve(__("would log 42"))
      else
        @device.saveSnapshot()
        return Promise.resolve(__("logged 42"))

  foscam = new Foscam
  return foscam
