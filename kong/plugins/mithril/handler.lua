local BasePlugin = require "kong.plugins.base_plugin"
local json = require "dkjson"
local http = require "resty.http"
local rstrip = require("pl.stringx").rstrip
local replace = require("pl.stringx").replace
local split = require("pl.stringx").split

local MithrilHandler = BasePlugin:extend()
local req_headers = {}

MithrilHandler.PRIORITY = 1500
MithrilHandler.VERSION = "0.0.1"

local function find_rule(rules)
    local api_path = rstrip(ngx.ctx.router_matches.uri, "/")
    local request_path = ngx.var.uri
    local api_relative_path = replace(request_path, api_path, "")
    local method = ngx.req.get_method()

    for k, rule in pairs(rules) do
        path_matched = string.match(api_relative_path, "^"..rule.path) ~= nil
        method_matched = false
        for key, rule_method in pairs(rule.methods) do
            if rule_method == method then
                method_matched = true
                break
            end
        end
        if path_matched and method_matched then
            return rule
        end
    end
end

function MithrilHandler:new()
    MithrilHandler.super.new(self, "mithril")
end

function MithrilHandler:access(config)
    MithrilHandler.super.access(self)

    local authorization_header = ngx.req.get_headers()["authorization"]
    local api_key =  ngx.req.get_headers()["api-key"]

    if authorization_header ~= nil then
        local bearer = string.sub(authorization_header, 8)
        local url = string.gsub(config.url_template, "{access_token}", bearer)

        local httpc = http.new()
        local res, err = httpc:request_uri(url, {
            method = "GET",
            headers = {
                accept = "application/json",
                ["Content-Type"] = "application/json",
                ["api-key"] = api_key
            }
        })

        if not res then
            ngx.say("failed to request: ", err)
            return
        end

        if res.status ~= 200 then
            ngx.status = res.status
            ngx.say(res.body)
            return ngx.exit(200)
        end

        local response = json.decode(res.body)
        local data = response.data or {}
        local details = data.details or {}
        local broker_scope = details.broker_scope
        local user_id = data.user_id or data.consumer_id
        local scope = data.consumer_scope or details.scope

        if user_id == nil or scope == nil then
            ngx.status = 401
            ngx.say("Invalid access token")
            return ngx.exit(200)
        end

        ngx.req.set_header("x-consumer-id", user_id)
        ngx.req.set_header("x-consumer-scope", scope)
        if details.scope ~= nil then
            ngx.req.set_header("x-consumer-metadata", json.encode(details))
        end

        local rule = find_rule(config.rules)
        if rule == nil then
            ngx.status = 403
            ngx.say("No matching rule was found for path")
            return ngx.exit(200)
        end

        if scope == nil or scope == "" then
            ngx.status = 403
            ngx.say("Your scope does not allow to access this resource. Missing allowances: "..table.concat(rule.scopes, ", "))
            return ngx.exit(200)
        end

        local consumer_scopes = split(scope, " ")
        local missing_scopes = {}

        for k, required_scope in pairs(rule.scopes) do
            local has_scope = false
            for key, consumer_scope in pairs(consumer_scopes) do
                ngx.say({required_scope, consumer_scope})
                if required_scope == consumer_scope then
                    has_scope = true
                    break
                end

            end
            if not has_scope then
                table.insert(missing_scopes, required_scope)
            end
        end

        if #missing_scopes > 0 then
            ngx.status = 403
            ngx.say("Your scope does not allow to access this resource. Missing allowances: "..table.concat(missing_scopes, ", "))
        end

        return ngx.exit(200)

        -- 1. Implement scope validation logic
        -- 2. Check error messages
    else
        ngx.status = 401
        ngx.header.content_type = "application/json"
        ngx.say("Authorization header is not set or doesn't contain Bearer token")
        return ngx.exit(200)
    end
end


return MithrilHandler
