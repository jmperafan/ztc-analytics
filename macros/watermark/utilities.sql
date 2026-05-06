{% macro get_hwm_fqn(schema=false) %}
    {%- if schema -%}
{{ var('watermark_database', target.database) }}.{{ generate_schema_name(custom_schema_name=var('watermark_schema', 'public'), node_obj=node) }}
  {%- else -%}
        {%- set _db = var('watermark_database', target.database) -%}
        {%- set _schema = generate_schema_name(custom_schema_name=var('watermark_schema', 'public'), node_obj=node) -%}
        {%- set _tbl = var('watermark_table', 'dbt_high_watermark') -%}
        {{ _db }}.{{ _schema }}.{{ _tbl }}
    {%- endif -%}
{% endmacro %}

{% macro create_hwm_table() %}
    {% set create_hwm_table %}
    create table if not exists {{ get_hwm_fqn() }} (
        target_name     text not null,
        source_name     text not null,
        invocation_id   text not null,
        invocation_time timestamp_ntz(9) not null,
        complete        boolean,
        hwm_timestamp   timestamp_ntz(9) not null
    )
  {% endset %}
    {% do run_query(create_hwm_table) %}
{% endmacro %}

{% macro create_watermark_schema() %}
    {% set create_watermark_schema %}
    create schema if not exists {{ get_hwm_fqn(schema=true) }}
    {% endset %}
    {% do run_query(create_watermark_schema) %}
{% endmacro %}

{% macro get_current_hwm(relation_obj) %}
    {{ return(adapter.dispatch('get_hwm', 'ztc_analytics')(true, relation_obj)) }}
{% endmacro %}

{% macro get_previous_hwm(relation_obj) %}
    {{ return(adapter.dispatch('get_hwm', 'ztc_analytics')(false, relation_obj)) }}
{% endmacro %}

{% macro snowflake__get_hwm(current, relation_obj) %}
    {%- if current -%}
    select max(hwm_timestamp)
    from {{ get_hwm_fqn() }}
    where target_name = '{{ model.unique_id }}'
      and source_name ilike '{{ relation_obj }}'
      and invocation_id = '{{ invocation_id }}'
      and complete = false
  {%- else -%}
    select coalesce(
      max(hwm_timestamp),
      '1900-01-01 00:00:00.000'
    )
    from {{ get_hwm_fqn() }}
    where target_name = '{{ model.unique_id }}'
      and source_name ilike '{{ relation_obj }}'
      and complete = true
    {%- endif -%}
{% endmacro %}
