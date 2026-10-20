{{ config(
    materialized='table',
    schema='gold',
    alias='cs03_safety_action_frequency'
) }}

-- Grain: one row per academic_cycle x academic_quarter x safety_level
--        x safety_action (TA code).
-- Feeds CS03 ("Safety practices ranked by frequency of observation" -
-- horizontal bar, one bar per teacher action TA1-TA14, plus an optional
-- split of each bar by the observation's safety level L1-L4).
--
--   academic_cycle     - e.g. "2025-26" (Apr-Mar year)
--   academic_quarter    - Q1-Q4
--   safety_level        - 1-4, digit extracted from the "level_N" code of
--                         the observation the action was recorded in
--   safety_action       - TA code exactly as recorded (TA1 ... TA14).
--                         Codes are kept as-is on purpose: the code ->
--                         label sheet is blended in Looker Studio, so the
--                         values here must match that sheet's code column.
--   observation_count   - number of distinct observations in which this
--                         action was recorded, at this level, in this
--                         cycle + quarter
--
-- Confirmed rules:
--   * ALL observations count (not latest-only) - same as CS01.
--   * Counted per observation (submission_id), NOT through the classroom
--     bridge, so a co-teach observation that names two classrooms still
--     counts once per action.
--   * 'none' rows are excluded - they mean "no action recorded", not a
--     practice.
--   * Filters supported: academic_cycle + academic_quarter only (no
--     school or program columns, per the CS03 decision).
--   * Observations without a safety level are excluded, so CS01 and CS03
--     are always built on the same set of observations.
--
-- Ranking (highest to lowest) is done by the chart's sort in Looker
-- Studio. The plain ranking is SUM(observation_count) across levels; the
-- optional breakdown uses safety_level as the breakdown dimension.
--
-- Layer 2 has no safety-action fact, so this model reads the silver
-- fct_safety_actions and joins gold_observation_base (Layer 1) on
-- submission_id for the cycle and quarter. Nothing in Layers 1-2 is
-- modified.

WITH actions AS (

    SELECT
        a.submission_id,
        b.academic_cycle,
        b.academic_quarter,
        SAFE_CAST(REGEXP_EXTRACT(a.safety_level, r'(\d+)') AS INT64) AS safety_level,
        TRIM(a.safety_action) AS safety_action
    FROM {{ ref('fct_safety_actions') }} AS a
    INNER JOIN {{ ref('gold_observation_base') }} AS b
        ON a.submission_id = b.submission_id
    WHERE a.safety_action IS NOT NULL
      AND LOWER(TRIM(a.safety_action)) != 'none'

)

SELECT
    academic_cycle,
    academic_quarter,
    safety_level,
    safety_action,
    COUNT(DISTINCT submission_id) AS observation_count
FROM actions
WHERE safety_level IS NOT NULL
GROUP BY
    academic_cycle,
    academic_quarter,
    safety_level,
    safety_action