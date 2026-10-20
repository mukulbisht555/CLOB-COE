{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_21c_quarterly'
) }}

-- Grain: one row per teacher_uid x academic_cycle x academic_quarter.
-- Feeds IM09 (the Q1-Q4 quarterly trend chart for 21C skills, 4 points
-- within a single selected academic_cycle). No baseline column - same
-- idea as gold_teacher_math_quarterly / gold_teacher_language_quarterly.
--
--   teacher_uid            - the teacher
--   academic_cycle           - e.g. "2023-24" (Apr-Mar year)
--   academic_quarter          - Q1-Q4
--   observation_date         - THAT QUARTER's latest observation's date
--                              for this teacher
--   teacher_action_count     - distinct SV-aligned teacher actions
--                              (TA_SV_* codes, excluding 'none') on
--                              that quarter-latest observation. A
--                              teacher "integrates 21C skills" when
--                              this is >= 5 - that threshold check is
--                              left to Looker Studio, this column holds
--                              the raw count.
--
-- gold_svi_indicator_responses is fanned out through the classroom
-- bridge (one row per submission x classroom x indicator), so
-- distinct_submissions below collapses that back to one row per
-- submission before any ranking happens - a co-teach submission naming
-- 2 classrooms is not double-counted. COUNT(DISTINCT indicator_code)
-- further down is also safe regardless - the same action code repeated
-- across classroom rows collapses fine.
--
-- Kept as a SEPARATE table from gold_teacher_21c_summary on purpose -
-- that one stays one-row-per-year (with baseline) for IM04's "%
-- teachers integrating 21C skills" to work without needing a quarter
-- filter; this one has up to 4 rows per year and is only meant for the
-- quarterly chart, filtered to a single academic_cycle with no
-- academic_quarter filter applied (so all 4 points show).
--
-- Does not touch gold_svi_indicator_responses - joined/read as-is.

WITH distinct_submissions AS (

    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        observation_date
    FROM {{ ref('gold_svi_indicator_responses') }}

),

ranked_latest_per_quarter AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle, academic_quarter
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM distinct_submissions

),

latest_per_quarter AS (

    SELECT
        teacher_uid,
        academic_cycle,
        academic_quarter,
        submission_id,
        observation_date
    FROM ranked_latest_per_quarter
    WHERE rn = 1

),

action_counts AS (

    SELECT
        lp.teacher_uid,
        lp.academic_cycle,
        lp.academic_quarter,
        COUNT(DISTINCT v.indicator_code) AS teacher_action_count
    FROM latest_per_quarter AS lp
    INNER JOIN {{ ref('gold_svi_indicator_responses') }} AS v
        ON lp.submission_id = v.submission_id
    WHERE v.is_sv_aligned_teacher_action
    GROUP BY lp.teacher_uid, lp.academic_cycle, lp.academic_quarter

)

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date,
    COALESCE(ac.teacher_action_count, 0) AS teacher_action_count
FROM latest_per_quarter AS lp
LEFT JOIN action_counts AS ac
    ON lp.teacher_uid = ac.teacher_uid
    AND lp.academic_cycle = ac.academic_cycle
    AND lp.academic_quarter = ac.academic_quarter