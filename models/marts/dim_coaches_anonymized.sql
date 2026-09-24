-- Names, email and phone are deliberately left out: coaches are identified by
-- coach_id only, in line with dim_members_anonymized.
WITH coaches AS (
    SELECT * FROM {{ ref('ztc_core', 'dim_coaches') }}
),

final AS (
    SELECT
        coach_id,
        hire_date,
        years_at_club,
        specialty,
        certification_level,
        hourly_rate,
        is_active
    FROM coaches
)

SELECT * FROM final
