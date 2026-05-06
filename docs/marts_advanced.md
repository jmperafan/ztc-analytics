{% docs fct_hourly_weather_usage %}

# Hourly Court Usage + Weather

One row per **court × date × hour**. Weather observations are merged in so that
late-arriving corrections are automatically applied on the next dbt run.

---

## When to use this model

| Use case | Recommended model |
|---|---|
| Hour-of-day patterns | ✅ This model |
| Day-level totals | `fct_daily_court_stats` |
| Raw bookings | `fct_reservation_events` |

---

## How `ideal_weather` is calculated

The `ideal_weather` flag is set to `TRUE` when **all three** conditions are met:

- 🌡️ Temperature between **10 °C and 35 °C**
- 🌧️ Precipitation = **0 mm**
- 💨 Wind speed ≤ **20 km/h**

```sql
-- From the tennis_weather macro
temperature between 10 and 35
and precipitation = 0
and wind_speed <= 20
```

> **Note:** Wind speed is in km/h. Make sure you're not comparing against m/s values
> from external APIs — they will make the flag unreliable.

---

## Lineage

`stg_reservations` → `int_court_usage` → `fct_court_usage` → `fct_hourly_usage`
↘ (joined with) `fct_weather` → **`fct_hourly_weather_usage`**

---

## Known limitations

1. Weather data has gaps for dates before 2022-03-01.
2. Courts 4 and 5 were added mid-season; `utilization_pct` may be misleading before 2022-06-01.
3. `ideal_weather` is a club-defined threshold — it is **not** a meteorological standard.

{% enddocs %}
