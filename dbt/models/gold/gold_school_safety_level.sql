{{ config(
    materialized='table',
    schema='gold',
    alias='school_safety_distribution'
) }}

-- Grain: one row per school_name x academic_cycle x safety_level.
-- Feeds CS01 ("Safety level distribution by school" - 100% stacked bar,
-- one bar per school, segments = Level 1-4).
--
--   school_name        - school code (GL, LD, KN, BS, KD, LL ...)
--   academic_cycle      - e.g. "2025-26" (Apr-Mar year)
--   safety_level        - 1-4, digit extracted from the "level_N" code
--   observation_count   - number of observations at that level, for that
--                         school, in that cycle
--
-- Confirmed rules:
--   * ALL observations count (not just the latest per teacher/classroom) -
--     this is a distribution of observations, so each submission counts
--     once, whatever its level.
--   * Only academic_cycle is carried as a filter - no quarter or program
--     columns on purpose.
--
-- No percentage column: the "% of observations" is produced by the 100%
-- stacked bar in Looker Studio (dimension = school_name, breakdown
-- dimension = safety_level, metric = observation_count). A stored
-- percentage would give wrong numbers whenever more than one cycle is
-- selected at once.
--
-- gold_safety_observations is submission-grain (one row per submission),
-- so COUNT(*) here is a count of observations. Read as-is, not modified.

SELECT
    school_name,
    academic_cycle,
    CAST(safety_level_numeric AS INT64) AS safety_level,
    COUNT(DISTINCT submission_id) AS observation_count
FROM {{ ref('gold_safety_observations') }}
WHERE safety_level_numeric IS NOT NULL
  AND school_name IS NOT NULL
GROUP BY
    school_name,
    academic_cycle,
    CAST(safety_level_numeric AS INT64)