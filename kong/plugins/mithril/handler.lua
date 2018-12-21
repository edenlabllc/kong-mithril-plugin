local BasePlugin = require "kong.plugins.base_plugin"
local json = require "dkjson"
local http = require "resty.http"
local rstrip = require("pl.stringx").rstrip
local replace = require("pl.stringx").replace
local split = require("pl.stringx").split
local CorrelationIdHandler = require("kong.plugins.correlation-id.handler")
local rex = require("rex_pcre")
local ck = require("resty.cookie")
local rate_limiting = require("kong.plugins.mithril.rate-limiting")

local MithrilHandler = BasePlugin:extend()
local req_headers = {}

MithrilHandler.PRIORITY = 770
MithrilHandler.VERSION = "0.0.1"
CorrelationIdHandler.PRIORITY = 1501

local function send_error(status_code, message)
  ngx.status = status_code
  ngx.header.content_type = "application/json"
  local type = "access_denied"
  if status_code == 403 then
    type = "forbidden"
  end

  local port = ""
  if ngx.var.server_port ~= 80 then
    port = ":" .. ngx.var.server_port
  end
  local error = {
    meta = {
      url = ngx.var.scheme .. "://" .. ngx.var.host .. port .. ngx.var.request_uri,
      type = "object",
      request_id = ngx.ctx.correlationid_header_value,
      code = status_code
    },
    error = {
      type = type,
      message = message
    }
  }
  ngx.say(json.encode(error))
end

local function validate_scopes(required_scopes, available_scopes)
  local missing_scopes = {}
  for k, required_scope in pairs(required_scopes) do
    local has_scope = false
    for key, consumer_scope in pairs(available_scopes) do
      if required_scope == consumer_scope then
        has_scope = true
        break
      end
    end
    if not has_scope then
      table.insert(missing_scopes, required_scope)
    end
  end

  return missing_scopes
end

local function find_rule(rules)
  local api_path = rstrip(ngx.ctx.router_matches.uri, "/")
  local request_path = ngx.var.uri
  local api_relative_path = replace(request_path, api_path, "")
  local method = ngx.req.get_method()

  for k, rule in pairs(rules) do
    path_matched = rex.match(api_relative_path, "^" .. rule.path) ~= nil
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
  local cookie, err = ck:new()

  local authorization
  local field, err = cookie:get("authorization")
  if not field then
    authorization = ngx.req.get_headers()["authorization"]
  else
    authorization = "Bearer " .. field
  end

  local api_key = ngx.req.get_headers()["api-key"]
  if authorization ~= nil then
    local bearer = string.sub(authorization, 8)
    rate_limiting.verify(config, bearer)
    local url = string.gsub(config.url_template, "{access_token}", bearer)

    local httpc = http.new()
    local res, err =
      httpc:request_uri(
      url,
      {
        method = "GET",
        headers = {
          accept = "application/json",
          ["Content-Type"] = "application/json",
          ["api-key"] = api_key
        }
      }
    )

    httpc:close()

    if not res or res.status ~= 200 then
      send_error(401, "Invalid access token")
      return ngx.exit(200)
    end

    local response = json.decode(res.body)
    local data = response.data or {}
    local urgent = response.urgent or {}
    local mis_client_id = urgent.mis_client_id
    local details = data.details or {}
    local broker_scope = details.broker_scope
    local user_id = data.user_id or data.consumer_id
    local scope = data.consumer_scope or details.scope

    if user_id == nil or scope == nil then
      send_error(401, "Invalid access token")
      return ngx.exit(200)
    end

    ngx.req.set_header("x-consumer-id", user_id)
    ngx.req.set_header("x-consumer-scope", scope)
    ngx.var.upstream_x_mis_client_id = mis_client_id
    ngx.var.upstream_x_consumer_id = user_id
    if details.scope ~= nil then
      local x_consumer_metadata = json.encode(details)
      ngx.req.set_header("x-consumer-metadata", x_consumer_metadata)
      ngx.var.upstream_x_client_id = details.client_id
    end

    local rule = find_rule(config.rules)
    if next(config.rules) ~= nil then
      if rule == nil then
        send_error(403, "ACL: No matching rule was found for path " .. ngx.ctx.router_matches.uri)
        return ngx.exit(200)
      end

      if scope == nil or scope == "" then
        send_error(
          403,
          "Your scope does not allow to access this resource. Missing allowances: " .. table.concat(rule.scopes, ", ")
        )
        return ngx.exit(200)
      end

      local missing_scopes = validate_scopes(rule.scopes, split(scope, " "))
      if #missing_scopes > 0 then
        send_error(
          403,
          "Your scope does not allow to access this resource. Missing allowances: " ..
            table.concat(missing_scopes, ", ")
        )
        return ngx.exit(200)
      end

      if broker_scope ~= nil then
        local missing_scopes = validate_scopes(rule.scopes, split(broker_scope, " "))
        if #missing_scopes > 0 then
          send_error(
            403,
            "Your scope does not allow to access this resource. Missing allowances: " ..
              table.concat(missing_scopes, ", ")
          )
          return ngx.exit(200)
        end
      end
    end
  else
    send_error(401, "Authorization header is not set or doesn't contain Bearer token")
    return ngx.exit(200)
  end
end

return MithrilHandler
