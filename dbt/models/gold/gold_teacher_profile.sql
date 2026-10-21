{{ config(
    materialized='table',
    schema='gold',
    alias='tl_teaching_inputs'
) }}

-- Dashboard mart for Teacher profile -> "Coaching inputs - from logbook".
--
-- Grain: one row per teacher-log submission x coaching touchpoint.
--   * a log with 3 touchpoints  -> 3 rows
--   * a log with no touchpoints -> 1 row, touchpoint columns NULL
-- The log (tl_fct_teacher_log) is the spine, so a log that only introduced
-- TLMs still counts toward the TLM tile.
--
-- Every tile on the section is a plain aggregate of this ONE table, so the
-- teacher / academic-year / quarter filters apply to all of them together:
--
--   Total touchpoints this cycle   SUM(touchpoint_count)
--   Avg. effectiveness rating      AVG(rating)            -- shown as x/4
--   TLMs introduced (sessions)     SUM(tlm_session_count)
--   Touchpoints by type            SUM(touchpoint_count) by touchpoint
--   Touchpoints by subject focus   SUM(touchpoint_count) by subject_label
--
-- The two additive columns exist because of the repeated rows:
--   touchpoint_count  = 1 on a real touchpoint row, 0 on a "no touchpoints" row
--   tlm_session_count = 1 on ONE row per log (the first) when that log
--                       introduced TLMs, else 0 - so a log with 3 touchpoints
--                       is counted once, not three times. A plain COUNT of
--                       rows, or a SUM over a per-log flag, would over-count.
-- AVG(rating) is a true average over touchpoints: rating is NULL on a "no
-- touchpoints" row, and AVG ignores NULLs.
--
-- Logs without an observation_date are excluded: no academic cycle or
-- quarter can be assigned, so they could never match a dashboard filter.
-- academic_cycle / academic_quarter use the same macros as
-- gold_observation_base (macros/academic_calendar.sql).
--
-- teacher_uid is the full teacher_name code (e.g. "T3-GL-Reeta"), built the
-- same way as gold_observation_base so this mart joins to the observation
-- marts and to the dashboard's teacher filter. If that model is changed to
-- extract only the code prefix, change this line with it.

WITH log AS (

    SELECT
        submission_id,
        observation_date,
        coach_name,
        school_name,
        classroom_name,
        teacher_name,
        classroom_type,
        tlm_introduced,
        tlm_types
    FROM {{ ref('tl_fct_teacher_log') }}
    WHERE observation_date IS NOT NULL

),

touchpoints AS (

    SELECT
        submission_id,
        touchpoint,
        other_touchpoint_type,
        subject,
        objective,
        rating,
        evidence
    FROM {{ ref('tl_fct_touchpoints') }}

),

joined AS (

    SELECT
        l.submission_id,
        l.observation_date,
        l.coach_name,
        l.school_name,
        l.classroom_name,
        l.teacher_name,
        l.classroom_type,
        l.tlm_introduced,
        l.tlm_types,
        t.touchpoint,
        t.other_touchpoint_type,
        t.subject,
        t.objective,
        t.rating,
        t.evidence,
        -- Marks one row per log (touchpoint is unique within a log), used
        -- to count each TLM session exactly once.
        ROW_NUMBER() OVER (
            PARTITION BY l.submission_id
            ORDER BY t.touchpoint
        ) AS row_in_log
    FROM log AS l
    LEFT JOIN touchpoints AS t
        ON l.submission_id = t.submission_id

)

SELECT
    submission_id,

    observation_date,
    {{ academic_cycle_label('observation_date') }} AS academic_cycle,
    {{ academic_quarter_label('observation_date') }} AS academic_quarter,

    coach_name,
    school_name,
    classroom_name,
    classroom_name AS classroom_uid,
    teacher_name,
    teacher_name AS teacher_uid,
    classroom_type,

    touchpoint,
    other_touchpoint_type,
    subject,
    -- Display label for the subject-focus chart. Underscored codes become
    -- words (general_pedagogy -> General Pedagogy); EVS is an acronym, so it
    -- is kept upper-case. `subject` above stays the raw value.
    CASE
        WHEN subject IS NULL THEN NULL
        WHEN LOWER(subject) = 'evs' THEN 'EVS'
        ELSE INITCAP(REPLACE(subject, '_', ' '))
    END AS subject_label,
    objective,
    rating,
    evidence,

    CASE tlm_introduced
        WHEN 'yes' THEN TRUE
        WHEN 'no' THEN FALSE
    END AS tlm_introduced,
    tlm_types,

    IF(touchpoint IS NULL, 0, 1) AS touchpoint_count,
    IF(row_in_log = 1 AND tlm_introduced = 'yes', 1, 0) AS tlm_session_count
FROM joined
