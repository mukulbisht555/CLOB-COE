{{ config(materialized='table', schema='bronze', alias='br_language') }}
{# SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."fl_block/language_block/lang_practice"') AS language_practice_codes,
  JSON_VALUE(data, '$."fl_block/language_block/oral_sound"') AS oral_sound_codes,
  JSON_VALUE(data, '$."fl_block/language_block/letter_sound_recognition"') AS letter_sound_recognition_codes,
  JSON_VALUE(data, '$."fl_block/language_block/blending_segmenting"') AS blending_segmenting_codes,
  JSON_VALUE(data, '$."fl_block/language_block/rf"') AS reading_fluency_codes,
  JSON_VALUE(data, '$."fl_block/language_block/vocab_practice"') AS vocabulary_practice_codes
FROM {{ source('raw', 'submissions') }}
WHERE JSON_VALUE(data, '$._id') IS NOT NULL
  AND JSON_VALUE(data, '$."fl_block/subject_observed"') IN ('hindi', 'english')  #}


{# {{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='submission_id',
    on_schema_change='append_new_columns',
    schema='bronze',
    alias='br_language'
) }} #}
SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$."fl_block/language_block/lang_practice"') AS language_practice_codes,
  JSON_VALUE(data, '$."fl_block/language_block/oral_sound"') AS oral_sound_codes,
  JSON_VALUE(data, '$."fl_block/language_block/letter_sound_recognition"') AS letter_sound_recognition_codes,
  JSON_VALUE(data, '$."fl_block/language_block/blending_segmenting"') AS blending_segmenting_codes,
  JSON_VALUE(data, '$."fl_block/language_block/rf"') AS reading_fluency_codes,
  JSON_VALUE(data, '$."fl_block/language_block/vocab_practice"') AS vocabulary_practice_codes
FROM {{ source('raw', 'observation_submissions') }} AS src
WHERE JSON_VALUE(data, '$._id') IS NOT NULL
AND JSON_VALUE(data, '$."fl_block/subject_observed"') IN ('hindi', 'english')
  {# AND {{ new_submissions_only('src.submission_id') }} #}