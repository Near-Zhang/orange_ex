local ipairs = ipairs
local type = type

local utils = require("orange.utils.utils")
local stringy = require("orange.utils.stringy")
local orange_db = require("orange.store.orange_db")
local judge_util = require("orange.utils.judge")
local extractor_util = require("orange.utils.extractor")
local handle_util = require("orange.utils.handle")
local BasePlugin = require("orange.plugins.base_handler")


local function ensure_end(uri)
    if not stringy.endswith(uri, "/") then
        uri = uri.."/"
    end
    return uri
end

local function filter_rules(sid, plugin, ngx_var, ngx_var_uri, ngx_var_host)
    local rules = orange_db.get_json(plugin .. ".selector." .. sid .. ".rules")
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end

    for _, rule in ipairs(rules) do
        ngx.log(ngx.INFO, "==[Divide][START TO PASS THROUGH RULE:", rule.id, "]")
        if rule.enable == true then
            -- judge阶段
            local pass = judge_util.judge_rule(rule, plugin)

            -- extract阶段
            local variables = extractor_util.extract_variables(rule.extractor)

            -- handle阶段
            if pass then
                if rule.log == true then
                    ngx.log(ngx.INFO, "[Divide-Match-Rule] ", rule.id, " host:", ngx_var_host, " uri:", ngx_var_uri)
                end

                local extractor_type = rule.extractor.type
                if rule.handler and rule.handler.upstream_url then
                    if not rule.handler.upstream_host or rule.handler.upstream_host=="" then -- host默认取请求的host
                        ngx_var.upstream_host = ngx_var_host
                    else 
                        ngx_var.upstream_host = handle_util.build_upstream_host(extractor_type, rule.handler.upstream_host, variables, plugin)
                    end

                    ngx_var.upstream_url = handle_util.build_upstream_url(extractor_type, rule.handler.upstream_url, variables, plugin)

                    ngx.log(ngx.INFO, "[Divide-Match-Rule:upstream] ", rule.id, " extractor_type:", extractor_type,
                        " upstream_host:", ngx_var.upstream_host, " upstream_url:", ngx_var.upstream_url)
                else
                    ngx.log(ngx.INFO, "[Divide-Match-Rule:error] no handler or upstream_url. ", rule.id, " host:", ngx_var_host, " uri:", ngx_var_uri)
                end

                return true
            else
                if rule.log == true then
                    ngx.log(ngx.INFO, "[Divide-NotMatch-Rule] ", rule.id, " host:", ngx_var_host, " uri:", ngx_var_uri)
                end
            end
        end
    end

    return false
end


local DivideHandler = BasePlugin:extend()
DivideHandler.PRIORITY = 2000

function DivideHandler:new(store)
    DivideHandler.super.new(self, "Divide-plugin")
    self.store = store
end

function DivideHandler:access(conf)
    DivideHandler.super.access(self)
    
    local enable = orange_db.get("divide.enable")
    local meta = orange_db.get_json("divide.meta")
    local selectors = orange_db.get_json("divide.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end

    local ngx_var = ngx.var
    local ngx_var_uri = ngx_var.uri
    local ngx_var_host = ngx_var.host

    for i, sid in ipairs(ordered_selectors) do
        ngx.log(ngx.INFO, "==[Divide][START TO PASS THROUGH SELECTOR:", sid, "]")

        local selector = selectors[sid]
        if selector and selector.enable == true then
            local selector_pass 
            if selector.type == 0 then -- 全流量selector
                selector_pass = true
            else
                selector_pass = judge_util.judge_selector(selector, "divide") -- selector judge
            end

            if selector_pass then
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Divide][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
                end

                local stop = filter_rules(sid, "divide", ngx_var, ngx_var_uri, ngx_var_host)
                if stop then -- 已匹配该selector中的rule，不再进行执行通过后续的selector
                    return
                end
            else
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Divide][NOT-PASS-SELECTOR:", sid, "] ", ngx_var_uri)
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

return DivideHandler
