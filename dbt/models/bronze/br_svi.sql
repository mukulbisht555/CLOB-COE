{{ config(materialized='table', schema='bronze', alias='br_svi') }}
{# SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."svi_block/svi_co_indicators"') AS svi_co_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_ct_indicators"') AS svi_ct_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_cr_indicators"') AS svi_cr_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_teacher_actions"') AS svi_teacher_actions_raw
FROM {{ source('raw', 'submissions') }}
WHERE JSON_VALUE(data, '$._id') IS NOT NULL #}


{# {{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='submission_id',
    on_schema_change='append_new_columns',
    schema='bronze',
    alias='br_svi'
) }} #}
SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."svi_block/svi_co_indicators"') AS svi_co_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_ct_indicators"') AS svi_ct_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_cr_indicators"') AS svi_cr_indicators_raw,
  JSON_VALUE(data, '$."svi_block/svi_teacher_actions"') AS svi_teacher_actions_raw
FROM {{ source('raw', 'observation_submissions') }} AS src
WHERE JSON_VALUE(data, '$._id') IS NOT NULL
  {# AND {{ new_submissions_only('src.submission_id') }} #}