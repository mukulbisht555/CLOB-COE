
{{ config(
    materialized='table',
    schema='silver',
    alias='tl_fct_teacher_log'
) }}

WITH source_data AS (

    SELECT *
    FROM {{ ref('tl_br_observations') }}

)

SELECT
    submission_id,

    NULLIF(TRIM(coach_name), '') AS coach_name,

    COALESCE(
        SAFE_CAST(SUBSTR(TRIM(submission_date), 1, 10) AS DATE),
        SAFE_CAST(
            SAFE_CAST(submission_date AS TIMESTAMP) AS DATE
        )
    ) AS observation_date,

    NULLIF(TRIM(school_name), '') AS school_name,
    NULLIF(TRIM(classroom_name), '') AS classroom_name,
    NULLIF(TRIM(teacher_name), '') AS teacher_name,
    NULLIF(TRIM(classroom_type), '') AS classroom_type,

    LOWER(NULLIF(TRIM(tlm_introduced), '')) AS tlm_introduced,
    NULLIF(TRIM(tlm_types), '') AS tlm_types,

    NULLIF(TRIM(coaching_touchpoints), '') AS coaching_touchpoints

FROM source_data
