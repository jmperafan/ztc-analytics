{% docs fct_daily_court_stats %}
Daily aggregation of court usage per court. One row per `court_number × reservation_date`,
covering non-winter-break days only.

Use this model for day-level utilization reporting and trend analysis.
{% enddocs %}

{% docs utilization_pct %}
Share of playable minutes that were booked, expressed as a percentage
(`booked_slots / total_playable_slots × 100`). NULL when no playable slots exist.
{% enddocs %}
