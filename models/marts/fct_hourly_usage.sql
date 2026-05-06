WITH source AS (
    SELECT * FROM {{ ref('zuilense_tennis_club', 'fct_court_usage') }}
),

hourly AS (
    SELECT
        reservation_id,
        court_number,
        reservation_date,
        start_time,
        reservation_type,
        event_description,
        HOUR(start_time) AS start_hour
    FROM source
    WHERE is_winter_break = FALSE
)

SELECT * FROM hourly
