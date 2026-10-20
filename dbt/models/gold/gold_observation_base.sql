{{ config(
    materialized='table',
    schema='gold',
    alias='observation_base'
) }}

-- Grain: one row per observation submission (submission_id).
-- Shared dimensional backbone for every Impact Metrics gold mart.
--
-- teacher_name is a structured code, e.g. "T14-BS-Rajni"
-- (teacher code T14 + school code BS + short name) - teacher_uid is
-- extracted from the leading "T<digits>-<SCHOOLCODE>" pattern, which is
-- already unique across schools since it embeds the school code.
--
-- classroom_name can hold MULTIPLE space-separated classroom codes on one
-- submission (e.g. "CL16-BS-2022A CL17-BS-2021A" on co_teach rows), so it
-- is kept raw here - see gold_observation_classroom_bridge for the
-- exploded one-row-per-classroom-code version. Confirmed: a single
-- classroom code is globally unique on its own (already embeds the
-- school code), no need to compound it with school_name.

WITH obs AS (

    SELECT
        submission_id,
        submission_uuid,
        observation_date,
        submission_time,
        school_name,
        classroom_name,
        teacher_name,
        observer_name,
        teaching_type,
        subject_observed,
        program_name,
        students_present,
        student_sampling,
        student_learning,
        submission_status
    FROM {{ ref('fct_observations') }}
        WHERE observation_date IS NOT NULL
            AND NULLIF(TRIM(teacher_name), '') IS NOT NULL

)

SELECT
    submission_id,
    submission_uuid,
    observation_date,
    submission_time,
    {{ academic_cycle_label('observation_date') }} AS academic_cycle,
    {{ academic_quarter_label('observation_date') }} AS academic_quarter,
    EXTRACT(YEAR FROM observation_date) AS calendar_year,

    school_name,
    NULLIF(TRIM(school_name), '') AS school_key,

    classroom_name AS classroom_name_raw,
    teacher_name AS teacher_name_raw,
    observer_name,

    NULLIF(TRIM(teacher_name), '') AS teacher_uid,

    teaching_type,
    LOWER(TRIM(subject_observed)) AS subject_observed,
    program_name,
    students_present,
    student_sampling,
    student_learning,
    submission_status
FROM obs
