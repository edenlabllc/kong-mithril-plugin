local BasePlugin = require "kong.plugins.base_plugin"
local json = require "dkjson"
local http = require "resty.http"

local MithrilHandler = BasePlugin:extend()
local req_headers = {}

MithrilHandler.PRIORITY = 1500
MithrilHandler.VERSION = "0.0.1"

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

        -- 1. Add rules config
        -- 2. Add custom validation of rules config (should be a valid json)
        -- 3. Implement scope validation logic
    else
        ngx.status = 401
        ngx.header.content_type = "application/json"
        ngx.say("Authorization header is not set or doesn't contain Bearer token")
        return ngx.exit(200)
    end
end


return MithrilHandler
