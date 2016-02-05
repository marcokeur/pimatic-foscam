# #my-plugin configuration options
# Declare your config option for your plugin here.
module.exports = {
  title: "foscam devices config schema"
  IpCamera: {
    type: "object"
    properties:
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
      wsPort:
        description: "Port of websocket"
        type: "number"
        default: 9500
  }
}