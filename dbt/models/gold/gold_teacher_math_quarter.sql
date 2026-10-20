{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_math_quarterly'
) }}

-- Grain: one row per teacher_uid x academic_cycle x academic_quarter.
-- Feeds IM07 (the Q1-Q4 quarterly trend chart for Math, 4 points within
-- a single selected academic_cycle). No baseline column - this table is
-- comparison-point only, same idea as gold_classroom_safety_quarterly
-- but for math domains.
--
--   teacher_uid              - the teacher
--   academic_cycle            - e.g. "2023-24" (Apr-Mar year)
--   academic_quarter           - Q1-Q4
--   observation_date          - THAT QUARTER's latest observation's
--                               date for this teacher
--   domain_proficient_count   - distinct math domains (cc/psr/tr/gm)
--                               hit (mostly/vproficient) on that
--                               quarter-latest observation (0-4)
--
-- Kept as a SEPARATE table from gold_teacher_math_summary on purpose -
-- that one stays one-row-per-year (with baseline) for IM02's "%
-- teachers proficient" to work without needing a quarter filter; this
-- one has up to 4 rows per year and is only meant for the quarterly
-- chart, filtered to a single academic_cycle with no academic_quarter
-- filter applied (so all 4 points show).
--
-- Does not touch gold_math_indicator_responses - joined/read as-is.

WITH distinct_submissions AS (

    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        observation_date
    FROM {{ ref('gold_math_indicator_responses') }}

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

domain_hits AS (

    SELECT DISTINCT
        lp.teacher_uid,
        lp.academic_cycle,
        lp.academic_quarter,
        m.math_domain
    FROM latest_per_quarter AS lp
    INNER JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON lp.submission_id = m.submission_id
    WHERE m.is_mostly_or_vproficient
      AND m.math_domain IS NOT NULL

)

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date,
    COUNT(DISTINCT dh.math_domain) AS domain_proficient_count
FROM latest_per_quarter AS lp
LEFT JOIN domain_hits AS dh
    ON lp.teacher_uid = dh.teacher_uid
    AND lp.academic_cycle = dh.academic_cycle
    AND lp.academic_quarter = dh.academic_quarter
GROUP BY
    lp.teacher_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date