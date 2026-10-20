{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_language_quarterly'
) }}

-- Grain: one row per teacher_uid x academic_cycle x academic_quarter.
-- Feeds IM08 (the Q1-Q4 quarterly trend chart for Language, 4 points
-- within a single selected academic_cycle). No baseline column - same
-- idea as gold_teacher_math_quarterly, just for language practices.
--
--   teacher_uid                 - the teacher
--   academic_cycle                - e.g. "2023-24" (Apr-Mar year)
--   academic_quarter               - Q1-Q4
--   observation_date              - THAT QUARTER's latest QUALIFYING
--                                   observation's date for this teacher
--   practices_proficient_count    - distinct language practices hit
--                                   (is_practice_hit = true, already
--                                   computed in
--                                   gold_language_practice_responses -
--                                   not re-derived here) on that
--                                   quarter-latest observation (0-8)
--
-- "Qualifying observation" = subject_observed is hindi or english
-- (FL06 applicability rule, matches
-- gold_teacher_language_summary's own filter).
--
-- Kept as a SEPARATE table from gold_teacher_language_summary on
-- purpose - that one stays one-row-per-year (with baseline) for IM03's
-- "% teachers proficient" to work without needing a quarter filter;
-- this one has up to 4 rows per year and is only meant for the
-- quarterly chart, filtered to a single academic_cycle with no
-- academic_quarter filter applied (so all 4 points show).
--
-- Does not touch gold_language_practice_responses - joined/read as-is.

WITH distinct_submissions AS (

    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        observation_date
    FROM {{ ref('gold_language_practice_responses') }}
    WHERE subject_observed IN ('hindi', 'english')

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

practice_hits AS (

    SELECT DISTINCT
        lp.teacher_uid,
        lp.academic_cycle,
        lp.academic_quarter,
        p.language_practice
    FROM latest_per_quarter AS lp
    INNER JOIN {{ ref('gold_language_practice_responses') }} AS p
        ON lp.submission_id = p.submission_id
    WHERE p.is_practice_hit

)

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date,
    COUNT(DISTINCT ph.language_practice) AS practices_proficient_count
FROM latest_per_quarter AS lp
LEFT JOIN practice_hits AS ph
    ON lp.teacher_uid = ph.teacher_uid
    AND lp.academic_cycle = ph.academic_cycle
    AND lp.academic_quarter = ph.academic_quarter
GROUP BY
    lp.teacher_uid,
    lp.academic_cycle,
    lp.academic_quarter,
    lp.observation_date