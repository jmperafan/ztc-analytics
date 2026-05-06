{% macro set_job_param(success=false) %}

{{ create_watermark_schema() }}

  {%- set hwm_relation = adapter.get_relation(
      database=var('watermark_database', target.database),
      schema=generate_schema_name(custom_schema_name=var('watermark_schema', 'public'), node_obj=node),
      identifier=var('watermark_table', 'dbt_high_watermark')) is not none -%}
{% if not hwm_relation %}
{{ create_hwm_table() }}
{% endif %}

{% if execute %}
    {% set upstream_nodes = graph.nodes[model.unique_id].depends_on.nodes %}
  {% else %}
{% set upstream_nodes = [] %}
{% endif %}

{% set hwm_source_model = model.config.meta.get('hwm_source_model', none) %}

{% for upstream_node in upstream_nodes %}

{% set model_node = graph.nodes.get(upstream_node) %}
{% set source_node = graph.sources.get(upstream_node) %}
{% set ns = namespace(
    process=false, hwm_field='',
    upstream_node_db='', upstream_node_schema='', upstream_node_alias=''
) %}

    {% if model_node and model_node.resource_type == 'model'
          and (hwm_source_model is none or model_node.name == hwm_source_model) %}

      {% set ns.process = true %}
      {% set ns.hwm_field = model.config.meta.get('hwm_field', model.config.get('hwm_field', 'updated_at')) %}
      {% set ns.upstream_node_db = model_node.database %}
      {% set ns.upstream_node_schema = model_node.schema %}
      {% set ns.upstream_node_alias = model_node.alias %}

    {% elif source_node and source_node.resource_type == 'source' %}

{% set loaded_at_field = source_node.loaded_at_field %}
{% set ns.process = true %}

{% if model.config.get('use_loaded_at', false) and loaded_at_field %}
        {% set ns.hwm_field = loaded_at_field %}
      {% else %}
        {% set ns.hwm_field = model.config.meta.get('hwm_field', model.config.get('hwm_field', 'updated_at')) %}
      {% endif %}

      {% set ns.upstream_node_db = source_node.database %}
      {% set ns.upstream_node_schema = source_node.schema %}
      {% set ns.upstream_node_alias = source_node.identifier %}
    {% endif %}

    {% if ns.process %}
      {% set job_param_sql %}
        insert into {{ get_hwm_fqn() }} (
          target_name,
          source_name,
          invocation_id,
          invocation_time,
          complete,
          hwm_timestamp
        )
        select
          '{{ model.unique_id }}' as target_name,
          '{{ ns.upstream_node_db }}.{{ ns.upstream_node_schema }}.{{ ns.upstream_node_alias }}' as source_name,
          '{{ invocation_id }}' as invocation_id,
          current_timestamp as invocation_time,
          {{ success }} as complete,
          max({{ ns.hwm_field }}) as hwm_timestamp
        from {{ ns.upstream_node_db }}.{{ ns.upstream_node_schema }}.{{ ns.upstream_node_alias }}
      {% endset %}
      {% do run_query(job_param_sql) %}
    {% endif %}
  {% endfor %}

{% endmacro %}
