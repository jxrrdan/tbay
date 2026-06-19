{# ============================================================================
   Cross-adapter SQL utilities.

   Every function here has a default__ implementation (DuckDB) and a
   bigquery__ override. dbt's adapter.dispatch() picks the right one at
   compile time based on the active profile target.

   Usage in models:
       {{ week_start('created_at') }}
       {{ datediff_hours('created_at', 'resolved_at') }}
       CROSS JOIN {{ unnest_split('tags_raw', ',', 'tag_raw') }}
   ============================================================================ #}


{# ---------------------------------------------------------------------------
   week_start — truncate any date/timestamp to the Monday of its ISO week.
   Always returns DATE so types stay consistent across a UNION.
   --------------------------------------------------------------------------- #}
{% macro week_start(col) %}
  {{ return(adapter.dispatch('week_start', 'titanbay_is')(col)) }}
{% endmacro %}

{% macro default__week_start(col) %}
  cast(date_trunc('week', {{ col }}) as date)
{% endmacro %}

{% macro bigquery__week_start(col) %}
  date_trunc(cast({{ col }} as date), week(monday))
{% endmacro %}


{# ---------------------------------------------------------------------------
   month_start — truncate any date/timestamp to the first of its month.
   Always returns DATE.
   --------------------------------------------------------------------------- #}
{% macro month_start(col) %}
  {{ return(adapter.dispatch('month_start', 'titanbay_is')(col)) }}
{% endmacro %}

{% macro default__month_start(col) %}
  cast(date_trunc('month', {{ col }}) as date)
{% endmacro %}

{% macro bigquery__month_start(col) %}
  date_trunc(cast({{ col }} as date), month)
{% endmacro %}


{# ---------------------------------------------------------------------------
   datediff_hours — decimal hours between two timestamps.
   --------------------------------------------------------------------------- #}
{% macro datediff_hours(start_ts, end_ts) %}
  {{ return(adapter.dispatch('datediff_hours', 'titanbay_is')(start_ts, end_ts)) }}
{% endmacro %}

{% macro default__datediff_hours(start_ts, end_ts) %}
  (epoch({{ end_ts }}) - epoch({{ start_ts }})) / 3600.0
{% endmacro %}

{% macro bigquery__datediff_hours(start_ts, end_ts) %}
  timestamp_diff({{ end_ts }}, {{ start_ts }}, minute) / 60.0
{% endmacro %}


{# ---------------------------------------------------------------------------
   date_add_days / date_sub_days — date arithmetic with a literal integer.
   --------------------------------------------------------------------------- #}
{% macro date_add_days(date_col, n_days) %}
  {{ return(adapter.dispatch('date_add_days', 'titanbay_is')(date_col, n_days)) }}
{% endmacro %}

{% macro default__date_add_days(date_col, n_days) %}
  {{ date_col }} + interval '{{ n_days }}' day
{% endmacro %}

{% macro bigquery__date_add_days(date_col, n_days) %}
  date_add({{ date_col }}, interval {{ n_days }} day)
{% endmacro %}


{% macro date_sub_days(date_col, n_days) %}
  {{ return(adapter.dispatch('date_sub_days', 'titanbay_is')(date_col, n_days)) }}
{% endmacro %}

{% macro default__date_sub_days(date_col, n_days) %}
  {{ date_col }} - interval '{{ n_days }}' day
{% endmacro %}

{% macro bigquery__date_sub_days(date_col, n_days) %}
  date_sub({{ date_col }}, interval {{ n_days }} day)
{% endmacro %}


{# ---------------------------------------------------------------------------
   approx_median — median of a numeric column, ignoring NULLs.
   BigQuery has no native median() aggregate; APPROX_QUANTILES is the
   idiomatic substitute and is accurate enough for resolution-time reporting.
   --------------------------------------------------------------------------- #}
{% macro approx_median(col) %}
  {{ return(adapter.dispatch('approx_median', 'titanbay_is')(col)) }}
{% endmacro %}

{% macro default__approx_median(col) %}
  median({{ col }})
{% endmacro %}

{% macro bigquery__approx_median(col) %}
  approx_quantiles({{ col }}, 2)[offset(1)]
{% endmacro %}


{# ---------------------------------------------------------------------------
   cast_int64 — cast to a 64-bit integer.
   DuckDB: bigint   BigQuery: INT64
   --------------------------------------------------------------------------- #}
{% macro cast_int64(col) %}
  {{ return(adapter.dispatch('cast_int64', 'titanbay_is')(col)) }}
{% endmacro %}

{% macro default__cast_int64(col) %}
  cast({{ col }} as bigint)
{% endmacro %}

{% macro bigquery__cast_int64(col) %}
  cast({{ col }} as int64)
{% endmacro %}


{# ---------------------------------------------------------------------------
   unnest_split — split a delimited string and return one row per element.
   Intended for use as:
       CROSS JOIN {{ unnest_split('tags_raw', ',', 'tag_raw') }}

   DuckDB:    UNNEST(string_split(col, ',')) AS t(alias)
   BigQuery:  UNNEST(SPLIT(col, ','))        AS alias

   Both handle NULL input by producing zero rows (no LATERAL keyword needed).
   --------------------------------------------------------------------------- #}
{% macro unnest_split(col, delim, alias) %}
  {{ return(adapter.dispatch('unnest_split', 'titanbay_is')(col, delim, alias)) }}
{% endmacro %}

{% macro default__unnest_split(col, delim, alias) %}
  unnest(string_split({{ col }}, '{{ delim }}')) as t({{ alias }})
{% endmacro %}

{% macro bigquery__unnest_split(col, delim, alias) %}
  unnest(split({{ col }}, '{{ delim }}')) as {{ alias }}
{% endmacro %}
