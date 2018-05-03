local Errors = require "kong.dao.errors"

local function rule_check(value)
  local rule_fields = {
    path = "string",
    scopes = "table",
    methods = "table"
  }

  local valid_methods = {
    GET = true,
    POST = true,
    PUT = true,
    PATCH = true,
    DELETE = true,
    OPTIONS = true
  }

  for k, v in pairs(value) do
    if type(v) ~= "table" then
      return false, "'rules." .. (k - 1) .. "' is not a table"
    end

    for key, val in pairs(v) do
      if rule_fields[key] == nil then
        return false, "'rules." .. (k - 1) .. "." .. key .. "' is not allowed field"
      end
    end

    for key, key_type in pairs(rule_fields) do
      if v[key] == nil then
        return false, "'rules." .. (k - 1) .. "." .. key .. "' is required"
      end
      if type(v[key]) ~= key_type then
        return false, "'rules." .. (k - 1) .. "." .. key .. "' is invalid type. " .. key_type .. " expected"
      end
    end

    for key, val in pairs(v["scopes"]) do
      if type(val) ~= "string" then
        return false, "'rules." .. (k - 1) .. ".scopes." .. (key - 1) .. "' is not a string"
      end
    end

    for key, val in pairs(v["methods"]) do
      if type(val) ~= "string" then
        return false, "'rules." .. (k - 1) .. ".methods" .. (key - 1) .. "' is not a string"
      end

      if not valid_methods[val] then
        return false, "'rules." .. (k - 1) .. ".methods" .. (key - 1) .. "' is invalid method"
      end
    end
  end

  return true
end

return {
  no_consumer = true, -- this plugin will only be API-wide,
  fields = {
    url_template = {type = "string", required = true},
    rules = {type = "array", default = {}, func = rule_check},
    second = {type = "number"},
    minute = {type = "number"},
    hour = {type = "number"},
    day = {type = "number"},
    month = {type = "number"},
    year = {type = "number"},
    fault_tolerant = {type = "boolean", default = true},
    redis_host = {type = "string"},
    redis_port = {type = "number", default = 6379},
    redis_password = {type = "string"},
    redis_timeout = {type = "number", default = 2000},
    redis_database = {type = "number", default = 0},
    hide_client_headers = {type = "boolean", default = false}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    local ordered_periods = {"second", "minute", "hour", "day", "month", "year"}
    local has_value
    local invalid_order
    local invalid_value

    for i, v in ipairs(ordered_periods) do
      if plugin_t[v] then
        has_value = true
        if plugin_t[v] <= 0 then
          invalid_value = "Value for " .. v .. " must be greater than zero"
        else
          for t = i + 1, #ordered_periods do
            if plugin_t[ordered_periods[t]] and plugin_t[ordered_periods[t]] < plugin_t[v] then
              invalid_order = "The limit for " .. ordered_periods[t] .. " cannot be lower than the limit for " .. v
            end
          end
        end
      end
    end

    if invalid_value then
      return false, Errors.schema(invalid_value)
    elseif invalid_order then
      return false, Errors.schema(invalid_order)
    end

    if has_value then
      if not plugin_t.redis_host then
        return false, Errors.schema "You need to specify a Redis host"
      end
      if not plugin_t.redis_port then
        return false, Errors.schema "You need to specify a Redis port"
      end
      if not plugin_t.redis_timeout then
        return false, Errors.schema "You need to specify a Redis timeout"
      end
    end

    return true
  end
}
