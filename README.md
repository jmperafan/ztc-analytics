# ztc-analytics

Analytics project for Zuilense Tennis Club, running on dbt v2 (Fusion) on the dbt platform. It's a downstream consumer of `ztc_core` via dbt Mesh.

This project is the playground for the dbt Semantic Layer and Python models. It trades some governance rigour for speed: models are documented and tested on keys, but don't require column-level contracts.

## Architecture

```
ztc_core (foundation: contracts, CI, public models)
    └── ztc_analytics (this project: marts, Semantic Layer, Python/ML)
```

Cross-project refs look like `{{ ref('ztc_core', 'fct_court_usage') }}`.

## Project structure

```
models/
  marts/                          -- public, owned by analytics engineering
    fct_hourly_usage.sql          -- slot-level court activity for hour-of-day analysis
    dim_members_anonymized.sql    -- anonymised member dimension
    dim_coaches_anonymized.sql    -- coach dimension without names or contact details
    fct_coaching_lessons.sql      -- one row per lesson (wrapper over ztc_core)
    fct_member_invoices.sql       -- one row per invoice (wrapper over ztc_core)
  python/                         -- protected, owned by data science
    python_court_stats.py         -- descriptive stats with Polars
    python_member_segments.py     -- k-means member clustering with scikit-learn
    python_demand_forecast.py     -- 30-day utilization forecast (seasonal model)
  metrics/                        -- Semantic Layer: metrics, saved queries, time spine
macros/
  generate_schema_name.sql
scripts/
  ossie_bridge.py                 -- export the Semantic Layer to Apache Ossie
```

The Semantic Layer is documented in [models/metrics/README.md](models/metrics/README.md).

## Setup

Prerequisites: the [dbt platform CLI](https://docs.getdbt.com/docs/cloud/cloud-cli-installation) and access to the `ztc_analytics` project on the dbt platform. `ztc_core` must be deployed so its public models resolve.

1. Download your `dbt_cloud.yml` credentials file from the dbt platform into `~/.dbt/`, as described in the install guide.
2. Run the checks:

   ```bash
   dbt parse          # compiles against dbt 2.x on the platform
   dbt build
   dbt sl validate    # Semantic Layer validation
   ```

## CI

Every PR to `main` triggers the dbt platform CI job, which runs `dbt build --select state:modified+` in a `ci_pr_<number>` schema, deferring to production.

The `dbt Cloud CI` GitHub Action in [.github/workflows/dbt-cloud-ci.yml](.github/workflows/dbt-cloud-ci.yml) triggers the same job through the API. It needs the secrets `DBT_CLOUD_API_TOKEN`, `DBT_CLOUD_ACCOUNT_ID` and `DBT_CLOUD_CI_JOB_ID`, and the variable `DBT_CLOUD_BASE_URL`. These aren't configured yet, so the Action currently fails.
