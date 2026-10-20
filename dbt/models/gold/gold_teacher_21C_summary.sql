{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_21c_summary'
) }}

-- Grain: one row per teacher_uid x academic_cycle.
-- Feeds IM04. Same shape/logic as gold_teacher_math_summary /
-- gold_teacher_language_summary.
--
--   teacher_uid              - the teacher
--   academic_cycle            - e.g. "2023-24" (Apr-Mar year)
--   teacher_action_count      - distinct SV-aligned teacher actions
--                               (TA_SV_* codes, excluding 'none') on
--                               that cycle's latest observation. A
--                               teacher "integrates 21C skills" in a
--                               period when this is >= 5 - that
--                               threshold check is left to Looker
--                               Studio, this column holds the raw count.
--   baseline_teacher_action_count - same count, but computed on the
--                               teacher's very FIRST EVER recorded
--                               observation - a CONSTANT, identical on
--                               every cycle-row for that teacher
--
-- gold_svi_indicator_responses is fanned out through the classroom
-- bridge (one row per submission x classroom x indicator), so
-- distinct_submissions below collapses that back to one row per
-- submission before any ranking happens - otherwise a co-teach
-- submission naming 2 classrooms would be counted twice.
-- COUNT(DISTINCT indicator_code) further down is also safe regardless -
-- the same action code repeated across classroom rows collapses fine.
--
-- Does not touch gold_svi_indicator_responses - joined/read as-is.

WITH distinct_submissions AS (

    -- spans ALL cycles on purpose - baseline (first-ever) needs to look
    -- across cycles, not just the current one
    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        observation_date
    FROM {{ ref('gold_svi_indicator_responses') }}

),

-- ---------------------------------------------------------------
-- THIS CYCLE'S LATEST OBSERVATION per teacher x cycle
-- ---------------------------------------------------------------

ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM distinct_submissions

),

latest_per_cycle AS (

    SELECT
        teacher_uid,
        academic_cycle,
        submission_id
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

latest_action_counts AS (

    SELECT
        lp.teacher_uid,
        lp.academic_cycle,
        COUNT(DISTINCT v.indicator_code) AS teacher_action_count
    FROM latest_per_cycle AS lp
    INNER JOIN {{ ref('gold_svi_indicator_responses') }} AS v
        ON lp.submission_id = v.submission_id
    WHERE v.is_sv_aligned_teacher_action
    GROUP BY lp.teacher_uid, lp.academic_cycle

),

-- ---------------------------------------------------------------
-- BASELINE: teacher's very FIRST EVER observation - a constant per
-- teacher, same value regardless of which cycle the row is for
-- ---------------------------------------------------------------

ranked_first_ever AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid
            ORDER BY observation_date ASC, submission_id ASC
        ) AS rn
    FROM distinct_submissions

),

first_ever AS (

    SELECT teacher_uid, submission_id
    FROM ranked_first_ever
    WHERE rn = 1

),

baseline_counts AS (

    SELECT
        fe.teacher_uid,
        COUNT(DISTINCT v.indicator_code) AS baseline_teacher_action_count
    FROM first_ever AS fe
    LEFT JOIN {{ ref('gold_svi_indicator_responses') }} AS v
        ON fe.submission_id = v.submission_id
        AND v.is_sv_aligned_teacher_action
    GROUP BY fe.teacher_uid

)

-- ---------------------------------------------------------------
-- FINAL
-- ---------------------------------------------------------------

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    COALESCE(lac.teacher_action_count, 0) AS teacher_action_count,
    bc.baseline_teacher_action_count
FROM latest_per_cycle AS lp
LEFT JOIN latest_action_counts AS lac
    ON lp.teacher_uid = lac.teacher_uid
    AND lp.academic_cycle = lac.academic_cycle
LEFT JOIN baseline_counts AS bc
    ON lp.teacher_uid = bc.teacher_uid