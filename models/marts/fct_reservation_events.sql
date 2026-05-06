-- lookback=3: on every run, dbt reprocesses the 3 most recently completed
-- day-batches in addition to any new ones. This catches late-arriving source
-- records (e.g. a booking inserted a day or two after the fact) without a
-- full rebuild.
{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='reservation_date',
    batch_size='month',
    lookback=3,
    begin='2022-01-01',
    on_schema_change='fail'
  )
}}

WITH fct_reservations AS (
    SELECT * FROM {{ ref('zuilense_tennis_club', 'fct_reservations') }}
),

bridge_member_reservations AS (
    SELECT * FROM {{ ref('zuilense_tennis_club', 'bridge_member_reservations') }}
),

dim_members_anonimized AS (
    SELECT * FROM {{ ref('dim_members_anonimized') }}
),

reservations AS (
    SELECT
        reservation_id,
        reservation_date,
        court_number,
        start_time,
        end_time,
        duration_in_mins,
        reservation_type,
        event_description,
        DAYOFWEEK(reservation_date) AS day_of_week,
        DAYNAME(reservation_date) AS day_of_week_name,
        HOUR(start_time) AS start_hour
    FROM fct_reservations
    WHERE reservation_type = 'Gereserveerd'
),

member_bridge AS (
    SELECT
        reservation_id,
        member_id
    FROM bridge_member_reservations
),

member_profiles AS (
    SELECT
        member_id,
        gender,
        age_group,
        city,
        current_type_of_membership,
        is_club_member,
        is_knltb_member
    FROM dim_members_anonimized
),

final AS (
    SELECT
        r.reservation_id,
        r.reservation_date,
        r.court_number,
        r.start_time,
        r.end_time,
        r.duration_in_mins,
        r.day_of_week,
        r.day_of_week_name,
        r.start_hour,
        b.member_id,
        p.gender,
        p.age_group,
        p.city,
        p.current_type_of_membership,
        p.is_club_member,
        p.is_knltb_member
    FROM reservations AS r
    LEFT JOIN member_bridge AS b ON r.reservation_id = b.reservation_id
    LEFT JOIN member_profiles AS p ON b.member_id = p.member_id
)

SELECT * FROM final
