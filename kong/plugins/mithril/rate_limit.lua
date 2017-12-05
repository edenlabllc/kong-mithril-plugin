local policies = require "kong.plugins.rate-limiting.policies"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local Object = require "kong.vendor.classic"
local RateLimit = Object:extend()

function RateLimit:get_identifier(conf, token)
    local identifier

    -- Consumer is identified by ip address or authenticated_credential id
    if conf.limit_by == "consumer" then
      identifier = ngx.ctx.authenticated_consumer and ngx.ctx.authenticated_consumer.id
      if not identifier and ngx.ctx.authenticated_credential then -- Fallback on credential
        identifier = ngx.ctx.authenticated_credential.id
      end
    elseif conf.limit_by == "credential" then
      identifier = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.id
    elseif conf.limit_by == "token" then
        identifier = token
    end

    if not identifier then
      identifier = ngx.var.remote_addr
    end

    return identifier
end

function RateLimit:get_usage(conf, api_id, identifier, current_timestamp, limits)
    local usage = {}
    local stop

    for name, limit in pairs(limits) do
      local current_usage, err = policies[conf.policy].usage(conf, api_id, identifier, current_timestamp, name)
      if err then
        return nil, nil, err
      end

      -- What is the current usage for the configured limit name?
      local remaining = limit - current_usage

      -- Recording usage
      usage[name] = {
        limit = limit,
        remaining = remaining
      }

      if remaining <= 0 then
        stop = name
      end
    end

    return usage, stop
end

function RateLimit:rate_limit(conf)
    local current_timestamp = timestamp.get_utc()

    -- Consumer is identified by ip address or authenticated_credential id
    local identifier = get_identifier(conf)
    local api_id = ngx.ctx.api.id
    local policy = conf.policy
    local fault_tolerant = conf.fault_tolerant

    -- Load current metric for configured period
    local limits = {
        second = conf.second,
        minute = conf.minute,
        hour = conf.hour,
        day = conf.day,
        month = conf.month,
        year = conf.year
    }

    local usage, stop, err = get_usage(conf, api_id, identifier, current_timestamp, limits)
    if err then
        if fault_tolerant then
            ngx_log(ngx.ERR, "failed to get usage: ", tostring(err))
        else
            return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
    end

    if usage then
        -- Adding headers
        if not conf.hide_client_headers then
            for k, v in pairs(usage) do
            ngx.header[RATELIMIT_LIMIT .. "-" .. k] = v.limit
            ngx.header[RATELIMIT_REMAINING .. "-" .. k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
            end
        end

        -- If limit is exceeded, terminate the request
        if stop then
            return responses.send(429, "API rate limit exceeded")
        end
    end

    local incr = function(premature, conf, limits, api_id, identifier, current_timestamp, value)
        if premature then
            return
        end
        policies[policy].increment(conf, limits, api_id, identifier, current_timestamp, value)
    end

    -- Increment metrics for configured periods if the request goes through
    local ok, err = ngx_timer_at(0, incr, conf, limits, api_id, identifier, current_timestamp, 1)
    if not ok then
        ngx_log(ngx.ERR, "failed to create timer: ", err)
    end
end

return RateLimit
