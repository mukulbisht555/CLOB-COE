{{ config(
    materialized='table',
    schema='gold',
    alias='teacher_language_summary'
) }}

-- Grain: one row per teacher_uid x academic_cycle.
-- Feeds IM03. Same shape/logic as gold_teacher_math_summary.
--
--   teacher_uid                        - the teacher
--   academic_cycle                      - e.g. "2023-24" (Apr-Mar year)
--   practices_proficient_count          - distinct language practices
--                                         hit (is_practice_hit = true,
--                                         i.e. >=70% of that practice's
--                                         steps observed - computed in
--                                         gold_language_practice_responses,
--                                         not re-derived here) on that
--                                         cycle's latest QUALIFYING
--                                         observation (0-8)
--   baseline_practice_proficient_count  - same count, but computed on
--                                         the teacher's very FIRST EVER
--                                         recorded qualifying observation
--                                         - a CONSTANT, identical on
--                                         every cycle-row for that
--                                         teacher
--
-- "Qualifying observation" = subject_observed is hindi or english
-- (FL06 applicability rule, matches gold_language_practice_responses'
-- own subject_observed column - excludes math-subject observations from
-- both the latest-per-cycle and first-ever-baseline lookups below).
--
-- Source columns used from gold_language_practice_responses (unchanged
-- there - only reading language_practice and is_practice_hit, both
-- already computed against the confirmed step-total lookup in that
-- file): submission_id, teacher_uid, academic_cycle, observation_date,
-- subject_observed, language_practice, is_practice_hit.
--
-- Does not touch gold_language_practice_responses - joined/read as-is.

WITH distinct_submissions AS (

    -- spans ALL cycles on purpose - baseline (first-ever) needs to look
    -- across cycles, not just the current one
    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        observation_date
    FROM {{ ref('gold_language_practice_responses') }}
    WHERE subject_observed IN ('hindi', 'english')

),

-- ---------------------------------------------------------------
-- THIS CYCLE'S LATEST QUALIFYING OBSERVATION per teacher x cycle
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

latest_practice_hits AS (

    SELECT DISTINCT
        lp.teacher_uid,
        lp.academic_cycle,
        p.language_practice
    FROM latest_per_cycle AS lp
    INNER JOIN {{ ref('gold_language_practice_responses') }} AS p
        ON lp.submission_id = p.submission_id
    WHERE p.is_practice_hit

),

-- ---------------------------------------------------------------
-- BASELINE: teacher's very FIRST EVER qualifying observation - a
-- constant per teacher, same value regardless of which cycle the row
-- is for
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

first_ever_practice_hits AS (

    SELECT DISTINCT
        fe.teacher_uid,
        p.language_practice
    FROM first_ever AS fe
    INNER JOIN {{ ref('gold_language_practice_responses') }} AS p
        ON fe.submission_id = p.submission_id
    WHERE p.is_practice_hit

),

baseline_counts AS (

    SELECT
        fe.teacher_uid,
        COUNT(DISTINCT feph.language_practice) AS baseline_practice_proficient_count
    FROM first_ever AS fe
    LEFT JOIN first_ever_practice_hits AS feph
        ON fe.teacher_uid = feph.teacher_uid
    GROUP BY fe.teacher_uid

)

-- ---------------------------------------------------------------
-- FINAL
-- ---------------------------------------------------------------

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    COUNT(DISTINCT lph.language_practice) AS practices_proficient_count,
    bc.baseline_practice_proficient_count
FROM latest_per_cycle AS lp
LEFT JOIN latest_practice_hits AS lph
    ON lp.teacher_uid = lph.teacher_uid
    AND lp.academic_cycle = lph.academic_cycle
LEFT JOIN baseline_counts AS bc
    ON lp.teacher_uid = bc.teacher_uid
GROUP BY
    lp.teacher_uid,
    lp.academic_cycle,
    bc.baseline_practice_proficient_count