import polars as pl
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

FEATURE_COLS = [
    "total_bookings",
    "avg_duration_mins",
    "avg_start_hour",
    "pct_weekend",
    "unique_courts",
]
N_CLUSTERS = 4


def load_data(dbt) -> pl.DataFrame:
    reservations = pl.from_arrow(
        dbt.ref("zuilense_tennis_club", "fct_reservations").to_arrow()
    )
    bridge = pl.from_arrow(
        dbt.ref("zuilense_tennis_club", "bridge_member_reservations").to_arrow()
    )
    members = pl.from_arrow(
        dbt.ref("zuilense_tennis_club", "dim_members").to_arrow()
    )
    return (
        reservations.join(bridge, on="RESERVATION_ID")
        .with_columns(pl.col("MEMBER_ID").cast(pl.Int64))
        .join(members.select(pl.col("MEMBER_ID").cast(pl.Int64)), on="MEMBER_ID")
    )


def engineer_features(df: pl.DataFrame) -> pl.DataFrame:
    return (
        df.with_columns(
            pl.col("RESERVATION_START").cast(pl.Datetime).dt.hour().alias("hour"),
            pl.col("RESERVATION_START").cast(pl.Datetime).dt.weekday().alias("weekday"),
        )
        .group_by("MEMBER_ID")
        .agg(
            pl.len().alias("total_bookings"),
            pl.col("DURATION_IN_MINS").mean().alias("avg_duration_mins"),
            pl.col("hour").mean().alias("avg_start_hour"),
            (pl.col("weekday") >= 6).mean().alias("pct_weekend"),
            pl.col("COURT_NUMBER").n_unique().alias("unique_courts"),
        )
        .fill_null(0)
    )


def cluster(features: pl.DataFrame) -> pl.DataFrame:
    X_scaled = StandardScaler().fit_transform(features.select(FEATURE_COLS).to_numpy())
    labels = KMeans(n_clusters=N_CLUSTERS, random_state=42, n_init=10).fit_predict(
        X_scaled
    )
    return features.with_columns(pl.Series("segment", labels.tolist()))


def label_segments(features: pl.DataFrame) -> pl.DataFrame:
    stats = features.group_by("segment").agg(
        pl.col("total_bookings").mean(),
        pl.col("avg_start_hour").mean(),
        pl.col("pct_weekend").mean(),
    )
    median_bookings = stats["total_bookings"].median()

    stats = stats.with_columns(
        pl.when(pl.col("pct_weekend") >= 0.5)
        .then(pl.lit("Weekend Player"))
        .when(
            (pl.col("total_bookings") >= median_bookings)
            & (pl.col("avg_start_hour") < 13)
        )
        .then(pl.lit("Frequent Morning Player"))
        .when(pl.col("total_bookings") >= median_bookings)
        .then(pl.lit("Frequent Evening Player"))
        .otherwise(pl.lit("Casual Player"))
        .alias("segment_label")
    )
    return features.join(stats.select("segment", "segment_label"), on="segment")


def model(dbt, session):
    dbt.config(
        materialized="table",
        packages=["snowflake-snowpark-python", "polars", "scikit-learn"],
        tags=["python", "ml", "members"],
    )

    df = (
        load_data(dbt)
        .pipe(engineer_features)
        .pipe(cluster)
        .pipe(label_segments)
        .select(["MEMBER_ID", "segment", "segment_label", *FEATURE_COLS])
        .rename(
            {
                col: col.upper()
                for col in ["MEMBER_ID", "segment", "segment_label", *FEATURE_COLS]
            }
        )
    )
    session.use_database(dbt.this.database)
    session.use_schema(dbt.this.schema)
    return session.create_dataframe(df.to_pandas())
