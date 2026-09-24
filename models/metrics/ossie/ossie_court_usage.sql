SELECT
    *,
    court_number || '-' || reservation_date || '-' || start_time AS slot_id
FROM {{ ref('fct_hourly_usage') }}
