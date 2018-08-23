-- #################### balance algorithm ####################
-- ##### wrr #####
local function next_round_robin_server(peer_srvs, peer_srv_alive_cb)

    local srvs_count = #peer_srvs

    if srvs_count == 1 then
        if peer_srv_alive_cb(peer_srvs[1]) then
            return peer_srvs[1], nil
        end

        return nil, "round robin: no peer_srvs available"
    end

    -- select round robin server
    local best
    local max_weight
    local weight_sum = 0
    for idx = 1, srvs_count do
        local srv = peer_srvs[idx]
        -- init round robin state
        srv.weight = srv.weight or 1
        srv.effective_weight = srv.effective_weight or srv.weight
        srv.current_weight = srv.current_weight or 0

        if peer_srv_alive_cb(srv) then
            srv.current_weight = srv.current_weight + srv.effective_weight
            weight_sum = weight_sum + srv.effective_weight

            if srv.effective_weight < srv.weight then
                srv.effective_weight = srv.effective_weight + 1
            end

            if not max_weight or srv.current_weight > max_weight then
                max_weight = srv.current_weight
                best = srv
            end
        end
    end

    if not best then
        return nil, "round robin: no peer_srvs available"
    end
    best.current_weight = best.current_weight - weight_sum
    return best, nil

end

local function free_round_robin_server(srv, failed)
    if not failed then
        return
    end
    srv.effective_weight = math.ceil((srv.effective_weight or 1) / 2)
end

-- ##### consistent hash #####
local MOD       = 2 ^ 32
local REPLICAS  = 20

local function hash_string(str)
    local key = 0
    for i = 1, #str do
        key = (key * 31 + string.byte(str, i)) % MOD
    end
    return key
end

local function init_consistent_hash_state(peer_srvs)
    local weight_sum = 0
    for _, srv in ipairs(peer_srvs) do
        weight_sum = weight_sum + (srv.weight or 1)
    end

    local circle, members = {}, 0
    for index, srv in ipairs(peer_srvs) do
        local key = ("%s.%d"):format(srv.ip, srv.port)
        local base_hash = hash_string(key)
        local replicas = REPLICAS * weight_sum
        for c = 1, replicas do
            -- more replicas balance hash
            local hash = (base_hash + c * MOD / replicas ) % MOD
            table.insert(circle, { hash, index })
        end
        members = members + 1
    end

    table.sort(circle, function(a, b) return a[1] < b[1] end)

    return { circle = circle, members = members }
end

local function binary_search(circle, key)
    local size = #circle
    local st, ed, mid = 1, size
    while st <= ed do
        mid = math.floor((st + ed) / 2)
        if circle[mid][1] < key then
            st = mid + 1
        else
            ed = mid - 1
        end
    end

    return st == size + 1 and 1 or st
end

local function next_consistent_hash_server(peer_srvs, peer_srv_alive_cb, hash_key)
    peer_srvs.chash = type(peer_srvs.chash) == "table" and peer_srvs.chash
                    or init_consistent_hash_state(peer_srvs)

    local chash = peer_srvs.chash
    if chash.members == 1 then
        if peer_srv_alive_cb(1, peer_srvs[1]) then
            return peer_srvs[1]
        end

        return nil, "consistent hash: no peer_srvs available"
    end

    local circle = chash.circle
    local st = binary_search(circle, hash_string(hash_key))
    local size = #circle
    local ed = st + size - 1
    for i = st, ed do  --  algorithm O(n)
        local idx = circle[(i - 1) % size + 1][2]
        if peer_srv_alive_cb(peer_srvs[idx]) then
            return peer_srvs[idx]
        end
    end

    return nil, "consistent hash: no peer_srvs available"

end

-- #################### end ####################

local _M = {}

