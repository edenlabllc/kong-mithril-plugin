local SCHEMA = {
    primary_key = {"api_id", "identifier", "period_date", "period"},
    table = "mithril_rate_limiting", -- the actual table in the database
    fields = {
        api_id = {type = "id", required = true, foreign = "apis:id"}, -- a foreign key to a Consumer's id
        identifier = {type = "string", required = true},
        period = {type = "string", required = true},
        period_date = {type = "timestamp", immutable = true, dao_insert_value = true}, -- also interted by the DAO itself
        value = {type = "integer", required = true} -- a unique API key
    }
  }

return {mithril_rate_limiting = SCHEMA}
