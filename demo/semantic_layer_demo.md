# Semantic layer demo: dbt metrics + Apache Ossie

A two-part demo on the ZTC tennis club data, running on dbt v2 (Fusion) through the dbt platform CLI. Everything is authored in the latest YAML spec.

| Part | Story | Where it lives |
|---|---|---|
| 1. dbt Semantic Layer | Metrics defined once in dbt, joined and queried the same way everywhere | `models/marts/_models.yml` (members, lessons, invoices, coaches), `models/metrics/` (incl. court usage in `ossie/`) |
| 2. dbt → Ossie | Export the semantic layer to the vendor-neutral Apache Ossie format for other tools, and show what gets lost | `scripts/ossie_bridge.py` → `target/ossie_document.yaml` |

Every command and result below was run against `ANALYTICS_DEV` on 2026-09-24 (dbt 2.0.6).

---

## Before you start

```bash
dbt parse                                               # must finish with no semantic errors
dbt build --select "metricflow_time_spine dim_members_anonymized fct_coaching_lessons fct_member_invoices dim_coaches_anonymized ossie_court_usage"
dbt sl validate
```

Add `setopt BRACECCL` to `~/.zshrc` if zsh mangles the `{{ Dimension(...) }}` filters.

---

## Part 1: the dbt Semantic Layer

**Talking point:** the latest YAML spec keeps semantics next to the model. There's no separate `semantic_models:` block and no measures, just columns tagged as entities and dimensions, plus simple metrics.

Show `dim_members_anonymized` in [models/marts/_models.yml](../models/marts/_models.yml), then [models/metrics/_metrics.yml](../models/metrics/_metrics.yml) for the metrics built on top: ratio, cumulative and derived with a time offset.

```bash
# What can I ask for?
dbt sl list dimensions --metrics total_members
dbt sl list dimension-values --metrics total_members --dimension member__gender

# Headline numbers: a simple, a filtered simple, and a ratio metric
dbt sl query --metrics total_members,active_members,knltb_members,knltb_share
```

```
| ACTIVE_MEMBERS | KNLTB_MEMBERS |  KNLTB_SHARE | TOTAL_MEMBERS |
|            430 |           424 | 0.9860465116 |           430 |
```

```bash
# Time: new members per year, running total, and year-on-year change
dbt sl query --metrics total_members,cumulative_members,new_members_yoy_change \
  --group-by metric_time__year --order-by -metric_time__year \
  --where "{{ TimeDimension('metric_time', 'year') }} <= '2024-01-01'"   # data ends in 2024
```

```
| METRIC_TIME__YEAR | CUMULATIVE_MEMBERS | NEW_MEMBERS_YOY_CHANGE | TOTAL_MEMBERS |
| 2024-01-01        |                396 | -55                    | 33            |
| 2023-01-01        |                308 | 25                     | 88            |
| 2022-01-01        |                245 | -5                     | 63            |
```

```bash
# Show the SQL MetricFlow writes, which people shouldn't have to write themselves
dbt sl query --metrics knltb_share --group-by member__age_group --compile

# A saved query: the same question, asked the same way, by name
dbt sl query --saved-query membership_mix --limit 5
```

### 1b. Joins: the reason to have a semantic layer

The dbt-native semantic models form a small star. Nobody writes a join; MetricFlow walks the entities.

```
          coaches ◄── coach ── lessons ── member ──► members ◄── member ── invoices
```

```bash
# Lesson revenue by coach specialty (lessons → coaches)
dbt sl query --metrics lesson_revenue,revenue_per_coaching_hour,lessons_delivered \
  --group-by coach__specialty,coach__certification_level --order-by -lesson_revenue --limit 5
```

```
| COACH__SPECIALTY   | COACH__CERTIFICATION_LEVEL | LESSON_REVENUE | LESSONS_DELIVERED | REVENUE_PER_COACHING_HOUR |
| Competitive        | Elite                      |       37647.25 |               692 |             54.6007976795 |
| Beginners          | Certified                  |        23002.9 |               425 |             54.2521226415 |
| Adult lessons      | Master                     |        17012.7 |               318 |             51.3978851964 |
```

```bash
# Two fact tables side by side through one shared dimension (lessons + invoices → members)
dbt sl query --metrics lesson_revenue,invoiced_amount,collection_rate,students_coached \
  --group-by member__gender --order-by -invoiced_amount
```

```
| MEMBER__GENDER | COLLECTION_RATE | INVOICED_AMOUNT | LESSON_REVENUE | STUDENTS_COACHED |
| Vrouw          |    0.9036993509 |          937678 |        75011.1 |              229 |
| Man            |    0.8933659101 |          780107 |       66005.95 |              200 |
| <nil>          |    0.9128318792 |           85272 |        4775.35 |                0 |
```

**Talking point on the `<nil>` row:** about 5% of lessons and invoices in `ztc_core` belong to "GHOST-…" member ids with no member record. The semantic layer doesn't hide them. They surface as an unknown bucket worth €85k of invoices. The per-member ratios (`lessons_per_student`, `invoiced_per_member`) filter them out of the numerator so they don't inflate the result.

### 1c. Every metric type

