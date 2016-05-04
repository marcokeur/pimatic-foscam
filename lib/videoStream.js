(function() {
  var Mpeg1Muxer, STREAM_MAGIC_BYTES, VideoStream, events, util, ws;

  ws = require('ws');

  util = require('util');

  events = require('events');

  Mpeg1Muxer = require(__dirname + '/mpeg1muxer.js');

  STREAM_MAGIC_BYTES = "jsmp";

  VideoStream = function(options) {
    this.name = options.name;
    this.streamUrl = options.streamUrl;
    this.width = options.width;
    this.height = options.height;
    this.wsPort = options.wsPort;

    this.stream = void 0;
    this.initMpeg1Muxer();
    this.initWebsocketServer();
    return this;
  };

  util.inherits(VideoStream, events.EventEmitter);

  VideoStream.prototype.initMpeg1Muxer = function() {
    var gettingInputData, gettingOutputData, inputData, outputData, self;
    this.mpeg1Muxer = new Mpeg1Muxer({
      url: this.streamUrl
    });
    self = this;

    this.mpeg1Muxer.on('mpeg1data', function(data) {
      return self.emit('camdata', data);
    });
    gettingInputData = false;
    inputData = [];
    gettingOutputData = false;
    outputData = [];
    this.mpeg1Muxer.on('ffmpegError', function(data) {
      var size;
      data = data.toString();
      if (data.indexOf('Input #') !== -1) {
        gettingInputData = true;
      }
      if (data.indexOf('Output #') !== -1) {
        gettingInputData = false;
        gettingOutputData = true;
      }
      if (data.indexOf('frame') === 0) {
        gettingOutputData = false;
      }
      if (gettingInputData) {
        inputData.push(data.toString());
        size = data.match(/\d+x\d+/);
        if (size != null) {
          size = size[0].split('x');
          if (self.width == null) {
            self.width = parseInt(size[0], 10);
          }
          if (self.height == null) {
            return self.height = parseInt(size[1], 10);
          }
        }
      }
    });
    //this.mpeg1Muxer.on('ffmpegError', function(data) {
    //  return global.process.stderr.write(data);
    //});
    return this;
  };

  VideoStream.prototype.initWebsocketServer = function() {
    var self;
    self = this;
    this.wsServer = new ws.Server({
      port: this.wsPort
    });
    this.wsServer.on("connection", function(socket) {
      return self.onSocketConnect(socket);
    });
    this.wsServer.broadcast = function(data, opts) {
      var i, _results;
      _results = [];
      for (i in this.clients) {
        if (this.clients[i].readyState === 1) {
          _results.push(this.clients[i].send(data, opts));
        } else {
          _results.push(console.log("Error: Client (" + i + ") not connected."));
        }
      }
      return _results;
    };
    return this.on('camdata', function(data) {
      return self.wsServer.broadcast(data);
    });
  };

  function sendHeader(socket, width, height) {
    streamHeader = new Buffer(8);
    streamHeader.write(STREAM_MAGIC_BYTES);
    streamHeader.writeUInt16BE(width, 4);
    streamHeader.writeUInt16BE(height, 6);
    socket.send(streamHeader, {
      binary: true
    });
  }

  VideoStream.prototype.onSocketConnect = function(socket) {
    var self, streamHeader;
    self = this;

    self.mpeg1Muxer.startStream();

    if(self.width == undefined){
      setTimeout(function(){
        sendHeader(socket, self.width, self.height);
      }, 2500);
    }else{
      sendHeader(socket, self.width, self.height);
    }

    console.log(("" + this.name + ": New WebSocket Connection (") + this.wsServer.clients.length + " total)");

    socket.on("close", function(code, message) {
      console.log(("" + self.name + ": Disconnected WebSocket (") + self.wsServer.clients.length + " total)");

      if(self.wsServer.clients.length < 1){
        self.mpeg1Muxer.stopStream();
        console.log("Tearing down the mpeg1Muxer.");
      }
    });
  };

  module.exports = VideoStream;

}).call(this);
