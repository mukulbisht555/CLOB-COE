{{ config(
    materialized='table',
    schema='gold',
    alias='classroom_participation'
) }}

-- Grain: one row per observation submission x classroom code.
-- Feeds: IM05/IM06 ("Classrooms with active student engagement").
--
-- STILL BLOCKED: I haven't seen sample values for student_sampling /
-- student_learning yet, so no flag is precomputed - raw values pass
-- through as-is. Once you share a preview with real values I can add
-- the threshold logic here (mirrors the safety pattern above).

SELECT
    cb.submission_id,
    cb.observation_date,
    cb.academic_cycle,
    cb.academic_quarter,
    cb.calendar_year,
    cb.school_name,
    cb.school_key,
    cb.classroom_uid,
    cb.teacher_uid,
    cb.teaching_type,
    cb.program_name,
    b.students_present,
    b.student_sampling,
    b.student_learning
FROM {{ ref('gold_observation_classroom_bridge') }} AS cb
INNER JOIN {{ ref('gold_observation_base') }} AS b
    ON cb.submission_id = b.submission_id
