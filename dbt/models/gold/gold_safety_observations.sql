{{ config(
    materialized='table',
    schema='gold',
    alias='safety_observations'
) }}

-- Grain: one row per observation submission.
-- safety_level_raw is text like "level_3"; safety_level_numeric pulls
-- the digit out via regex.
-- Feeds gold_teacher_safety_summary (IM01 KPI + trend).

SELECT
    b.submission_id,
    b.observation_date,
    b.submission_time,
    b.academic_cycle,
    b.academic_quarter,
    b.calendar_year,
    b.school_name,
    b.school_key,
    b.teacher_uid,
    b.teaching_type,
    b.subject_observed,
    b.program_name,

    s.safety_level AS safety_level_raw,
    SAFE_CAST(REGEXP_EXTRACT(s.safety_level, r'(\d+)') AS NUMERIC) AS safety_level_numeric
FROM {{ ref('gold_observation_base') }} AS b
INNER JOIN {{ ref('br_safety') }} AS s
    ON b.submission_id = s.submission_id
WHERE s.safety_level IS NOT NULL
