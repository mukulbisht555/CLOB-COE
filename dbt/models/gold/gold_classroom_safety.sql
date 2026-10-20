{{ config(
    materialized='table',
    schema='gold',
    alias='classroom_safety_summary'
) }}

-- Grain: one row per classroom_uid x academic_cycle.
-- Feeds IM05 ("Classrooms with active student engagement" - the
-- classroom-grain twin of IM01's safety check).
--
--   classroom_uid       - the classroom
--   academic_cycle        - e.g. "2023-24" (Apr-Mar year)
--   observation_date      - THAT CYCLE's latest observation's date for
--                            this classroom
--   safety_level           - that cycle-latest observation's safety_level
--   baseline_safety_level  - DIFFERENT RULE FROM IM01-IM04: this is the
--                            PREVIOUS cycle's LATEST observation's
--                            safety_level for this classroom (year-on-
--                            year), NOT the classroom's first-ever
--                            observation. NULL if the classroom has no
--                            observations in the immediately preceding
--                            cycle - no fallback.
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
-- THIS CYCLE'S LATEST OBSERVATION per classroom x cycle
-- ---------------------------------------------------------------

ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY classroom_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM distinct_classroom_submissions

),

latest_per_cycle AS (

    SELECT
        classroom_uid,
        academic_cycle,
        observation_date,
        safety_level_numeric AS safety_level
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- YEAR-ON-YEAR BASELINE: classroom's LATEST observation from the
-- PREVIOUS cycle only - resolved per (classroom, target cycle), NULL
-- if that classroom has no observations in the previous cycle
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
    lp.observation_date,
    lp.safety_level,
     COALESCE(bv.baseline_safety_level, 1) AS baseline_safety_level
FROM latest_per_cycle AS lp
LEFT JOIN baseline_value AS bv
    ON lp.classroom_uid = bv.classroom_uid
    AND lp.academic_cycle = bv.target_cycle