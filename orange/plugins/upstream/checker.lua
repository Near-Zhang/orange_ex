local orange_db = require("orange.store.orange_db")
local json = require("orange.utils.json")
local try = require("orange.plugins.upstream.try")

local upstream_status = ngx.shared.upstream_status
local localtime = ngx.now

local _M = {
	STATUS_OK = 0,
	STATUS_ERR = 1,					-- 后续添加检查方法时，可以添加一个 UNSTABLE 状态
	checkups_status = {},			-- store the upstream's pasitive check status of all upstreams / per request
	checkups_list = {}				-- store the upstream's balance algorithm list of all upstreams / per worker
}

local function update_mem_srv_status(srv_status, fail_time, success_time)
	local srvkey = srv_status.srvkey
	local status = srv_status.status

	local old_status_str, err = upstream_status:get(srvkey)
	if err then
        ngx.log(ngx.ERR, "[Upstream] failed to get old status:", srvkey, ", ", err)
        return
    end

    local old_status
    if old_status_str then
        old_status, err = json.decode(old_status_str)
        if err then
            ngx.log(ngx.ERR, "[Upstream] failed decode old srv status string ,", err)
        end
    end

    if not old_status then
        old_status = {
            status = _M.STATUS_OK,
            fail_num = 0,
            sueccss_num = 0,
            lastmodified = localtime(),
        }
    end

    if status == _M.STATUS_OK then
        old_status.fail_num = 0
        if old_status.status ~= _M.STATUS_OK then
            old_status.sueccss_num = old_status.sueccss_num + 1
            if old_status.sueccss_num >= success_time then
                old_status.status = _M.STATUS_OK
                old_status.lastmodified = localtime()
            end
        end
    else
        old_status.sueccss_num = 0
        if old_status.status == _M.STATUS_OK then
            old_status.fail_num = old_status.fail_num + 1
            if old_status.fail_num >= fail_time then
                old_status.status = _M.STATUS_ERR
                old_status.lastmodified = localtime()
            end
        end
    end

    local ok, err = upstream_status:set(srvkey, json.encode(old_status))
    if not ok then
        ngx.log(ngx.ERR, "[Upstream] failed to set new srv status ", err)
    end
end

local function update_mem_ups_status(ups_status, fail_time, success_time)
    if not ups_status then
        return
    end

    for _, srv_status in ipairs(ups_status) do
        update_mem_srv_status(srv_status, fail_time, success_time)
    end
end

local function srv_heartbeat(ip, port, timeout)
    local sock = ngx.socket.tcp()
    sock:settimeout(timeout * 1000)
    local ok, err = sock:connect(ip, port)
    if not ok then
        ngx.log(ngx.WARN, "[Upstream] heartbeat failed to connect server, ip:"..ip..", port:"..port..", err:"..err)
        return _M.STATUS_ERR, err
    end

    sock:setkeepalive()
    return _M.STATUS_OK
end

local function ups_heartbeat(ukey, upstream)
	local srv_count = 0
	for level, peer_srvs in ipairs(upstream.servers) do
        if peer_srvs and #peer_srvs > 0 then
            srv_count = srv_count + #peer_srvs
        end
    end

    local error_count = 0
    local ups_available = false
    local ups_status = {}

    local timeout = upstream.checker_timeout or 3
    local fail_time = upstream.checker_fail_time or 3
    local success_time = upstream.checker_success_time or 3

    for level, peer_srvs in ipairs(upstream.servers) do
        for _, srv in ipairs(peer_srvs) do
            local srvkey = string.format("%s.%s.%d", ukey, srv.ip, srv.port)
            local status, err = srv_heartbeat(srv.ip, srv.port, timeout)

            local srv_status = {
                srvkey = srvkey,
                status = status,
            }

            if status == _M.STATUS_OK then
                update_mem_srv_status(srv_status, fail_time, success_time)
                srv_status.updated = true
                ups_available = true
            end

            if status == _M.STATUS_ERR then
				error_count = error_count + 1
                if ups_available then
                    update_mem_srv_status(srv_status, fail_time, success_time)
                    srv_status.updated = true
                end
            end

            if srv_status.updated ~= true then
                table.insert(ups_status, srv_status)
            end
        end
    end

    if next(ups_status) then
        if error_count == srv_count then
            ups_status[1].status = _M.STATUS_OK
            ngx.log(ngx.ERR,"[Upstream] no servers alive, start to protect mode, upstream_name:", ukey, " backup srv:", ups_status[1].srvkey)
        end
        update_mem_ups_status(ups_status, fail_time, success_time)
    end
end

