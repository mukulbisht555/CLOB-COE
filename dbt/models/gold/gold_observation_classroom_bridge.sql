{{ config(
    materialized='table',
    schema='gold',
    alias='observation_classroom_bridge'
) }}

-- Grain: one row per observation submission x classroom code.
-- classroom_name_raw can contain more than one space-separated classroom
-- code on a single submission (seen on teaching_type = 'co_teach' rows),
-- so it has to be split before it's used as a grouping key for any
-- classroom-grain metric (21C skills %, participation %).

SELECT
    submission_id,
    academic_cycle,
    academic_quarter,
    calendar_year,
    observation_date,
    school_name,
    school_key,
    teacher_uid,
    teaching_type,
    subject_observed,
    program_name,
    TRIM(classroom_code) AS classroom_uid
FROM {{ ref('gold_observation_base') }},
UNNEST(
    SPLIT(
        REGEXP_REPLACE(COALESCE(classroom_name_raw, ''), r'\s+', ' '),
        ' '
    )
) AS classroom_code
WHERE TRIM(classroom_code) != ''
