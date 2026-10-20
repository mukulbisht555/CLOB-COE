{{ config(
    materialized='table',
    schema='silver',
    alias='fct_observations'
) }}

SELECT
    submission_id,
    submission_uuid,
    form_uuid,
    instance_id,
    form_version,
    start_timestamp,
    end_timestamp,
    submission_time,
    observation_date,
    observation_time,
    observation_duration,
    students_present,
    program_name,
    observer_name,
    school_name,
    classroom_name,
    teacher_name,
    teaching_type,
    lesson_objective,
    student_sampling,
    student_learning,
    subject_observed,
    submission_status,
    submitted_by,
    xform_id,
    raw_data
FROM {{ ref('br_observations') }}
WHERE submission_id IS NOT NULL