function _M.ups_heartbeat_checker(premature)
    ngx.update_time()

    if premature then
        ngx.log(ngx.ERR,"[Upstream] heartbeat timer is premature and going to dead")
        local ok, err = upstream_status:set("heartbeat_timer_alive", 2)
        if not ok then
            ngx.log(ngx.ERR, "[Upstream] heartbeat dead and failed to update upstream_status: ", err)
        end
        return
    end

    local checkup_timer_interval = 5
    local checkup_timer_overtime = 60

    local config_load
    repeat
        config_load = orange_db.get("upstream.updated.0")
        if config_load == nil then
            ngx.sleep(0.1)
            ngx.log(ngx.WARN,"[Upstream] waiting loading config")
        else
            break
        end
    until false

    local enable = orange_db.get("upstream.enable")
    local upstreams = orange_db.get_json("upstream.upstreams")
    if not enable or enable ~= true or not upstreams then
        ngx.log(ngx.ERR,"[Upstream] upstream plugin is not enable and timer is stopping check")
        local ok, err = upstream_status:set("heartbeat_timer_alive", 1)
        if not ok then
            ngx.log(ngx.ERR, "[Upstream] heartbeat stop and failed to update upstream_status: ", err)
        end
    else
        for ukey, upstream in pairs(upstreams) do
            ups_heartbeat(ukey, upstream)
        end
        upstream_status:set("heartbeat_timer_last_run_time", localtime())
        upstream_status:set("heartbeat_timer_alive", 0, checkup_timer_overtime)
    end

    local ok, err = ngx.timer.at(checkup_timer_interval, _M.ups_heartbeat_checker)
    if not ok then
        ngx.log(ngx.ERR, "[Upstream] heartbeat stop because of failed to create heartbeat_timer: ", err)
        ok, err = upstream_status:set("heartbeat_timer_alive", 2)
        if not ok then
            ngx.log(ngx.WARN, "[Upstream] failed to update upstream_status: ", err)
        end
        return
    end    
end

-- feedback status to var checkups_status
function _M.feedback_status(ukey, ip, port, failed)
	local upstreams = orange_db.get_json("upstream.upstreams")
	local upstream = upstreams[ukey]

    if not upstream then
        return
    end

    local srv
    for level, peer_srvs in ipairs(upstream.servers) do
        for _, s in ipairs(peer_srvs) do
            if s.ip == ip and s.port == port then
                srv = s
                break
            end
        end
    end

    if not srv then
        return
    end

    _M.set_var_srv_status(ukey, upstream, srv, failed)
end

-- the api of set status to checkups_status
function _M.set_var_srv_status(ukey, upstream, srv, failed)
    local ups_status = _M.checkups_status[ukey]
    if not ups_status then
        ups_status = {}
        _M.checkups_status[ukey] = ups_status
    end

    local max_fails = srv.max_fails or 1
    local fail_timeout = srv.fail_timeout or 10
    if max_fails == 0 then  --  if max_fails equal to 0 ,disables the accounting of attempts
        return
    end

    local time_now = localtime()
    local srv_key = string.format("%s.%d", srv.ip, srv.port)
    local srv_status = ups_status[srv_key]
    if not srv_status then
        srv_status = {
            status = _M.STATUS_OK,
            failed_count = 0,
            lastmodify = time_now
        }
        ups_status[srv_key] = srv_status
    elseif srv_status.lastmodify + fail_timeout < time_now then -- srv_status expired
        srv_status.status = _M.STATUS_OK
        srv_status.failed_count = 0
        srv_status.lastmodify = time_now
    end

    if failed then
        srv_status.failed_count = srv_status.failed_count + 1

        if srv_status.failed_count >= max_fails then
            for level, peer_srvs in ipairs(upstream.servers) do
                for _, s in ipairs(peer_srvs) do
                    local key = string.format("%s.%d", s.ip, s.port)
                    local st = ups_status[key]
                    -- confirm this server not the last ok server
                    if not st or st.status == _M.STATUS_OK and key ~= srv_key then
                        srv_status.status = _M.STATUS_ERR
                        return
                    end
                end
            end
        end
    end
end

-- update checkups_list and call try module
function _M.select_peer(ukey)
	local worker_id = ngx.worker.id()
	local config_updated = orange_db.get("upstream.updated."..tostring(worker_id))

	if not config_updated or not next(_M.checkups_list) then
        local upstreams = orange_db.get_json("upstream.upstreams")
	    for uk, upstream in pairs(upstreams) do
	        _M.checkups_list[uk] = upstream
        end
	    orange_db.set("upstream.updated."..tostring(worker_id), true)
    end

	local ups = _M.checkups_list[ukey]
	if not ups then
        return
    end

    local request_srv_func
    if ups.strict_check and ups.strict_check == true then
	    request_srv_func = function(ip, port)
            return { ip=ip, port=port, status=STATUS_OK}
        end
	else
        request_srv_func = function(ip, port)
           return { ip=ip, port=port }
        end
	end

    return try.try_ups(ukey, _M, request_srv_func)
end

-- the api of get status from shared dict and checkups_status
function _M.get_mem_srv_status(ukey, srv)
	local srv_key = string.format("%s.%s.%d", ukey, srv.ip, srv.port)
    local peer_status = upstream_status:get(srv_key)
    if peer_status then
        return json.decode(peer_status)
    else
        return nil
    end
end

function _M.get_var_srv_status(ukey, srv)
    local ups_status = _M.checkups_status[ukey]
    if not ups_status then
        return _M.STATUS_OK
    end

    local srv_key = string.format("%s.%d", srv.ip, srv.port)
    local srv_status = ups_status[srv_key]
    local fail_timeout = srv.fail_timeout or 10

    if srv_status and srv_status.lastmodify + fail_timeout > ngx.now() then
        return srv_status.status
    end

    return _M.STATUS_OK
end

return _M