{#
    new_submissions_only(column)

    Row filter used by every incremental bronze/silver model, so the
    "only process what's new" rule lives in ONE place.

    - First run (the table doesn't exist yet) or `--full-refresh`:
      returns TRUE, so the model builds from ALL data.
    - Any later run: only rows whose submission_id is higher than the
      highest submission_id already in this model's table.

    This mirrors the Python loader's watermark. It is safe because
    raw.submissions is append-only and Kobo `_id` values only increase.

    Usage:  WHERE ... AND {{ new_submissions_only('src.submission_id') }}
#}

{% macro new_submissions_only(column='submission_id') -%}
    {%- if is_incremental() -%}
        {{ column }} > (SELECT COALESCE(MAX(submission_id), 0) FROM {{ this }})
    {%- else -%}
        TRUE
    {%- endif -%}
{%- endmacro %}
