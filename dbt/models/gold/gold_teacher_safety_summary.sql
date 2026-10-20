{# {{ config(
    materialized='table',
    schema='gold',
    alias='teacher_safety_summary'
) }}

-- Grain: one row per teacher x academic_cycle x academic_quarter.
-- Feeds IM01 ("Teachers creating a safe & conducive environment" KPI)
-- and its trend.
--
-- COMPARISON POINT (unchanged):
--   1. For each teacher-period, find their SINGLE LATEST observation.
--   2. Explode it across its named classroom(s) via the bridge
--      (co-teach submissions can name more than one).
--   3. is_safety_level3plus = AVG(safety_level) across those classroom
--      rows is >= 3.
--
-- Two INDEPENDENT baseline columns (replaces the earlier combined
-- baseline_source/baseline_value logic):
--
--   year_on_year_baseline_safety_level
--     = the teacher's LAST observation from the cycle immediately
--       before this row's academic_cycle. NULL if they have no
--       observations in that previous cycle - no fallback. Different
--       per cycle (a teacher's 2025-26 rows compare against their
--       2024-25 last observation; their 2024-25 rows compare against
--       their 2023-24 last observation, etc).
--
--   fixed_baseline_safety_level
--     = the teacher's very FIRST observation EVER, across all cycles.
--       A true constant per teacher - identical value on every row of
--       theirs regardless of which cycle/quarter that row is for.
--
-- Both are raw averaged numbers (classroom-averaged, same treatment as
-- the comparison point) - NOT run through the >=3 pass/fail check, that
-- stays in Looker Studio.
--
-- program_name is carried through from the latest observation for
-- filtering. Trend-chart ordering uses academic_cycle + academic_quarter
-- directly. Does not touch gold_safety_observations or
-- gold_observation_classroom_bridge - both are joined as-is.

WITH classroom_level AS (

    SELECT
        so.submission_id,
        so.teacher_uid,
        so.academic_cycle,
        so.academic_quarter,
        so.observation_date,
        so.submission_time,
        so.program_name,
        so.school_name,
        cb.classroom_uid,
        so.safety_level_numeric
    FROM {{ ref('gold_safety_observations') }} AS so
    INNER JOIN {{ ref('gold_observation_classroom_bridge') }} AS cb
        ON so.submission_id = cb.submission_id
    WHERE so.safety_level_numeric IS NOT NULL

),

distinct_submissions AS (

    -- spans ALL cycles on purpose - both baseline computations below
    -- need to look across cycles, so this stays unfiltered.
    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        observation_date,
        submission_time,
        program_name,
        CAST(SUBSTR(academic_cycle, 1, 4) AS INT64) AS cycle_start_year
    FROM classroom_level

),

-- ---------------------------------------------------------------
-- COMPARISON POINT: latest observation per teacher x cycle x quarter
-- ---------------------------------------------------------------

ranked AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle, academic_quarter
            ORDER BY observation_date DESC, submission_time DESC, submission_id DESC
        ) AS rn
    FROM distinct_submissions

),

latest_submission AS (

    SELECT
        teacher_uid,
        academic_cycle,
        academic_quarter,
        submission_id AS latest_submission_id,
        observation_date AS latest_observation_date,
        program_name AS latest_program_name
    FROM ranked
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- YEAR-ON-YEAR BASELINE: teacher's last observation of the PREVIOUS
-- cycle, resolved per (teacher, target cycle) - NULL if none exists
-- ---------------------------------------------------------------

teacher_cycles AS (

    SELECT DISTINCT teacher_uid, academic_cycle, cycle_start_year
    FROM distinct_submissions

),

previous_year_candidates AS (

    SELECT
        tc.teacher_uid,
        tc.academic_cycle AS target_cycle,
        ds.submission_id,
        ROW_NUMBER() OVER (
            PARTITION BY tc.teacher_uid, tc.academic_cycle
            ORDER BY ds.observation_date DESC, ds.submission_id DESC
        ) AS rn
    FROM teacher_cycles AS tc
    INNER JOIN distinct_submissions AS ds
        ON ds.teacher_uid = tc.teacher_uid
        AND ds.cycle_start_year = tc.cycle_start_year - 1

),

year_on_year_baseline_submission AS (

    SELECT teacher_uid, target_cycle, submission_id AS yoy_submission_id
    FROM previous_year_candidates
    WHERE rn = 1

),

year_on_year_baseline_value AS (

    SELECT
        b.teacher_uid,
        b.target_cycle,
        AVG(cl.safety_level_numeric) AS year_on_year_baseline_safety_level
    FROM year_on_year_baseline_submission AS b
    INNER JOIN classroom_level AS cl
        ON b.yoy_submission_id = cl.submission_id
    GROUP BY b.teacher_uid, b.target_cycle

),

-- ---------------------------------------------------------------
-- FIXED BASELINE: teacher's very first observation EVER - a constant
-- per teacher, same value regardless of which cycle/quarter the row is
-- ---------------------------------------------------------------

teacher_first_ever AS (

    SELECT
        teacher_uid,
        submission_id,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid
            ORDER BY observation_date ASC, submission_id ASC
        ) AS rn
    FROM distinct_submissions

),

