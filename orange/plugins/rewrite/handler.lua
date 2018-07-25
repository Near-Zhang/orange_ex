local pairs = pairs
local ipairs = ipairs
local ngx_re_sub = ngx.re.sub
local ngx_re_find = ngx.re.find
local string_sub = string.sub
local orange_db = require("orange.store.orange_db")
local judge_util = require("orange.utils.judge")
local extractor_util = require("orange.utils.extractor")
local handle_util = require("orange.utils.handle")
local BasePlugin = require("orange.plugins.base_handler")
local ngx_set_uri = ngx.req.set_uri
local ngx_set_uri_args = ngx.req.set_uri_args
local ngx_decode_args = ngx.decode_args


local function filter_rules(sid, plugin, ngx_var_uri)
    local rules = orange_db.get_json(plugin .. ".selector." .. sid .. ".rules")
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end

    for i, rule in ipairs(rules) do
        if rule.handle and rule.handle.log == true then
            ngx.log(ngx.INFO, "[Rewrite][Start To Pass Through Rule:", rule.id, "]")
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
                    ngx.log(ngx.INFO, "[Rewrite][Match-Rule:", rule.id, "]")
                end

                if handle and handle.uri_tmpl then
                    local rewrite_uri = handle_util.build_uri(rule.extractor.type, handle.uri_tmpl, variables)

                    if rewrite_uri and rewrite_uri ~= ngx_var_uri then

                        ngx.var.rewrite_uri = rewrite_uri
                        if handle.log == true then
                            ngx.log(ngx.INFO, "[Rewrite][To-Rewrite] to:", rewrite_uri)
                        end

                        local from, to, err = ngx_re_find(rewrite_uri, "[%?]{1}", "jo")
                        if not err and from and from >= 1 then
                            local qs = string_sub(rewrite_uri, from+1)
                            rewrite_uri = string_sub(rewrite_uri, 1, from-1)
                            if qs then
                                local args = ngx_decode_args(qs, 0)
                                if args then 
                                    ngx_set_uri_args(args) 
                                end
                            end
                        end

                        local jump = false
                        if handle.jump and type(handle.jump) == "boolean" then
                            jump = handle.jump
                        end
   

                        ngx_set_uri(rewrite_uri, jump)
                                                                                   
                    else
                        if handle.log == true then
                            ngx.log(ngx.ERR, "[Rewrite][Match-Rule-Error] the rewrite_uri is nil or equal to var.ngx.uri")
                        end    
                    end
                else
                    if handle.log == true then
                        ngx.log(ngx.ERR, "[Rewrite][Match-Rule-Error] no handler or uri_tmpl ")
                    end
                end

                return true
            else
                if rule.handle and rule.handle.log == true then
                    ngx.log(ngx.INFO, "[Rewrite][NotMatch-Rule:", rule.id, "]")
                end
            end
        end
    end

    return false
end

local RewriteHandler = BasePlugin:extend()
RewriteHandler.PRIORITY = 2000

function RewriteHandler:new(store)
    RewriteHandler.super.new(self, "Rewrite-plugin")
    self.store = store
end

function RewriteHandler:rewrite(conf)
    RewriteHandler.super.rewrite(self)

    local enable = orange_db.get("rewrite.enable")
    local meta = orange_db.get_json("rewrite.meta")
    local selectors = orange_db.get_json("rewrite.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end

    local ngx_var_uri = ngx.var.uri

    for i, sid in ipairs(ordered_selectors) do
        local selector = selectors[sid]
        if selector.handle and selector.handle.log == true then
            ngx.log(ngx.INFO, "[Rewrite][Start To Pass Through Selector:", sid, "]")
        end

        if selector and selector.enable == true then
            local selector_pass 
            if selector.type == 0 then -- 全流量selector
                selector_pass = true
            else
                selector_pass = judge_util.judge_selector(selector, "rewrite")-- selector judge
            end

            if selector_pass then
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Rewrite][Pass-Selector:", sid, "]")
                end

                local stop = filter_rules(sid, "rewrite", ngx_var_uri)
                if stop then -- 已匹配该selector中的rule，不再进行执行通过后续的selector
                    return
                end
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Rewrite][NotMatch-Any-Rule-In-Selector:", sid, "]")
                end
            else
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Rewrite][Not-Pass-Selector:", sid, "]")
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

return RewriteHandler
