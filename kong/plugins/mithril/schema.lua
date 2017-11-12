return {
    no_consumer = true, -- this plugin will only be API-wide,
    fields = {
        url_template = {type = "string", required = true},
    },
    self_check = function(schema, plugin_t, dao, is_updating)
      -- perform any custom verification
      return true
    end
}
