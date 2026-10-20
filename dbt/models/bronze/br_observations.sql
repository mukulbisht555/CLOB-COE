{{ config(materialized='table', schema='bronze', alias='br_observations') }}
{# SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$._uuid') AS submission_uuid,
  JSON_VALUE(data, '$."formhub/uuid"') AS form_uuid,
  JSON_VALUE(data, '$."meta/instanceID"') AS instance_id,
  JSON_VALUE(data, '$."**version**"') AS form_version,
  SAFE_CAST(JSON_VALUE(data, '$.start') AS TIMESTAMP) AS start_timestamp,
  SAFE_CAST(JSON_VALUE(data, '$.end') AS TIMESTAMP) AS end_timestamp,
  SAFE_CAST(JSON_VALUE(data, '$."_submission_time"') AS TIMESTAMP) AS submission_time,
  SAFE_CAST(JSON_VALUE(data, '$.observation_date') AS DATE) AS observation_date,
  SAFE_CAST(JSON_VALUE(data, '$.observation_time') AS TIME) AS observation_time,
  JSON_VALUE(data, '$.observation_duration') AS observation_duration,
  SAFE_CAST(JSON_VALUE(data, '$.std_present') AS INT64) AS students_present,
  JSON_VALUE(data, '$.program_name') AS program_name,
  JSON_VALUE(data, '$."intro_block/observer_name"') AS observer_name,
  JSON_VALUE(data, '$."intro_block/school_name"') AS school_name,
  JSON_VALUE(data, '$."intro_block/classroom_name"') AS classroom_name,
  JSON_VALUE(data, '$."intro_block/teacher_name"') AS teacher_name,
  JSON_VALUE(data, '$."intro_block/teaching_type"') AS teaching_type,
  JSON_VALUE(data, '$."fl_block/lesson_objective"') AS lesson_objective,
  SAFE_CAST(JSON_VALUE(data, '$."fl_block/student_sampling"') AS INT64) AS student_sampling,
  SAFE_CAST(JSON_VALUE(data, '$."fl_block/student_learning"') AS INT64) AS student_learning,
  JSON_VALUE(data, '$."fl_block/subject_observed"') AS subject_observed,
  JSON_VALUE(data, '$."_status"') AS submission_status,
  JSON_VALUE(data, '$."_submitted_by"') AS submitted_by,
  JSON_VALUE(data, '$."_xform_id_string"') AS xform_id,
  data AS raw_data
FROM {{ source('raw', 'submissions') }}
WHERE JSON_VALUE(data, '$._id') IS NOT NULL #}


{# {{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='submission_id',
    on_schema_change='append_new_columns',
    schema='bronze',
    alias='br_observations'
) }} #}
SELECT
  SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,
  JSON_VALUE(data, '$._uuid') AS submission_uuid,
  JSON_VALUE(data, '$."formhub/uuid"') AS form_uuid,
  JSON_VALUE(data, '$."meta/instanceID"') AS instance_id,
  JSON_VALUE(data, '$."**version**"') AS form_version,
  SAFE_CAST(JSON_VALUE(data, '$.start') AS TIMESTAMP) AS start_timestamp,
  SAFE_CAST(JSON_VALUE(data, '$.end') AS TIMESTAMP) AS end_timestamp,
  SAFE_CAST(JSON_VALUE(data, '$."_submission_time"') AS TIMESTAMP) AS submission_time,
  SAFE_CAST(JSON_VALUE(data, '$.observation_date') AS DATE) AS observation_date,
  SAFE_CAST(JSON_VALUE(data, '$.observation_time') AS TIME) AS observation_time,
  JSON_VALUE(data, '$.observation_duration') AS observation_duration,
  SAFE_CAST(JSON_VALUE(data, '$.std_present') AS INT64) AS students_present,
  JSON_VALUE(data, '$.program_name') AS program_name,
  JSON_VALUE(data, '$."intro_block/observer_name"') AS observer_name,
  JSON_VALUE(data, '$."intro_block/school_name"') AS school_name,
  JSON_VALUE(data, '$."intro_block/classroom_name"') AS classroom_name,
  JSON_VALUE(data, '$."intro_block/teacher_name"') AS teacher_name,
  JSON_VALUE(data, '$."intro_block/teaching_type"') AS teaching_type,
  JSON_VALUE(data, '$."fl_block/lesson_objective"') AS lesson_objective,
  SAFE_CAST(JSON_VALUE(data, '$."fl_block/student_sampling"') AS INT64) AS student_sampling,
  SAFE_CAST(JSON_VALUE(data, '$."fl_block/student_learning"') AS INT64) AS student_learning,
  JSON_VALUE(data, '$."fl_block/subject_observed"') AS subject_observed,
  JSON_VALUE(data, '$."_status"') AS submission_status,
  JSON_VALUE(data, '$."_submitted_by"') AS submitted_by,
  JSON_VALUE(data, '$."_xform_id_string"') AS xform_id,
  data AS raw_data
FROM {{ source('raw', 'observation_submissions') }} AS src
WHERE JSON_VALUE(data, '$._id') IS NOT NULL
  {# AND {{ new_submissions_only('src.submission_id') }} #}
