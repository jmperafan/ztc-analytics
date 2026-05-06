# ztc-analytics

Analytics project for Zuilense Tennis Club. Downstream consumer of `ztc_core` via dbt Mesh.

This project is the demo playground for advanced dbt features: Python models, the Semantic Layer, metrics, microbatch incremental, and the high-watermark pattern. It trades some governance rigour for speed of delivery — models are well-documented and tested on primary keys, but do not require full column-level contracts.

---

## Architecture

```
ztc_core (foundation — impeccable governance, contracts, CI)
    └── ztc_analytics (this project — analytics, ML, Semantic Layer)
```

Cross-project refs follow the pattern:

```sql
{{ ref('ztc_core', 'fct_court_usage') }}
```

---

## Project structure

```
models/
  marts/
    fct_reservation_events.sql    -- microbatch incremental (one booking per row)
    fct_daily_court_stats.sql     -- delete+insert incremental (court × date aggs)
    fct_hourly_weather_usage.sql  -- merge incremental (court × hour × date + weather)
    fct_hourly_usage.sql          -- slot-level table for hour-of-day analysis
    fct_reservations_hwm.sql      -- high-watermark incremental pattern demo
    dim_members_anonymized.sql    -- anonymised member dimension (8 safe columns)
    python/
      python_court_stats.py       -- descriptive stats with Polars (median demo)
      python_member_segments.py   -- k-means member clustering with scikit-learn
      python_demand_forecast.py   -- 30-day utilization forecast (seasonal model)
macros/
  watermark/                      -- high-watermark macro library
```

---

## Incremental strategies at a glance

| Model | Strategy | Why |
|---|---|---|
| `fct_reservation_events` | microbatch | dbt manages time windows; handles late arrivals via `lookback=3` |
| `fct_daily_court_stats` | delete+insert | simple date-keyed aggregation |
| `fct_hourly_weather_usage` | merge | composite unique key across three columns |
| `fct_reservations_hwm` | merge + HWM | demonstrates the high-watermark pattern for MECE processing windows |

---

## Local setup

**Prerequisites:** Python 3.11+, access to the Snowflake `ANALYTICS_DEV` database.

```bash
# 1. Install dependencies
pip install dbt-snowflake sqlfluff

# 2. Configure Snowflake credentials (add to ~/.dbt/profiles.yml)
ztc_analytics:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: fka50167
      user: <your_username>
      password: <your_password>
      role: TRANSFORMER
      database: ANALYTICS_DEV
      warehouse: TRANSFORMING
      schema: "dbt_{{ env_var('DBT_USER', 'dev') }}"

# 3. Install dbt packages (ztc_core must already be deployed)
dbt deps

# 4. Verify connection
dbt debug

# 5. Build all models
dbt build
```

---

## CI

Three GitHub Actions workflows run on every PR to `main`:

| Workflow | What it checks | Credentials needed |
|---|---|---|
| `sqlfluff.yml` | SQL style (dialect: Snowflake) | None |
| `bouncer.yml` | Naming, test coverage, lineage | dbt Cloud API token |
| `dbt-cloud-ci.yml` | SQL correctness against real data | dbt Cloud API token + Snowflake (via dbt Cloud) |

Required GitHub secrets: `DBT_CLOUD_API_TOKEN`, `DBT_CLOUD_ACCOUNT_ID`, `DBT_CLOUD_CI_JOB_ID`, `DBT_CLOUD_PROD_JOB_ID`.  
Required GitHub variable: `DBT_CLOUD_BASE_URL`.
