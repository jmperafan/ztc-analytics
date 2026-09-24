WITH invoices AS (
    SELECT * FROM {{ ref('ztc_core', 'fct_invoices') }}
),

final AS (
    SELECT
        invoice_id,
        -- ztc_core stores member_id as text and ~5% are "GHOST-…" ids with no
        -- member record. Cast to match dim_members_anonymized so the member
        -- entity joins; orphans become null and keep their raw id alongside.
        TRY_TO_NUMBER(member_id) AS member_id,
        member_id AS source_member_id,
        invoice_date,
        due_date,
        paid_date,
        days_to_pay,
        total_amount,
        status,
        is_paid,
        is_overdue,
        payment_method
    FROM invoices
)

SELECT * FROM final
