import polars as pl


def model(dbt, session):
    dbt.config(
        materialized="table",
        packages=["snowflake-snowpark-python", "polars"],
        tags=["python", "example"],
    )

    df = pl.from_arrow(
        dbt.ref("ztc_core", "fct_reservations").to_arrow()
    )

    stats = df.group_by("COURT_NUMBER").agg(
        pl.col("DURATION_IN_MINS").mean().alias("avg_duration_mins"),
        pl.col("DURATION_IN_MINS").median().alias("median_duration_mins"),
        pl.col("DURATION_IN_MINS").std().alias("std_duration_mins"),
        pl.len().alias("total_reservations"),
    )

    session.use_database(dbt.this.database)
    session.use_schema(dbt.this.schema)
    return session.create_dataframe(stats.to_pandas())
