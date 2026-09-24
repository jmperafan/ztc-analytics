# MetricFlow cheatsheet

Commands for the dbt Semantic Layer on dbt v2, through the dbt platform CLI, Studio IDE or VS Code. All of them start with `dbt sl` and run remotely on the dbt platform.

Flags below were checked against the dbt platform CLI 0.40.23 on 2026-09-23. Where they differ from the docs, this sheet follows the CLI.

---

## Discover

| Task | Command |
|---|---|
| List metrics (+ their dimensions) | `dbt sl list metrics` |
| Find one metric | `dbt sl list metrics --search court_slots` |
| All dimensions per metric | `dbt sl list metrics --show-all-dimensions` |
| Dimensions shared by metrics | `dbt sl list dimensions --metrics total_members,knltb_members` |
| Entities shared by metrics | `dbt sl list entities --metrics court_utilization` |
| Values of a dimension | `dbt sl list dimension-values --metrics total_members --dimension member__gender` |
| Saved queries | `dbt sl list saved-queries [--show-exports] [--show-parameters]` |

`--search` is effectively an exact name match on the dbt platform CLI: `court_slots` matches, `court` returns nothing.

---

## Query

```bash
# Metrics only (one grand-total row)
dbt sl query --metrics total_members,knltb_share

# By time, at a grain: day | week | month | quarter | year
dbt sl query --metrics booked_slots --group-by metric_time__month

# By dimension: <entity>__<dimension>
dbt sl query --metrics total_members --group-by member__age_group,member__gender

# Sort (- = descending) and limit
dbt sl query --metrics booked_slots --group-by slot_id__court_number --order-by -booked_slots --limit 3

# Saved query
dbt sl query --saved-query membership_mix
```

| Flag | `dbt sl query` |
|---|---|
| Metrics | `--metrics a,b` |
| Group by | `--group-by metric_time__year,member__city` |
| Filter (repeatable) | `--where "..."` |
| Sort | `--order-by -metric_time` |
| Limit | `--limit 500` (default 100, max 1024) |
| Show SQL | `--compile` (does not run the query) |
| Time range | use `--where` |

No spaces after commas: `--metrics a,b`, not `--metrics a, b`.

---

## Filters (`--where`)

```bash
# Categorical
--where "{{ Dimension('member__city') }} = 'Utrecht'"
--where "{{ Dimension('slot_id__reservation_type') }} not in ('Beschikbaar','Gesloten')"

# Boolean
--where "{{ Dimension('member__is_knltb_member') }}"

# Time, at a grain
--where "{{ TimeDimension('metric_time', 'month') }} >= '2024-01-01'"
--where "{{ TimeDimension('member__member_since', 'year') }} < '2000-01-01'"

# Entity
--where "{{ Entity('member') }} is not null"

# Several filters are ANDed
--where "..." --where "..."
```

In zsh, add `setopt BRACECCL` to `~/.zshrc` if `{{ }}` gets mangled. Always single-quote the string literals inside the double-quoted filter.

---

## Validate and build

| Task | Command |
|---|---|
| Refresh `semantic_manifest.json` after any YAML change | `dbt parse` |
| Semantic + warehouse validation | `dbt sl validate` |
| Migrate legacy YAML to the latest spec | `uvx dbt-autofix deprecations --semantic-layer [--dry-run]` |

`dbt sl validate` passing doesn't guarantee a metric is queryable. Always run one real query.

---

## Saved query exports

| Task | Command |
|---|---|
| Materialize all exports (in a job) | `dbt build --resource-type saved_query` |
| Run one saved query's exports | `dbt sl export --saved-query membership_mix [--select <export>] [--export-as table\|view] [--schema s] [--alias a]` |
| Run many | `dbt sl export-all [--saved-queries a,b] [--exports x,y]` |

---

## Apache Ossie in this project

| Task | Command |
|---|---|
| dbt → Ossie (`target/semantic_manifest.json` → `target/ossie_document.yaml`) | `dbt parse && uv run scripts/ossie_bridge.py` |
| Converter directly | `ossie-dbt msi-to-ossie -i target/semantic_manifest.json -o out.yaml` |

dbt v2 doesn't read or write Ossie natively yet. The semantic layer is authored in dbt YAML only.

---

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
  - name: lessons_per_student               # ratio with a filtered input
    type: ratio
    numerator: { name: lessons_delivered, filter: "{{ Entity('member') }} is not null" }
    denominator: students_coached
  - name: new_member_lesson_conversion      # funnel; input metrics must be count_distinct (Fusion rejects count)
    type: conversion
    entity: member
    calculation: conversion_rate            # or conversions
    base_metric: total_members
    conversion_metric: lessons_booked
    window: 90 days
```

Simple metric extras: `fill_nulls_with: 0` (show 0 instead of null when no rows match, useful for ratio numerators) and `agg_time_dimension: <col>` (per-metric override).
