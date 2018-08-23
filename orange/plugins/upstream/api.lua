local BaseAPI = require("orange.plugins.base_api")
local common_api = require("orange.plugins.common_api")
local orange_db = require("orange.store.orange_db")
local dao = require("orange.store.dao")
local utils = require("orange.utils.utils")
local json = require("orange.utils.json")
local upstream_status = ngx.shared.upstream_status
local checker = require("orange.plugins.upstream.checker")

local api = BaseAPI:new("upstream-api", 2)
local common_api_table = common_api("upstream")

-- get useable api from common api 
local useable_api = {
	"/upstream/enable",
	"/upstream/sync"
}
local useable_api_table = {}
for _, path in pairs(useable_api) do
	useable_api_table[path] = common_api_table[path]
end
api:merge_apis(useable_api_table)

api:get("/upstream/fetch_config",function (store)
	return function (req, res, next)
		local data = {}
        local enables ,err = dao.get_enable("upstream" ,store)
        if enables and type(enables) == "table" and #enables > 0 then
            data["upstream.enable"] = (enables[1].value == "1")
        else
            data["upstream.enable"] = false
        end

        local upstreams, err = store:query({
            sql = "select * from upstream where `type` = ?",
            params = {"upstream"}
        })

        if err then
            ngx.log(ngx.ERR, "error to find upstreams from storage when fetching data of plugin[upstream], err:", err)
            return false
        end

        local upstreams_table = {}
        if upstreams and type(upstreams) == "table" and #upstreams > 0 then
	        for _ , upstream in pairs(upstreams) do
	        	upstreams_table[upstream.key] = json.decode(upstream.value)
	        end
	    end
        data["upstream.upstreams"] = upstreams_table

		return res:json({
			success = true,
			data = data,
			msg = "succeed to fetch config from store"
		})
	end
end)

api:get("/upstream/config",function (store)
	return function (req, res, next)
		local data = {}
        local enable = orange_db.get("upstream.enable") or false
        data["enable"] = enable

        local upstreams = orange_db.get_json("upstream.upstreams")
        data["upstreams"] = upstreams

		res:json({
			success = true,
			data = data
			})
	end
end)

api:get("/upstream/checker",function (store)
    return function (req, res, next)
        local function ups_status(ukey,ups)
            local ups_statuses = {}
            for level, peer_srvs in pairs(ups["servers"]) do
                for _, srv in pairs(peer_srvs) do
                    local st = checker.get_mem_srv_status(ukey, srv)
                    local srv_key = string.format("%s.%d", srv.ip, srv.port)
                    local status = false
                    if not st or st.status == checker.STATUS_OK then
                        status = true
                    end
                    ups_statuses[srv_key] = status
                end
            end
            return ups_statuses
        end

        local data = {}
        data["heartbeat_timer_last_run_time"] = upstream_status:get("heartbeat_timer_last_run_time")
        data["heartbeat_timer_alive"] = upstream_status:get("heartbeat_timer_alive")
        data["upstreams"] = {}

        local upstreams = orange_db.get_json("upstream.upstreams")
        local get_ukey = req.query.upstream_name
        if get_ukey and get_ukey ~= "" then
            local upstream = upstreams[get_ukey]
            if upstream then
                data["upstreams"][get_ukey] = ups_status(get_ukey, upstream)
            else
                return res:json({
                    success = false,
                    msg = "fail to find upstream which matchs this upstream_name"
                    })
            end
        else
            for ukey, upstream in pairs(upstreams) do
                ngx.log(ngx.ERR,type(upstream))
                data["upstreams"][ukey] = ups_status(ukey, upstream)
            end
        end

        return res:json({
            success = true,
            data = data
            })

    end
end)    

api:get("/upstream/upstreams",function (store)
	return function (req, res, next)
    	return res:json({
    		success = true,
    		data = orange_db.get_json("upstream.upstreams")
    		})
    	end
end)

api:post("/upstream/upstreams",function (store)
	return function (req, res, next)
		local upstream = req.body.upstream
		upstream = json.decode(upstream)

        if not upstream then
            return res:json({
                    success = false,
                    msg = "upstream is not a standard json"
                })
        end

		upstream.time = utils.now()

		local create_upstream_result = dao.create_record("upstream" ,store, "upstream", upstream)
		if create_upstream_result then
			local update_local_upstreams_result = dao.update_local_records("upstream", store, "upstream", "upstreams")
            if not update_local_upstreams_result then
                return res:json({
                    success = false,
                    msg = "error to local upstreams when creating upstream"
                })
            end
        else
            return res:json({
            	success = false,
                msg = "error to create upstream"            	
            })
		end

        return res:json({
        	success = true,
            msg = "succeed to create upstream"
        })
	end
end)

api:put("/upstream/upstreams",function (store)
	return function (req, res, next)
		local upstream = req.body.upstream
		upstream = json.decode(upstream)

        if not upstream then
            return res:json({
                    success = false,
                    msg = "upstream is not a standard json"
                })
        end
        
		upstream.time = utils.now()

        local update_upstream_result = dao.update_record("upstream" ,store, "upstream", upstream)
        if update_upstream_result then
        	local update_local_upstreams_result = dao.update_local_records("upstream", store, "upstream", "upstreams")
            if not update_local_upstreams_result then
                return res:json({
                    success = false,
                    msg = "error to local upstreams when updating upstream"
                })
            end
        else
            return res:json({
            	success = false,
                msg = "error to update upstream"            	
            })
        end

        return res:json({
        	success = true,
            msg = "succeed to update upstream"
        })
	end
end)

api:delete("/upstream/upstreams",function (store)
	return function (req, res, next)
		local upstream_name = req.body.upstream_name
		if not upstream_name or upstream_name == "" then
            return res:json({
                success = false,
                msg = "upstream_name can not be null"
            })
        end

		local upstream = dao.get_record("upstream" ,store, "upstream" ,upstream_name)
		if not upstream or not upstream.value then
            return res:json({
                success = false,
                msg = "upstream not found when deleting it"
            })
        end

        local delete_upstream_result = dao.delete_record("upstream" ,store ,"upstream" ,upstream_name)
        if delete_upstream_result then
        	local update_local_upstreams_result = dao.update_local_records("upstream", store, "upstream", "upstreams")
            if not update_local_upstreams_result then
        			return res:json({
                    success = false,
                    msg = "error to local upstreams when deleting upstream"
                })
        	end
        else
        	return res:json({
            	success = false,
                msg = "error to delete upstream"            	
            })
        end
    	return res:json({
        	success = true,
            msg = "succeed to delete upstream"
        })
	end
end)

return api
