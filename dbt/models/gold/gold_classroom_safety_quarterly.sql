{{ config(
    materialized='table',
    schema='gold',
    alias='classroom_safety_quarterly'
) }}

-- Grain: one row per classroom_uid x academic_cycle x academic_quarter.
-- Feeds IM06 (the Q1-Q4 quarterly trend chart, 4 points within a single
-- selected academic_cycle).
--
--   classroom_uid       - the classroom
--   academic_cycle        - e.g. "2023-24" (Apr-Mar year)
--   academic_quarter       - Q1-Q4
--   observation_date      - THAT QUARTER's latest observation's date
--                            for this classroom
--   safety_level           - that quarter-latest observation's
--                            safety_level
--   baseline_safety_level  - same rule as IM05's baseline: the PREVIOUS
--                            cycle's LATEST observation's safety_level
--                            for this classroom (year-on-year), NOT
--                            first-ever. Computed at classroom x cycle
--                            grain (not per quarter) - the SAME baseline
--                            value is repeated across all 4 quarter-rows
--                            of a given cycle for a given classroom,
--                            since a baseline shouldn't move mid-year.
--                            NULL if no data exists in the immediately
--                            preceding cycle - no fallback.
--
-- Kept as a SEPARATE table from gold_classroom_safety_summary on
-- purpose - that one stays one-row-per-year for IM05's "% classrooms
-- safe" to work without needing a quarter filter; this one has 4 rows
-- per year and is only meant for the quarterly chart, filtered to a
-- single academic_cycle with no academic_quarter filter applied (so all
-- 4 points show).
--
-- gold_safety_observations is submission-grain (not classroom-grain), so
-- it's joined to gold_observation_classroom_bridge here to get one row
-- per submission x classroom - a co-teach submission naming 2
-- classrooms contributes a row to each classroom independently.
--
-- Does not touch gold_safety_observations or
-- gold_observation_classroom_bridge - both joined/read as-is.

WITH distinct_classroom_submissions AS (

    -- spans ALL cycles on purpose - the year-on-year baseline needs to
    -- look at the previous cycle, not just the current one
    SELECT DISTINCT
        cb.classroom_uid,
        cb.academic_cycle,
        cb.academic_quarter,
        so.submission_id,
        so.observation_date,
        so.safety_level_numeric,
        CAST(SUBSTR(cb.academic_cycle, 1, 4) AS INT64) AS cycle_start_year
    FROM {{ ref('gold_observation_classroom_bridge') }} AS cb
    INNER JOIN {{ ref('gold_safety_observations') }} AS so
        ON cb.submission_id = so.submission_id
    WHERE so.safety_level_numeric IS NOT NULL

),

-- ---------------------------------------------------------------
-- THIS QUARTER'S LATEST OBSERVATION per classroom x cycle x quarter
-- ---------------------------------------------------------------

ranked_latest_per_quarter AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY classroom_uid, academic_cycle, academic_quarter
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM distinct_classroom_submissions

),

latest_per_quarter AS (

    SELECT
        classroom_uid,
        academic_cycle,
        academic_quarter,
        observation_date,
        safety_level_numeric AS safety_level
    FROM ranked_latest_per_quarter
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- YEAR-ON-YEAR BASELINE: classroom's LATEST observation from the
-- PREVIOUS cycle only - resolved per (classroom, target cycle), NULL
-- if that classroom has no observations in the previous cycle. Same
-- logic as gold_classroom_safety_summary's baseline, kept identical
-- across both tables intentionally.
-- ---------------------------------------------------------------

classroom_cycles AS (

    SELECT DISTINCT
        classroom_uid,
        academic_cycle AS target_cycle,
        cycle_start_year
    FROM distinct_classroom_submissions

),

previous_year_candidates AS (

    SELECT
        cc.classroom_uid,
        cc.target_cycle,
        dcs.safety_level_numeric,
        ROW_NUMBER() OVER (
            PARTITION BY cc.classroom_uid, cc.target_cycle
            ORDER BY dcs.observation_date DESC, dcs.submission_id DESC
        ) AS rn
    FROM classroom_cycles AS cc
    INNER JOIN distinct_classroom_submissions AS dcs
        ON dcs.classroom_uid = cc.classroom_uid
        AND dcs.cycle_start_year = cc.cycle_start_year - 1

),

baseline_value AS (

    SELECT
        classroom_uid,
        target_cycle,
        safety_level_numeric AS baseline_safety_level
    FROM previous_year_candidates
    WHERE rn = 1

)

-- ---------------------------------------------------------------
-- FINAL
-- ---------------------------------------------------------------

SELECT
    lp.classroom_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date,
    lp.safety_level,
   COALESCE(bv.baseline_safety_level, 1) AS baseline_safety_level
FROM latest_per_quarter AS lp
LEFT JOIN baseline_value AS bv
    ON lp.classroom_uid = bv.classroom_uid
    AND lp.academic_cycle = bv.target_cycle