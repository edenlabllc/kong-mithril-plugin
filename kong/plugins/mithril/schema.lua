local function rule_check(value)
    local rule_fields = {
        path  = "string",
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
            return false, "'rules."..(k - 1).."' is not a table"
        end

        for key, val in pairs(v) do
            if rule_fields[key] == nil then
                return false, "'rules."..(k - 1).."."..key.."' is not allowed field"
            end
        end

        for key, key_type in pairs(rule_fields) do
            if v[key] == nil then
                return false, "'rules."..(k - 1).."."..key.."' is required"
            end
            if type(v[key]) ~= key_type then
                return false, "'rules."..(k - 1).."."..key.."' is invalid type. "..key_type.." expected"
            end
        end

        for key, val in pairs(v["scopes"]) do
            if type(val) ~= "string" then
                return false, "'rules."..(k - 1)..".scopes."..(key - 1).."' is not a string"
            end
        end

        for key, val in pairs(v["methods"]) do
            if type(val) ~= "string" then
                return false, "'rules."..(k - 1)..".methods"..(key - 1).."' is not a string"
            end

            if not valid_methods[val] then
                return false, "'rules."..(k - 1)..".methods"..(key - 1).."' is invalid method"
            end
        end
    end

    return true
end

return {
    no_consumer = true, -- this plugin will only be API-wide,
    fields = {
        url_template = {type = "string", required = true},
        rules = {type = "array", default = {}, func = rule_check}
    }
}
