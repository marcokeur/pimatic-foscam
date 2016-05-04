var child_process = require('child_process');
var util = require('util');
var events = require('events');

util.inherits(Mpeg1Muxer, events.EventEmitter);

function Mpeg1Muxer(options) {
    this.url = options.url;
    this.running = false;
}

Mpeg1Muxer.prototype.startStream = function(){
    var self = this;

    if(!self.running){
      self.running = true;

      self.stream = child_process.spawn("ffmpeg", ["-rtsp_transport", "tcp", "-i", self.url, '-f', 'mpeg1video', '-b:v', '800k', '-r', '30', '-'], {
        detached: false
      });
      self.stream.stdout.on('data', function(data) {
        return self.emit('mpeg1data', data);
      });
      self.stream.stderr.on('data', function(data) {
        return self.emit('ffmpegError', data);
      });
    }
};

Mpeg1Muxer.prototype.stopStream = function() {
    var self = this;

    self.stream.kill();
    self.running = false;
}


module.exports = Mpeg1Muxer;
