local BasePlugin = require("orange.plugins.base_handler")
local orange_db = require("orange.store.orange_db")
local judge_util = require("orange.utils.judge")
local extractor_util = require("orange.utils.extractor")
local handle_util = require("orange.utils.handle")
local utils = require("orange.utils.utils")

local function filter_rules( sid, plugin, ngx_var )
	local rules = orange_db.get_json(plugin .. ".selector." .. sid .. ".rules")
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end

    for _, rule in ipairs(rules) do
        if rule.handle and rule.handle.log == true then
            ngx.log(ngx.INFO, "[Mirror][Start To Pass Through Rule:", rule.id, "]")
        end

    if rule.enable == true then
            -- judge阶段
            local pass = judge_util.judge_rule(rule, plugin)

            -- extract阶段
            local variables = extractor_util.extract_variables(rule.extractor)

            -- handle阶段
            if pass then
                local handle = rule.handle
                if handle and handle.log == true then
                    ngx.log(ngx.INFO, "[Mirror][Match-Rule:", rule.id, "]")
                end

                if not ngx_var.junhai_trace_id or ngx_var.junhai_trace_id == "" or ngx_var.junhai_trace_id == "-" then
                    ngx_var.junhai_trace_id = utils.new_id()     -- set new trace id
                end

            	local extractor_type = rule.extractor.type
            	local method = ngx_var.request_method
            	local mirror_host_tmp = ngx_var.host
                local mirror_url_tmp = "http://backend"
                local mirror_name_tmp = "default_upstream"
            	local methods = {
            		GET = ngx.HTTP_GET,
            		POST = ngx.HTTP_POST,
            		PUT = ngx.HTTP_PUT,
            		DELETE = ngx.HTTP_DELETE
            	}

                if handle and (handle.mirror_url or handle.mirror_name) then

                	if handle.mirror_host and handle.mirror_host ~= "" then -- mirror_host默认取请求的host
                        mirror_host_tmp = handle_util.build_upstream_host(extractor_type, handle.mirror_host, variables, plugin)
                    end

                    if handle.mirror_url and handle.mirror_url ~= "" then -- mirror_url默认取 http://backend
                        mirror_url_tmp = handle_util.build_upstream_url(extractor_type, handle.mirror_url, variables, plugin)
                    end

                    if handle.mirror_name and handle.mirror_name ~= "" then -- mirror_name默认取 default_upstream
                        mirror_name_tmp = handle.mirror_name
                    end     

                	ngx.req.read_body()
                	local options = {
                	    method = methods[method],
                	    ctx = {
                			sub_origin_uri = ngx_var.uri,
     	          			sub_upstream_host = mirror_host_tmp,
                			sub_upstream_url = mirror_url_tmp,
                            sub_upstream_name = mirror_name_tmp,
                            sub_junhai_trace_id = ngx_var.junhai_trace_id
                		},
                		always_forward_body = true
                	}

                	local subquest_uri = "/mirror-plugin-of-api-gateway"
                	if ngx_var.args then
                		subquest_uri = subquest_uri.."?"..ngx_var.args
                	end

                    local multiple = handle.multiple or 1
                    local multi_t = {}

                    for var = 1, multiple do
                        table.insert(multi_t, {subquest_uri,options})
                    end

                	local ok,err = pcall(ngx.location.capture_multi, multi_t)
                	if ok then
                        ngx_var.mirror_url = mirror_url_tmp
                        ngx_var.mirror_host = mirror_host_tmp
                        ngx_var.mirror_name = mirror_name_tmp
                		if handle.log == true then
                			ngx.log(ngx.INFO, "[Mirror][Mirror-To] mirrot_host:"..mirror_host_tmp..", mirror_url:"..mirror_url_tmp..", mirror_name:"..mirror_name_tmp)
                		end
                	else
                		if handle.log == true then
                			ngx.log(ngx.ERR, "[Mirror][Match-Rule-Error] failed to issues subquest:"..tostring(ok)..","..err)
                		end
                	end

                else
                	if handle.log == true then
                        ngx.log(ngx.ERR, "[Mirror][Match-Rule-Error] no handle or mirror_url")
                    end
                end

                return true
            else
                if rule.handle and rule.handle.log == true then
                    ngx.log(ngx.INFO, "[Mirror][NotMatch-Rule:", rule.id, "]")
                end
            end
        end
    end

    return false
end


local MirrorHandler = BasePlugin:extend()
MirrorHandler.PRIORITY = 2000

function MirrorHandler:new(store)
    MirrorHandler.super.new(self, "Mirror-plugin")
    self.store = store
end

function MirrorHandler:mirror()
    MirrorHandler.super.mirror(self)

    local enable = orange_db.get("mirror.enable")
    local meta = orange_db.get_json("mirror.meta")
    local selectors = orange_db.get_json("mirror.selectors")
    local ordered_selectors = meta and meta.selectors

    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end

    local ngx_var = ngx.var

    for i, sid in ipairs(ordered_selectors) do
        local selector = selectors[sid]
        if selector.handle and selector.handle.log == true then
            ngx.log(ngx.INFO, "[Mirror][Start To Pass Through Selector:", sid, "]")
        end

        if selector and selector.enable == true then
            local selector_pass 
            if selector.type == 0 then -- 全流量selector
                selector_pass = true
            else
                selector_pass = judge_util.judge_selector(selector, "mirror") -- selector judge
            end

            if selector_pass then
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Mirror][Pass-Selector:", sid, "]")
                end

                local stop = filter_rules(sid, "mirror", ngx_var)
                if stop then -- 已匹配该selector中的rule，不再进行执行通过后续的selector
                    return
                end
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Mirror][NotMatch-Any-Rule-In-Selector:", sid, "]")
                end
            else
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Mirror][Not-Pass-Selector:", sid, "]")
                end
            end

            -- 没有通过该selector或不匹配该selector中的所有rule，判断是否继续匹配下面的selector
            if selector.handle and selector.handle.continue == true then
                -- continue next selector
            else
                break
            end
        end
    end

end

return MirrorHandler
