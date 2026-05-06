{{
  config(
    materialized='incremental',
    unique_key='daily_court_key',
    incremental_strategy='delete+insert',
    on_schema_change='fail'
  )
}}

WITH fct_court_usage AS (
    SELECT * FROM {{ ref('zuilense_tennis_club', 'fct_court_usage') }}
),

filtered AS (
    SELECT *
    FROM fct_court_usage
    WHERE
        NOT is_winter_break

    {% if is_incremental() %}
        AND reservation_date > (SELECT MAX(reservation_date) FROM {{ this }})  -- noqa: RF02
    {% endif %}
),

final AS (
    SELECT
        CONCAT(
            court_number::varchar, '_', reservation_date::varchar
        ) AS daily_court_key,
        court_number,
        reservation_date,
        COUNT_IF(reservation_type = 'Gereserveerd') AS booked_slots,
        COUNT_IF(reservation_type = 'Beschikbaar') AS available_slots,
        COUNT_IF(reservation_type IN ('Gereserveerd', 'Beschikbaar')) AS total_playable_slots,
        SUM(
            CASE
                WHEN reservation_type = 'Gereserveerd'
                    THEN duration_in_mins
                ELSE 0
            END
        ) AS booked_minutes,
        SUM(
            CASE
                WHEN reservation_type IN ('Gereserveerd', 'Beschikbaar')
                    THEN duration_in_mins
                ELSE 0
            END
        ) AS available_minutes,
        ROUND(
            COUNT_IF(reservation_type = 'Gereserveerd') * 100.0
            / NULLIF(COUNT_IF(reservation_type IN ('Gereserveerd', 'Beschikbaar')), 0),
            2
        ) AS utilization_pct
    FROM filtered
    GROUP BY 1, 2, 3
)

SELECT * FROM final
