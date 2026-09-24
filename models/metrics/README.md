# Metrics and the dbt Semantic Layer

Everything is authored in the latest YAML spec and runs on dbt v2 (Fusion). You query it through the dbt platform CLI, Studio IDE or VS Code with `dbt sl`.

## Where things live

| What | Where |
|---|---|
| Semantic models, entities, dimensions and simple metrics | On the model they describe: [models/marts/_models.yml](../marts/_models.yml) and [ossie/_ossie_court_usage.yml](ossie/_ossie_court_usage.yml) |
| Ratio, cumulative, derived and conversion metrics | [_metrics.yml](_metrics.yml) (top-level `metrics:`) |
| Saved queries and exports | [_saved_queries.yml](_saved_queries.yml) |
| Time spine | [metricflow_time_spine.sql](metricflow_time_spine.sql). It starts in 1980 so `cumulative_members` reaches the earliest `member_since`. |

| Semantic model | Model | Entity | Covers |
|---|---|---|---|
| `members` | `dim_members_anonymized` | `member` | Headcount, KNLTB share, new-member trends |
| `lessons` | `fct_coaching_lessons` | `lesson` → `member`, `coach` | Lesson volume, revenue, cancellations, no-shows |
| `invoices` | `fct_member_invoices` | `invoice` → `member` | Invoiced, paid, outstanding and overdue amounts |
| `coaches` | `dim_coaches_anonymized` | `coach` | Coach headcount and rates |
| `court_usage` | `ossie_court_usage` | `slot_id` | Court slots and utilization |

MetricFlow joins through the entities, so nobody writes a join:

```
coaches ◄── coach ── lessons ── member ──► members ◄── member ── invoices
```

`court_usage` stands alone. It was first written in Apache Ossie, which is why it lives in `ossie/`, but it's plain dbt YAML now.

## Query

```bash
# Discover
dbt sl list metrics [--search <exact_name>] [--show-all-dimensions]
dbt sl list dimensions --metrics total_members,knltb_members
dbt sl list dimension-values --metrics total_members --dimension member__gender
dbt sl list saved-queries [--show-exports]

# Query: group by metric_time__<grain> (day|week|month|quarter|year) or <entity>__<dimension>
dbt sl query --metrics total_members,knltb_share
dbt sl query --metrics lesson_revenue --group-by coach__specialty --order-by -lesson_revenue --limit 5
dbt sl query --metrics invoiced_amount,invoiced_amount_mom_growth --group-by metric_time__month
dbt sl query --saved-query membership_mix

# Show the generated SQL without running it
dbt sl query --metrics knltb_share --group-by member__age_group --compile
```

- `--order-by` takes `-` for descending. `--limit` defaults to 100 (max 1024).
- There's no time-range flag. Use `--where`.
- Don't put spaces after commas: `--metrics a,b`.
- `--search` is effectively an exact name match.

### Filters

```bash
--where "{{ Dimension('member__city') }} = 'Utrecht'"
--where "{{ Dimension('member__is_knltb_member') }}"                    # boolean
--where "{{ TimeDimension('metric_time', 'month') }} >= '2024-01-01'"
--where "{{ Entity('member') }} is not null"
--where "..." --where "..."                                              # ANDed
```

Single-quote the literals inside the double-quoted filter. In zsh, add `setopt BRACECCL` to `~/.zshrc` if `{{ }}` gets mangled.

### Validate and export

| Task | Command |
|---|---|
| Refresh `semantic_manifest.json` after a YAML change | `dbt parse` |
| Semantic and warehouse validation | `dbt sl validate` |
| Materialize saved query exports (in a job) | `dbt build --resource-type saved_query` |
| Run one saved query's exports | `dbt sl export --saved-query membership_mix` |
| Migrate legacy semantic YAML | `uvx dbt-autofix deprecations --semantic-layer [--dry-run]` |

A passing `dbt sl validate` doesn't guarantee a metric is queryable, so always run one real query.

## Latest YAML spec, at a glance

```yaml
models:
  - name: dim_members_anonymized
    semantic_model: { enabled: true, name: members }
    agg_time_dimension: member_since          # model level; Fusion rejects it under semantic_model
    columns:
      - name: member_id
        entity: { type: primary, name: member }
      - name: member_since
        granularity: day
        dimension: { type: time }
      - name: city
        dimension: { type: categorical, label: City }
    metrics:                                  # simple metrics replace measures
      - name: total_members
        type: simple
        agg: count_distinct                   # sum | count | count_distinct | average | min | max | sum_boolean | median | percentile
        expr: member_id
        filter: "{{ Dimension('member__is_club_member') }}"   # optional

metrics:                                      # built from other metrics, top level
  - { name: knltb_share, type: ratio, numerator: knltb_members, denominator: total_members }
  - { name: cumulative_members, type: cumulative, input_metric: total_members }   # + window / grain_to_date
  - name: new_members_yoy_change
    type: derived
    expr: cur - prev
    input_metrics:
      - { name: total_members, alias: cur }
      - { name: total_members, alias: prev, offset_window: 1 year }
  - name: new_member_lesson_conversion      # funnel; input metrics must be count_distinct
    type: conversion
    entity: member
    calculation: conversion_rate
    base_metric: total_members
    conversion_metric: lessons_booked
    window: 90 days
```

Simple metric extras: `fill_nulls_with: 0` (0 instead of null when no rows match) and `agg_time_dimension: <col>` (per-metric override).

## Exporting to Apache Ossie

dbt v2 can't read or write Ossie natively yet. [scripts/ossie_bridge.py](../../scripts/ossie_bridge.py) runs the official converter in an isolated uv environment:

```bash
dbt parse && uv run scripts/ossie_bridge.py     # -> target/ossie_document.yaml
```

Ossie is a lowest common denominator, so some semantics don't survive:

| dbt | In Ossie | Warned? |
|---|---|---|
| Cumulative metrics | Plain aggregates; the running window is lost | Yes |
| Conversion metrics, private metrics | Dropped | Yes (conversion) |
| Derived metrics with `offset_window` | The offset is lost, so `new_members_yoy_change` always evaluates to 0 | **No** |
| Metric filters on dimensions | Refer to MetricFlow names, not columns | No |
| `agg_time_dimension` | No equivalent | No |

## Gotchas

- **Legacy semantic YAML is ignored on dbt v2**, apart from a deprecation warning. `dbt-autofix` migrates it but drops labels and duplicates descriptions, so review its output.
- **The latest spec doesn't support cross-project refs yet.** Every semantic model needs a local model, so `fct_coaching_lessons`, `fct_member_invoices` and `dim_coaches_anonymized` are thin wrappers over `ztc_core`.
- **Fusion rejects `expr` on a column-level entity.** The `member_id` type mismatch (text in `ztc_core` facts, number in members) is fixed in the wrapper SQL with `TRY_TO_NUMBER`. The raw id is kept as `source_member_id`.
- **Conversion metrics reject a `count` input metric** on Fusion. `lessons_booked` uses `count_distinct` on the primary key instead.
- **Counts on dimension tables slice by their time dimension.** `total_members` and `active_coaches` by `metric_time` count joiners and hires per period, not headcount.
- **One member has no `member_since`.** They show up as a `<nil>` year and fall outside `cumulative_members`. Filter `metric_time is not null` when ordering by year.
- **About 5% of lessons and invoices belong to "GHOST-…" member ids** with no member record. They surface as a `<nil>` member bucket. The per-member ratios filter them out of the numerator.
- **Data ends in October 2024.** Later court-usage years hold placeholder slots only, so utilization reads 0.
