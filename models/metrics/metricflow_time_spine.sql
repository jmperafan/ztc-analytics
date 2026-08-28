{{ config(materialized='table') }}

WITH RECURSIVE spine AS (
    SELECT CAST('1980-01-01' AS DATE) AS date_day
    UNION ALL
    SELECT DATEADD('day', 1, date_day)
    FROM spine
    WHERE date_day < DATEADD('year', 1, CURRENT_DATE())
)

SELECT date_day FROM spine
