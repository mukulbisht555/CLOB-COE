 {{ config(materialized='table', schema='bronze', alias='br_safety') }}
{# SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."safety_block/safety_level"') AS safety_level,
  JSON_VALUE(data, '$."safety_block/safety_action"') AS safety_actions_raw
FROM {{ source('raw', 'submissions') }}
WHERE JSON_VALUE(data, '$._id') IS NOT NULL #}


{# {{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='submission_id',
    on_schema_change='append_new_columns',
    schema='bronze',
    alias='br_safety'
) }} #}
SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."safety_block/safety_level"') AS safety_level,
  JSON_VALUE(data, '$."safety_block/safety_action"') AS safety_actions_raw
FROM {{ source('raw', 'observation_submissions') }} AS src
WHERE JSON_VALUE(data, '$._id') IS NOT NULL
  {# AND {{ new_submissions_only('src.submission_id') }} #}
