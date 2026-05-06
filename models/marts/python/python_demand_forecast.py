from datetime import timedelta

import polars as pl

OPENING_HOUR = 8
CLOSING_HOUR = 23
AVAILABLE_MINS = (CLOSING_HOUR - OPENING_HOUR) * 60  # 900
FORECAST_HORIZON = 30

SEASONAL_FACTORS = pl.DataFrame(
    {
        "month": list(range(1, 13)),
        "seasonal_factor": [
            0.65, 0.70, 0.85, 1.00, 1.10, 1.15,
            1.10, 1.10, 1.05, 0.90, 0.75, 0.65,
        ],
    }
)


def load_usage(dbt) -> pl.DataFrame:
    return (
        pl.from_arrow(
            dbt.ref("zuilense_tennis_club", "fct_court_usage").to_arrow()
        )
        .filter(pl.col("IS_WINTER_BREAK").cast(pl.Boolean).not_())
        .with_columns(pl.col("RESERVATION_DATE").cast(pl.Date))
    )


def daily_utilization(usage: pl.DataFrame) -> pl.DataFrame:
    return (
        usage.filter(pl.col("RESERVATION_TYPE") != "Gesloten")
        .with_columns(
            pl.when(pl.col("RESERVATION_TYPE") != "Beschikbaar")
            .then(pl.col("DURATION_IN_MINS"))
            .otherwise(0)
            .alias("booked_mins")
        )
        .group_by("COURT_NUMBER", "RESERVATION_DATE")
        .agg(pl.col("booked_mins").sum())
        .with_columns(
            (pl.col("booked_mins") / AVAILABLE_MINS).clip(0, 1).alias("utilization_rate"),
            pl.col("RESERVATION_DATE").dt.weekday().alias("day_of_week"),
            pl.col("RESERVATION_DATE").dt.month().alias("month"),
        )
    )


def dow_baselines(daily: pl.DataFrame) -> pl.DataFrame:
    return daily.group_by("COURT_NUMBER", "day_of_week").agg(
        pl.col("utilization_rate").mean().alias("dow_avg")
    )


def trend_factors(daily: pl.DataFrame) -> pl.DataFrame:
    recent_dates = daily["RESERVATION_DATE"].unique().sort(descending=True).head(28)
    overall = daily.group_by("COURT_NUMBER").agg(
        pl.col("utilization_rate").mean().alias("overall_mean")
    )
    recent = (
        daily.filter(pl.col("RESERVATION_DATE").is_in(recent_dates))
        .group_by("COURT_NUMBER")
        .agg(pl.col("utilization_rate").mean().alias("recent_mean"))
    )
    return (
        overall.join(recent, on="COURT_NUMBER")
        .with_columns(
            (pl.col("recent_mean") / pl.col("overall_mean")).clip(0.5, 1.5).alias("trend_factor")
        )
        .select("COURT_NUMBER", "trend_factor")
    )


def build_forecast_grid(daily: pl.DataFrame) -> pl.DataFrame:
    last_date = daily["RESERVATION_DATE"].max()
    forecast_dates = pl.DataFrame(
        {
            "forecast_date": pl.date_range(
                start=last_date + timedelta(days=1),
                end=last_date + timedelta(days=FORECAST_HORIZON),
                interval="1d",
                eager=True,
            ),
            "forecast_horizon_days": range(1, FORECAST_HORIZON + 1),
        }
    )
    return (
        daily.select("COURT_NUMBER").unique()
        .join(forecast_dates, how="cross")
        .with_columns(
            pl.col("forecast_date").dt.weekday().alias("day_of_week"),
            pl.col("forecast_date").dt.month().alias("month"),
        )
        .join(SEASONAL_FACTORS, on="month")
    )


def model(dbt, session):
    dbt.config(
        materialized="table",
        packages=["snowflake-snowpark-python", "polars"],
        tags=["python", "forecasting"],
    )

    daily = load_usage(dbt).pipe(daily_utilization)

    result = (
        build_forecast_grid(daily)
        .join(dow_baselines(daily), on=["COURT_NUMBER", "day_of_week"])
        .join(trend_factors(daily), on="COURT_NUMBER")
        .with_columns(
            (pl.col("dow_avg") * pl.col("trend_factor") * pl.col("seasonal_factor"))
            .clip(0, 1)
            .round(4)
            .alias("predicted_utilization_rate")
        )
        .select(
            pl.col("COURT_NUMBER"),
            "forecast_date",
            "predicted_utilization_rate",
            "day_of_week",
            "month",
            "forecast_horizon_days",
            pl.lit("seasonal_dow_with_trend").alias("model_type"),
        )
    )

    result = result.rename({col: col.upper() for col in result.columns})
    session.use_database(dbt.this.database)
    session.use_schema(dbt.this.schema)
    return session.create_dataframe(result.to_pandas())
