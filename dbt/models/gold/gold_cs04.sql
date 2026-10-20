{{ config(
    materialized='table',
    schema='gold',
    alias='cs04_school_classroom_safety'
) }}

-- Grain: one row per school_name x academic_cycle x academic_quarter
--        x classroom_uid.
-- Feeds CS04 ("Classrooms at Safety Level 3 or 4 - by school" - column
-- chart, one bar per school, height = number of distinct classrooms).
--
--   school_name         - school code (GL, LD, KN, BS, KD, LL ...)
--   academic_cycle       - e.g. "2025-26" (Apr-Mar year)
--   academic_quarter      - Q1-Q4
--   classroom_uid         - the classroom (one code per row; co-teach
--                           observations naming two classrooms are split
--                           by gold_observation_classroom_bridge)
--   max_safety_level      - the HIGHEST safety level (1-4) observed in
--                           that classroom during that cycle + quarter
--
-- Confirmed rules:
--   * "Any observation" rule: a classroom counts as level 3 or 4 in a
--     period if ANY of its observations in that period was at level >= 3.
--     max_safety_level >= 3 is exactly that test.
--   * Filters supported: academic_cycle + academic_quarter only.
--
-- The >= 3 threshold is applied in Looker Studio, as in the IM marts:
--   COUNT_DISTINCT(CASE WHEN max_safety_level >= 3 THEN classroom_uid END)
--
-- Why this shape works for any filter combination: "any observation" is
-- monotone - if a classroom reached level 3+ in Q1 it also did in
-- "Q1 + Q2". So the same classroom appearing in several quarter rows is
-- collapsed correctly by COUNT_DISTINCT, whether one quarter or several
-- are selected. (A "latest observation" rule would NOT behave this way.)
--
-- Safety level is per observation, so each classroom named on an
-- observation gets that observation's level.
--
-- Does not touch gold_observation_classroom_bridge or
-- gold_safety_observations - both read as-is.

SELECT
    cb.school_name,
    cb.academic_cycle,
    cb.academic_quarter,
    cb.classroom_uid,
    CAST(MAX(so.safety_level_numeric) AS INT64) AS max_safety_level
FROM {{ ref('gold_observation_classroom_bridge') }} AS cb
INNER JOIN {{ ref('gold_safety_observations') }} AS so
    ON cb.submission_id = so.submission_id
WHERE so.safety_level_numeric IS NOT NULL
  AND cb.school_name IS NOT NULL
GROUP BY
    cb.school_name,
    cb.academic_cycle,
    cb.academic_quarter,
    cb.classroom_uid