```bash
# Cumulative: month-to-date and trailing 28 days
dbt sl query --metrics invoiced_amount,invoiced_amount_mtd,invoiced_amount_trailing_28d \
  --group-by metric_time__day --order-by metric_time__day \
  --where "{{ TimeDimension('metric_time', 'day') }} between '2025-03-01' and '2025-03-05'"

# Derived with an offset: month-over-month growth
dbt sl query --metrics invoiced_amount,invoiced_amount_mom_growth --group-by metric_time__month \
  --where "{{ TimeDimension('metric_time', 'month') }} between '2025-01-01' and '2025-06-01'" \
  --order-by metric_time__month

# Conversion: share of new members who book a lesson within 90 days
dbt sl query --metrics new_member_lesson_conversion --group-by metric_time__year \
  --where "{{ TimeDimension('metric_time', 'year') }} is not null" \
  --order-by -metric_time__year --limit 2   # one member has no join date
```

```
| METRIC_TIME__YEAR | NEW_MEMBER_LESSON_CONVERSION |
| 2024-01-01        | 0.8484848485                 |
| 2023-01-01        | 0.0454545455                 |
```

Lesson data starts in 2024, so only late-2023 and 2024 joiners can convert. Say this before someone asks.

```bash
dbt sl query --saved-query coaching_performance --limit 5
dbt sl query --saved-query receivables --limit 5
```

### 1d. Court usage

The `court_usage` semantic model in [models/metrics/ossie/](../models/metrics/ossie/_ossie_court_usage.yml) was first written in Apache Ossie and converted to the latest spec. It's plain dbt YAML now, since dbt v2 can't read Ossie documents yet. Point out:
- `sum_boolean` metrics built on a SQL expression, not a column.
- `court_utilization` as a ratio of two of them.

```bash
dbt sl query --metrics court_slots,open_slots,booked_slots,court_utilization \
  --group-by metric_time__year --order-by metric_time__year
```

```
| METRIC_TIME__YEAR | BOOKED_SLOTS | COURT_SLOTS | OPEN_SLOTS | COURT_UTILIZATION |
| 2022-01-01        |         5543 |       12664 |       9418 |      0.5885538331 |
| 2023-01-01        |         4207 |       13037 |       8901 |      0.4726435232 |
| 2024-01-01        |         3797 |       12675 |       8119 |      0.4676684321 |
```

```bash
dbt sl query --metrics booked_slots,court_utilization \
  --group-by slot_id__court_number --order-by slot_id__court_number
dbt sl query --saved-query court_utilization_by_court
```

The data ends in October 2024. Later years contain placeholder slots only, so utilisation reads 0. Filter them out or explain it.

---

## Part 2: dbt → Apache Ossie

**Talking point:** Apache Ossie (formerly Open Semantic Interchange, now in the Apache Incubator) is a vendor-neutral format for datasets, fields, relationships and metrics. Any tool that reads Ossie can pick up the dbt definitions. dbt v2 doesn't export Ossie natively yet, so the bridge runs the official Apache Ossie dbt converter in an isolated uv environment.

```bash
dbt parse
uv run scripts/ossie_bridge.py
# [warning] CUMULATIVE_SEMANTICS_LOSS: cumulative_members
# [warning] CUMULATIVE_SEMANTICS_LOSS: invoiced_amount_mtd
# [warning] CUMULATIVE_SEMANTICS_LOSS: invoiced_amount_trailing_28d
# [warning] CONVERSION_METRIC_DROPPED: new_member_lesson_conversion
# target/semantic_manifest.json -> target/ossie_document.yaml
```

Open `target/ossie_document.yaml`. All 5 datasets are there, plus the 3 relationships MetricFlow inferred from the entities (lessons → coaches, lessons → members, invoices → members).

**The honest part.** Ossie is a lowest common denominator today, and this is where MetricFlow still earns its keep:

| dbt metric | Ossie expression | Lost |
|---|---|---|
| `cumulative_members` | `COUNT(DISTINCT members.member_id)` | The running window (warned) |
| `new_members_yoy_change` | `COUNT(DISTINCT ...) - COUNT(DISTINCT ...)` | The 1-year offset. The expression always evaluates to 0, and **no warning is raised** |
| `active_members` | `COUNT(DISTINCT CASE WHEN member__is_club_member ...)` | The filter refers to a MetricFlow dimension name, not a column |

`new_member_lesson_conversion` is dropped entirely: Ossie has no funnel metric type. The same happens to private metrics.

---

## Gotchas found while building this

- **The legacy semantic YAML is ignored on dbt v2**, apart from a deprecation warning. Before this change the manifest contained zero semantic models. `dbt-autofix deprecations --semantic-layer` does the migration, but it drops labels and duplicates descriptions, so review its output.
- **No cross-project refs in the latest spec yet.** Every semantic model needs a local model, so `fct_coaching_lessons`, `fct_member_invoices` and `dim_coaches_anonymized` are thin wrappers over `ztc_core` (coach names and contact details are dropped).
- **Fusion rejects `expr` on a column-level entity**, even though the docs list it. The `member_id` type mismatch (text in `ztc_core` facts, number in members) is fixed in the wrapper SQL with `TRY_TO_NUMBER`, and the raw id is kept as `source_member_id`.
- **Conversion metrics reject a `count` input metric** on Fusion ("agg type SUM"). `lessons_booked` uses `count_distinct` on the primary key instead, which gives the same numbers.
- **Counts on dimension tables slice by their time dimension.** `total_members` and `active_coaches` by `metric_time` count joiners and hires per period, not headcount.
- **`agg_time_dimension` goes at the model level on Fusion.** The docs show it under `semantic_model:`, but Fusion 2.0.6 rejects that.
- **Ossie has no aggregation time dimension**, so `agg_time_dimension` is lost on export. The converter writes the `0.2.0.dev0` document shape.
- **The converter isn't on PyPI**, despite its README. The bridge installs it from git, pinned to a commit.
