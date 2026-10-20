{{ config(
    materialized='table',
    schema='gold',
    alias='cs05_teacher_classroom_safety_shift'
) }}

-- Grain: one row per teacher_uid x school_name x classroom_uid
--        x academic_cycle.
-- Feeds CS05 ("Teacher-wise safety - latest vs baseline" table: Teacher,
-- School, Grade, Safety-Baseline, Safety-Latest, Shift).
--
--   teacher_uid            - the teacher
--   school_name            - school code of the observations
--   classroom_uid          - the classroom. Confirmed: the classroom IS the
--                            grade, so this column is shown as "Grade";
--                            no separate grade field or lookup exists.
--   academic_cycle          - e.g. "2025-26" (Apr-Mar year)
--   baseline_safety_level   - safety level (1-4) of this teacher's very
--                            FIRST observation in this classroom, across
--                            ALL cycles (a constant per teacher x
--                            classroom, same in every cycle row)
--   latest_safety_level     - safety level (1-4) of this teacher's LATEST
--                            observation in this classroom within the
--                            academic_cycle on the row
--   level_shift             - latest_safety_level - baseline_safety_level
--                            (+2 = up two levels, 0 = no change,
--                            negative = went down)
--
-- Confirmed rules:
--   * Baseline = the very first observation (per the wireframe sheet).
--   * Filter supported: academic_cycle only.
--
-- Read this before using the table:
--   * Baseline and latest are compared inside the same classroom, so a
--     teacher who moves between grades is not compared across grades.
--   * A teacher observed only once in a classroom has baseline = latest,
--     so level_shift is 0 for that row.
--   * Because each row is one teacher x classroom x cycle, the cycle
--     control in Looker Studio should be single-select; with two cycles
--     selected the table would show one row per cycle.
--   * Co-teach observations name two classrooms; each classroom is
--     treated separately with that observation's level.
--   * The ">= 3" view (classrooms at level 3 or 4) is applied in Looker
--     Studio with a filter on latest_safety_level, not baked in here.
--
-- Ties on the same observation_date fall back to submission_id.
-- Does not touch gold_observation_classroom_bridge or
-- gold_safety_observations - both read as-is.

WITH classroom_observations AS (

    SELECT DISTINCT
        so.teacher_uid,
        cb.school_name,
        cb.classroom_uid,
        cb.academic_cycle,
        so.submission_id,
        so.observation_date,
        so.safety_level_numeric AS safety_level
    FROM {{ ref('gold_observation_classroom_bridge') }} AS cb
    INNER JOIN {{ ref('gold_safety_observations') }} AS so
        ON cb.submission_id = so.submission_id
    WHERE so.safety_level_numeric IS NOT NULL
      AND cb.school_name IS NOT NULL

),

-- ---------------------------------------------------------------
-- BASELINE: first observation EVER per teacher x school x classroom
-- (spans all cycles on purpose)
-- ---------------------------------------------------------------

ranked_first_ever AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, school_name, classroom_uid
            ORDER BY observation_date ASC, submission_id ASC
        ) AS rn
    FROM classroom_observations

),

first_ever AS (

    SELECT
        teacher_uid,
        school_name,
        classroom_uid,
        safety_level AS baseline_safety_level
    FROM ranked_first_ever
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- LATEST: latest observation per teacher x school x classroom x cycle
-- ---------------------------------------------------------------

ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, school_name, classroom_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM classroom_observations

),

latest_per_cycle AS (

    SELECT
        teacher_uid,
        school_name,
        classroom_uid,
        academic_cycle,
        safety_level AS latest_safety_level
    FROM ranked_latest_per_cycle
    WHERE rn = 1

)

SELECT
    l.teacher_uid,
    l.school_name,
    l.classroom_uid,
    l.academic_cycle,
    CAST(f.baseline_safety_level AS INT64) AS baseline_safety_level,
    CAST(l.latest_safety_level AS INT64) AS latest_safety_level,
    CAST(l.latest_safety_level - f.baseline_safety_level AS INT64) AS level_shift
FROM latest_per_cycle AS l
INNER JOIN first_ever AS f
    ON l.teacher_uid = f.teacher_uid
    AND l.school_name = f.school_name
    AND l.classroom_uid = f.classroom_uid