fixed_baseline_submission AS (

    SELECT teacher_uid, submission_id AS fixed_submission_id
    FROM teacher_first_ever
    WHERE rn = 1

),

fixed_baseline_value AS (

    SELECT
        b.teacher_uid,
        AVG(cl.safety_level_numeric) AS fixed_baseline_safety_level
    FROM fixed_baseline_submission AS b
    INNER JOIN classroom_level AS cl
        ON b.fixed_submission_id = cl.submission_id
    GROUP BY b.teacher_uid

)

-- ---------------------------------------------------------------
-- FINAL: comparison point + both baselines, one row per teacher x
-- cycle x quarter
-- ---------------------------------------------------------------

SELECT
    ls.teacher_uid,
    ls.academic_cycle,
    ls.academic_quarter,
    ls.latest_submission_id,
    ls.latest_observation_date,
    ls.latest_program_name AS program_name,
    COUNT(DISTINCT cl.classroom_uid) AS n_classrooms_in_latest_observation,
    AVG(cl.safety_level_numeric) AS avg_classroom_safety_level,
    AVG(cl.safety_level_numeric) >= 3 AS is_safety_level3plus,
    yoy.year_on_year_baseline_safety_level,
    fb.fixed_baseline_safety_level,
     fb.fixed_baseline_safety_level >= 3 AS is_fixed_baseline_safety_level3plus
FROM latest_submission AS ls
INNER JOIN classroom_level AS cl
    ON ls.latest_submission_id = cl.submission_id
LEFT JOIN year_on_year_baseline_value AS yoy
    ON ls.teacher_uid = yoy.teacher_uid
    AND ls.academic_cycle = yoy.target_cycle
LEFT JOIN fixed_baseline_value AS fb
    ON ls.teacher_uid = fb.teacher_uid
GROUP BY
    ls.teacher_uid,
    ls.academic_cycle,
    ls.academic_quarter,
    ls.latest_submission_id,
    ls.latest_observation_date,
    ls.latest_program_name,
    yoy.year_on_year_baseline_safety_level,
    fb.fixed_baseline_safety_level #}


{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_safety_summary'
) }}

-- Grain: one row per teacher_id x academic_cycle.
-- Feeds IM01.
--
--   teacher_id       - the teacher
--   academic_cycle    - e.g. "2023-24" (Apr-Mar year)
--   submission_id     - THAT CYCLE's latest observation for this teacher
--   safety_level      - that cycle-latest observation's safety_level
--   baseline          - the teacher's very FIRST EVER recorded
--                        observation's safety_level - a CONSTANT,
--                        identical on every cycle-row for that teacher
--                        (computed across ALL cycles, not just this row's)
--   observation_date  - that cycle-latest observation's date
--
-- This lets a year filter on academic_cycle actually change something:
-- each cycle-row shows that specific year's own latest reading, always
-- compared against the same fixed baseline anchor.
--
-- Does not touch gold_safety_observations - joined/read as-is.

WITH ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM {{ ref('gold_safety_observations') }}
    WHERE safety_level_numeric IS NOT NULL

),

latest_per_cycle AS (

    SELECT
        teacher_uid,
        academic_cycle,
        submission_id,
        observation_date,
        safety_level_numeric AS safety_level
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

ranked_first_ever AS (

    -- spans ALL cycles on purpose - baseline is a per-teacher constant,
    -- not recalculated per cycle
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid
            ORDER BY observation_date ASC, submission_id ASC
        ) AS rn
    FROM {{ ref('gold_safety_observations') }}
    WHERE safety_level_numeric IS NOT NULL

),

first_ever AS (

    SELECT
        teacher_uid,
        safety_level_numeric AS baseline
    FROM ranked_first_ever
    WHERE rn = 1

)

SELECT
    l.teacher_uid,
    l.academic_cycle,
    l.submission_id,
    l.safety_level,
    f.baseline,
    l.observation_date
FROM latest_per_cycle AS l
LEFT JOIN first_ever AS f
    ON l.teacher_uid = f.teacher_uid