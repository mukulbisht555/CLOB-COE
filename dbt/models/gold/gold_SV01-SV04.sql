{{ config(
    materialized='table',
    schema='gold',
    alias='SV01_SV03_classroom_sv_domain'
) }}

-- Grain: one row per classroom_uid x academic_cycle x domain.
-- Feeds SV01-SV03 (KPI cards: % of classrooms with at least two
-- indicators observed in Collaboration / Critical Thinking / Creativity)
-- and is meant to feed the SV04 by-cycle trend as well. One mart serves
-- all three cards - each card just filters domain in Looker Studio.
--
--   classroom_uid               - the classroom (one code per row;
--                                 co-teach observations naming two
--                                 classrooms are split by
--                                 gold_observation_classroom_bridge)
--   academic_cycle               - e.g. "2025-26" (Apr-Mar year)
--   domain                       - Collaboration, Critical Thinking or
--                                 Creativity (the co_indicator,
--                                 ct_indicator and cr_indicator groups)
--   latest_indicator_count       - distinct indicators ticked in that
--                                 domain on the classroom's LATEST
--                                 observation in the cycle
--   baseline_indicator_count     - same count on the classroom's LAST
--                                 observation of the PREVIOUS academic
--                                 year. NULL if the classroom has no
--                                 observation in the previous cycle - no
--                                 fallback, same as IM05.
--
-- The "at least two indicators" test is applied in Looker Studio, as in
-- the IM marts:
--   COUNT_DISTINCT(CASE WHEN latest_indicator_count >= 2
--                  THEN classroom_uid END) / COUNT_DISTINCT(classroom_uid)
--
-- Confirmed rules:
--   * The classroom's LATEST observation in the cycle decides (not any
--     observation, not indicators added up across the cycle).
--   * Baseline = last observation of the previous academic year.
--   * Filter for SV01-SV03: academic_cycle only.
--
-- Choices made here (change them if they are wrong):
--   * The denominator is every classroom observed in the cycle. The
--     observation set comes from gold_observation_classroom_bridge, so a
--     classroom whose latest observation has no indicator rows at all is
--     still counted, with an indicator count of 0.
--   * Indicator code 'none' means nothing was observed and is not counted.
--   * Only the student-facing domains count (is_21c_domain_indicator);
--     teacher_action rows are the 6E / IM04 side, not part of SV01-SV04.
--   * The sheet title says ">=50% of students", but the data records
--     which indicators were ticked, not how many students, so the
--     Definition column's two-indicator rule is used.
--
-- Ties on the same observation_date fall back to submission_id.
-- Nothing in Layers 1-2 is modified; both are read as-is.

WITH classroom_observations AS (

    SELECT DISTINCT
        classroom_uid,
        academic_cycle,
        submission_id,
        observation_date,
        CAST(SUBSTR(academic_cycle, 1, 4) AS INT64) AS cycle_start_year
    FROM {{ ref('gold_observation_classroom_bridge') }}

),

domains AS (

    SELECT 'co_indicator' AS indicator_group, 'Collaboration' AS domain
    UNION ALL
    SELECT 'ct_indicator', 'Critical Thinking'
    UNION ALL
    SELECT 'cr_indicator', 'Creativity'

),

indicator_counts AS (

    SELECT
        submission_id,
        classroom_uid,
        indicator_group,
        COUNT(DISTINCT indicator_code) AS indicator_count
    FROM {{ ref('gold_svi_indicator_responses') }}
    WHERE is_21c_domain_indicator
      AND LOWER(TRIM(indicator_code)) != 'none'
    GROUP BY
        submission_id,
        classroom_uid,
        indicator_group

),

-- ---------------------------------------------------------------
-- LATEST observation per classroom x cycle
-- ---------------------------------------------------------------

ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY classroom_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM classroom_observations

),

latest_per_cycle AS (

    SELECT
        classroom_uid,
        academic_cycle,
        cycle_start_year,
        submission_id
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- BASELINE: last observation of the PREVIOUS cycle, resolved per
-- (classroom, target cycle) - no row when there is none
-- ---------------------------------------------------------------

previous_year_candidates AS (

    SELECT
        l.classroom_uid,
        l.academic_cycle AS target_cycle,
        o.submission_id,
        ROW_NUMBER() OVER (
            PARTITION BY l.classroom_uid, l.academic_cycle
            ORDER BY o.observation_date DESC, o.submission_id DESC
        ) AS rn
    FROM latest_per_cycle AS l
    INNER JOIN classroom_observations AS o
        ON o.classroom_uid = l.classroom_uid
        AND o.cycle_start_year = l.cycle_start_year - 1

),

baseline_submission AS (

    SELECT
        classroom_uid,
        target_cycle,
        submission_id AS baseline_submission_id
    FROM previous_year_candidates
    WHERE rn = 1

)

SELECT
    l.classroom_uid,
    l.academic_cycle,
    d.domain,
    COALESCE(lc.indicator_count, 0) AS latest_indicator_count,
    CASE
        WHEN b.baseline_submission_id IS NULL THEN NULL
        ELSE COALESCE(bc.indicator_count, 0)
    END AS baseline_indicator_count
FROM latest_per_cycle AS l
CROSS JOIN domains AS d
LEFT JOIN indicator_counts AS lc
    ON lc.submission_id = l.submission_id
    AND lc.classroom_uid = l.classroom_uid
    AND lc.indicator_group = d.indicator_group
LEFT JOIN baseline_submission AS b
    ON b.classroom_uid = l.classroom_uid
    AND b.target_cycle = l.academic_cycle
LEFT JOIN indicator_counts AS bc
    ON bc.submission_id = b.baseline_submission_id
    AND bc.classroom_uid = l.classroom_uid
    AND bc.indicator_group = d.indicator_group