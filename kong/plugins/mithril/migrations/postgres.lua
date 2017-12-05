return {
    {
        name = "2017-12-05-132400_init_rate_limiting",
        up = [[
            CREATE TABLE IF NOT EXISTS mithril_rate_limiting(
                api_id uuid,
                identifier text,
                period text,
                period_date timestamp without time zone,
                value integer,
                PRIMARY KEY (api_id, identifier, period_date, period)
            );
            CREATE OR REPLACE FUNCTION increment_mithril_rate_limits(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
            BEGIN
            LOOP
                UPDATE mithril_rate_limiting SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
                IF found then
                RETURN;
                END IF;
                BEGIN
                INSERT INTO mithril_rate_limiting(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
                RETURN;
                EXCEPTION WHEN unique_violation THEN
                END;
            END LOOP;
            END;
            $$ LANGUAGE 'plpgsql';
        ]],
        down = [[
            DROP TABLE mithril_rate_limiting;
        ]]
    },
}
