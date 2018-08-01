local BasePlugin = require("orange.plugins.base_handler")

local UpstreamHandler = BasePlugin:extend()
UpstreamHandler.PRIORITY = 4000

function UpstreamHandler:new()
    UpstreamHandler.super.new(self, "Upstream-plugin")
    self.store = store
end

return UpstreamHandler