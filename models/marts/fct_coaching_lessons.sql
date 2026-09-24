WITH lessons AS (
    SELECT * FROM {{ ref('ztc_core', 'fct_lessons') }}
),

final AS (
    SELECT
        lesson_id,
        lesson_date,
        start_hour,
        day_of_week_name,
        is_weekend,
        duration_minutes,
        lesson_type,
        skill_level,
        status,
        price,
        court_number,
        coach_id,
        -- ztc_core stores member_id as text and ~5% are "GHOST-…" ids with no
        -- member record. Cast to match dim_members_anonymized so the member
        -- entity joins; orphans become null and keep their raw id alongside.
        TRY_TO_NUMBER(member_id) AS member_id,
        member_id AS source_member_id
    FROM lessons
)

SELECT * FROM final
