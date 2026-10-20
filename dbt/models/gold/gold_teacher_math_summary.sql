{# {{ config(
    materialized='table',
    schema='gold',
    alias='teacher_math_summary'
) }}

-- Grain: one row per teacher x academic_cycle x academic_quarter.
-- Feeds IM02 ("Teachers proficient in FLN - Math" KPI + trend).
--
-- COMPARISON POINT (unchanged):
--   1. For each teacher-period, find their SINGLE LATEST observation.
--   2. Within that one observation, check the 4 math domains
--      (cc, psr, tr, gm) - a domain "hits" if ANY indicator in it was
--      rated mostly or vproficient on that one observation.
--   3. is_math_proficient = >= 2 distinct domains hit on that single
--      latest observation.
--
-- Two INDEPENDENT baseline columns (same pattern as IM01):
--
--   year_on_year_baseline_domains_proficient_count
--     = domains hit on the teacher's LAST observation from the cycle
--       immediately before this row's academic_cycle. NULL if they have
--       no observations in that previous cycle - no fallback.
--
--   fixed_baseline_domains_proficient_count
--     = domains hit on the teacher's very FIRST observation EVER,
--       across all cycles. A true constant per teacher - identical
--       value on every row of theirs regardless of cycle/quarter.
--
-- Both are raw domain-hit counts (0-4), NOT run through the >=2
-- pass/fail check - that stays in Looker Studio.
--
-- Does not touch gold_math_indicator_responses - joined as-is.
-- Note: no submission_time column on that fact, so ties on the same
-- date fall back to submission_id (same limitation as before).

WITH distinct_submissions AS (

    -- spans ALL cycles on purpose - both baseline computations below
    -- need to look across cycles, so this stays unfiltered.
    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        observation_date,
        CAST(SUBSTR(academic_cycle, 1, 4) AS INT64) AS cycle_start_year
    FROM {{ ref('gold_math_indicator_responses') }}

),

-- ---------------------------------------------------------------
-- COMPARISON POINT: latest observation per teacher x cycle x quarter
-- ---------------------------------------------------------------

ranked AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle, academic_quarter
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM distinct_submissions

),

latest_submission AS (

    SELECT
        teacher_uid,
        academic_cycle,
        academic_quarter,
        submission_id AS latest_submission_id,
        observation_date AS latest_observation_date
    FROM ranked
    WHERE rn = 1

),

domain_hits AS (

    SELECT DISTINCT
        ls.teacher_uid,
        ls.academic_cycle,
        ls.academic_quarter,
        m.math_domain
    FROM latest_submission AS ls
    INNER JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON ls.latest_submission_id = m.submission_id
    WHERE m.is_mostly_or_vproficient
      AND m.math_domain IS NOT NULL

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
        COUNT(DISTINCT m.math_domain) AS year_on_year_baseline_domains_proficient_count
    FROM year_on_year_baseline_submission AS b
    LEFT JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON b.yoy_submission_id = m.submission_id
        AND m.is_mostly_or_vproficient
        AND m.math_domain IS NOT NULL
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
        COUNT(DISTINCT m.math_domain) AS fixed_baseline_domains_proficient_count
    FROM fixed_baseline_submission AS b
    LEFT JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON b.fixed_submission_id = m.submission_id
        AND m.is_mostly_or_vproficient
        AND m.math_domain IS NOT NULL
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
    COUNT(DISTINCT dh.math_domain) AS domains_proficient_count,
    COUNT(DISTINCT dh.math_domain) >= 2 AS is_math_proficient,
    yoy.year_on_year_baseline_domains_proficient_count,
    fb.fixed_baseline_domains_proficient_count,
    (fb.fixed_baseline_domains_proficient_count >= 2) AS is_math_fixed_baseline_proficient
FROM latest_submission AS ls
LEFT JOIN domain_hits AS dh
    ON ls.teacher_uid = dh.teacher_uid
    AND ls.academic_cycle = dh.academic_cycle
    AND ls.academic_quarter = dh.academic_quarter
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
    yoy.year_on_year_baseline_domains_proficient_count,
    fb.fixed_baseline_domains_proficient_count #}



    {{ config(
    materialized='table',
    schema='gold',
    alias='teacher_math_summary'
) }}

-- Grain: one row per teacher_uid x academic_cycle.
-- Feeds IM02. Same shape as the reset IM01 mart.
--
--   teacher_uid            - the teacher
--   academic_cycle          - e.g. "2023-24" (Apr-Mar year)
--   observation_date        - THAT CYCLE's latest observation's date
--   domain_proficient_count - domains hit (mostly/vproficient) on that
--                             cycle-latest observation (0-4)
--   baseline_domain_count   - domains hit on the teacher's very FIRST
--                             EVER recorded observation - a CONSTANT,
--                             identical on every cycle-row for that
--                             teacher (computed across ALL cycles)
--
-- Does not touch gold_math_indicator_responses - joined/read as-is.

WITH distinct_submissions AS (

    -- spans ALL cycles on purpose - baseline (first-ever) needs to look
    -- across cycles, not just the current one
    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        observation_date
    FROM {{ ref('gold_math_indicator_responses') }}

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
        submission_id,
        observation_date
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

latest_domain_hits AS (

    SELECT DISTINCT
        lp.teacher_uid,
        lp.academic_cycle,
        m.math_domain
    FROM latest_per_cycle AS lp
    INNER JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON lp.submission_id = m.submission_id
    WHERE m.is_mostly_or_vproficient
      AND m.math_domain IS NOT NULL

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

first_ever_domain_hits AS (

    SELECT DISTINCT
        fe.teacher_uid,
        m.math_domain
    FROM first_ever AS fe
    INNER JOIN {{ ref('gold_math_indicator_responses') }} AS m
        ON fe.submission_id = m.submission_id
    WHERE m.is_mostly_or_vproficient
      AND m.math_domain IS NOT NULL

),

baseline_counts AS (

    SELECT
        fe.teacher_uid,
        COUNT(DISTINCT fedh.math_domain) AS baseline_domain_count
    FROM first_ever AS fe
    LEFT JOIN first_ever_domain_hits AS fedh
        ON fe.teacher_uid = fedh.teacher_uid
    GROUP BY fe.teacher_uid

)

-- ---------------------------------------------------------------
-- FINAL
-- ---------------------------------------------------------------

SELECT
    lp.teacher_uid,
    lp.academic_cycle,
    lp.observation_date,
    COUNT(DISTINCT ldh.math_domain) AS domain_proficient_count,
    bc.baseline_domain_count
FROM latest_per_cycle AS lp
LEFT JOIN latest_domain_hits AS ldh
    ON lp.teacher_uid = ldh.teacher_uid
    AND lp.academic_cycle = ldh.academic_cycle
LEFT JOIN baseline_counts AS bc
    ON lp.teacher_uid = bc.teacher_uid
GROUP BY
    lp.teacher_uid,
    lp.academic_cycle,
    lp.observation_date,
    bc.baseline_domain_count