local NEED_RETRY       = 0
local REQUEST_SUCCESS  = 1
local EXCESS_TRY_LIMIT = 2
local function prepare_callbacks(ukey, checker)

    -- calculate count of level and server
    local ups = checker.checkups_list[ukey]

    local levels_count = #ups.servers
    local srvs_count = 0
    for level, peer_srvs in pairs(ups.servers) do
        srvs_count = srvs_count + #peer_srvs
    end

    -- get next level peer_srvs
    local level = 0
    local next_level_srvs_cb = function()
        level = level + 1
        if level > levels_count then
            return
        end

        return ups.servers[level]
    end

    -- get next select server
    local mode = ups.type or 1
    local next_server_func
    local key

    if mode ~= 1 then
        if mode == 2 then
            key = ngx.var.remote_addr
        elseif mode == 3 then
            key = ngx.var.uri
        elseif mode == 4 then
            key = ngx.var.http_x_hash_key or ngx.var.uri
        end
        next_server_func = next_consistent_hash_server
    else
        next_server_func = next_round_robin_server
    end

    local next_server_cb = function(peer_srvs, peer_srv_alive_cb)
        return next_server_func(peer_srvs, peer_srv_alive_cb, key)
    end

    -- check whether ther server is available
    local bad_srvs = {}
    local peer_srv_alive_cb = function(srv)
        local srv_key = ("%s.%s.%d"):format(ukey, srv.ip, srv.port)
        if bad_srvs[srv_key] then
            return false
        end

        local peer_mem_status = checker.get_mem_srv_status(ukey, srv)
        local peer_var_status = checker.get_var_srv_status(ukey, srv)
        if (not peer_mem_status or peer_mem_status.status ~= checker.STATUS_ERR)
        and peer_var_status == checker.STATUS_OK then
            return true
        end
    end

    -- check whether need retry
    local try_count = 0
    local try_limit = srvs_count
    local retry_cb = function(res)
        if type(res) == "table" and res.status then
            if res.status == checker.STATUS_OK then
                return REQUEST_SUCCESS
            end
        elseif res then
            return REQUEST_SUCCESS
        end

        try_count = try_count + 1
        if try_count >= try_limit then
            return EXCESS_TRY_LIMIT
        end

        return NEED_RETRY
    end

    -- check whether try_time has over amount_request_time
    local try_time = 0
    local try_time_limit = ups.try_timeout or 0
    local try_time_cb = function(this_time_try_time)
        try_time = try_time + this_time_try_time
        if try_time_limit == 0 then
            return NEED_RETRY
        elseif try_time >= try_time_limit then
            return EXCESS_TRY_LIMIT
        end

        return NEED_RETRY
    end

    -- set some status
    local free_server_func
    if ups.type == 1 then
        free_server_func = free_round_robin_server
    else
        free_server_func= function(srv, failed)
        return
        end
    end

    local set_status_cb = function(srv, failed)
        local srv_key = ("%s.%s.%d"):format(ukey, srv.ip, srv.port)
        bad_srvs[srv_key] = failed
        checker.set_var_srv_status(ukey, ups, srv, failed)
        free_server_func(srv, failed)
    end

    return {
        next_level_srvs_cb = next_level_srvs_cb,
        next_server_cb = next_server_cb,
        peer_srv_alive_cb = peer_srv_alive_cb,
        retry_cb = retry_cb,
        try_time_cb = try_time_cb,
        set_status_cb = set_status_cb,
    }
end

function _M.try_ups(ukey, checker, request_srv_func)
	local callbacks = prepare_callbacks(ukey, checker)

	local next_level_srvs_cb = callbacks.next_level_srvs_cb
    local next_server_cb = callbacks.next_server_cb
    local peer_srv_alive_cb = callbacks.peer_srv_alive_cb
    local retry_cb = callbacks.retry_cb
    local try_time_cb = callbacks.try_time_cb
    local set_status_cb = callbacks.set_status_cb

    local ups = checker.checkups_list[ukey]
    local timeout = ups.checker_timeout or 3

    -- iter servers function
    local itersrvs = function(servers, peer_srv_alive_cb)
        return function() return next_server_cb(servers, peer_srv_alive_cb) end
    end

    local res, err = nil, "no servers available"
    repeat
        -- get next level/key cluster
        local peer_srvs = next_level_srvs_cb()

        if not peer_srvs then
            break
        end

        for srv, err in itersrvs(peer_srvs, peer_srv_alive_cb) do
            -- exec request callback by server
            local start_time = ngx.now()
            res, err = request_srv_func(srv.ip, srv.port, timeout)

            -- check whether need retry
            local end_time = ngx.now()
            local delta_time = end_time - start_time

            local feedback = retry_cb(res)
            set_status_cb(srv, feedback ~= REQUEST_SUCCESS) -- set some status
            if feedback ~= NEED_RETRY then
                return res, err
            end

            local feedback_try_time = try_time_cb(delta_time)
            if feedback_try_time ~= NEED_RETRY then
                return res, err
            end
       end
    until false

    return res, err

end

return _M
