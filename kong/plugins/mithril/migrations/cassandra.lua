return {
    {
        name = "2017-12-05-132400_init_rate_limiting",
        up = [[
            CREATE TABLE IF NOT EXISTS mithril_rate_limiting(
                api_id uuid,
                identifier text,
                period text,
                period_date timestamp,
                value counter,
                PRIMARY KEY ((api_id, identifier, period_date, period))
            );
        ]],
        down = [[
            DROP TABLE mithril_rate_limiting;
        ]]
    },
}
