WITH members AS (
    SELECT * FROM {{ ref('ztc_core', 'dim_members') }}
),

final AS (
    SELECT
        member_id,
        member_since,
        gender,
        age_group,
        city,
        current_type_of_membership,
        is_club_member,
        is_knltb_member
    FROM members
)

SELECT * FROM final
