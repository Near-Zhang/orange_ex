local BasePlugin = require("orange.plugins.base_handler")
local checker = require("orange.plugins.upstream.checker")
local balancer  = require("ngx.balancer")
local orange_db = require("orange.store.orange_db")

local UpstreamHandler = BasePlugin:extend()
UpstreamHandler.PRIORITY = 4000

function UpstreamHandler:new(store)
    UpstreamHandler.super.new(self, "Upstream-plugin")
    self.store = store
end

function UpstreamHandler:init_worker()
    UpstreamHandler.super.init_worker(self)

    if ngx.worker.id() ~= 0 then
        return
    end

    local ok, err = ngx.timer.at(0, checker.ups_heartbeat_checker)
    if not ok then
        ngx.log(ngx.ERR, "[Upstream][Failed-To-Create-Ups-Heartbeat-checker] ", err)
        return
    end
end

function UpstreamHandler:balance()
    UpstreamHandler.super.balance(self)

    local ukey = ngx.var.upstream_name
    local enable = orange_db.get("upstream.enable")
    local upstreams = orange_db.get_json("upstream.upstreams")
    local upstream = upstreams[ukey]

    if not ukey or not enable or enable ~= true or not upstreams or not upstream then
        return
    end

    local status, code = balancer.get_last_failure()
    if status == "failed" then
        local last_peer = ngx.ctx.last_peer
        checker.feedback_status(ukey, last_peer.ip, last_peer.port, true)
    end

    local ok, err, peer
    local connect_timeout = upstream.ctimeout
    local send_timeout = upstream.stimeout 
    local read_timeout = upstream.rtimeout 

    ok, err = balancer.set_timeouts(connect_timeout, send_timeout, read_timeout)
    if not ok then
        ngx.log(ngx.ERR, "[Upstream] set proxy timeout failed, ", err, " ukey:", ukey)
    end

    ok, err = balancer.set_more_tries(1)
    if not ok then
        ngx.log(ngx.ERR, "[Upstream] set more tries failed, ", err, " ukey:", ukey)
    end

    peer, err = checker.select_peer(ukey)
    if not peer then
        ngx.log(ngx.ERR, "[Upstream] select current peer server failed, ", err, " ukey:", ukey)
        return
    end

    ngx.ctx.last_peer = peer

    ok, err = balancer.set_current_peer(peer.ip, peer.port)
    if not ok then
        ngx.log(ngx.ERR, "[Upstream] set current peer server failed, ", err, " ukey:", ukey)
        return
    end

    if upstream.log then
        ngx.log(ngx.INFO, "[Upstream][Proxy-Server] ip:", peer.ip, ", port:", peer.port)
    end

end

return UpstreamHandler