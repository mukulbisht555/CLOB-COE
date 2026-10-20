{{ config(
    materialized='table',
    schema='gold',
    alias='classroom_sv_domain_quarterly'
) }}

-- Grain: one row per classroom_uid x academic_cycle x academic_quarter
--        x domain.
-- Feeds SV04 ("21C domain trends - % classrooms": three lines,
-- Collaboration / Critical Thinking / Creativity, with Q1-Q4 of the
-- selected academic_cycle on the x-axis, like IM06-IM09). No baseline
-- column - trend only.
--
--   classroom_uid        - the classroom (one code per row; co-teach
--                          observations naming two classrooms are split
--                          by gold_observation_classroom_bridge)
--   academic_cycle        - e.g. "2025-26" (Apr-Mar year)
--   academic_quarter       - Q1-Q4
--   domain                 - Collaboration, Critical Thinking or
--                            Creativity (the co_indicator,
--                            ct_indicator and cr_indicator groups)
--   indicator_count        - distinct indicators ticked in that domain on
--                            the classroom's LATEST observation in that
--                            quarter
--
-- The "at least two indicators" test is applied in Looker Studio:
--   COUNT_DISTINCT(CASE WHEN indicator_count >= 2
--                  THEN classroom_uid END) / COUNT_DISTINCT(classroom_uid)
--
-- Confirmed rules:
--   * The classroom's latest observation decides - here, its latest
--     observation within each quarter.
--   * x-axis = Q1-Q4 of the selected cycle; the cycle control applies,
--     the quarter control must not.
--
-- Kept as a SEPARATE table from gold_classroom_sv_domain_summary on
-- purpose - that one has one row per classroom per cycle (for the
-- SV01-SV03 cards, which would double count if quarter rows were mixed
-- in); this one has up to 4 rows per classroom per cycle and is only for
-- the quarter-by-quarter chart.
--
-- Same choices as the SV01-SV03 mart:
--   * The denominator is every classroom observed in the quarter (the
--     observation set comes from gold_observation_classroom_bridge), so
--     a classroom whose latest observation has no indicator rows still
--     counts, with 0.
--   * Indicator code 'none' means nothing was observed and is not
--     counted.
--   * Only the student-facing domains count (is_21c_domain_indicator);
--     teacher_action rows are not part of SV01-SV04.
--
-- Ties on the same observation_date fall back to submission_id.
-- Nothing in Layers 1-2 is modified; both are read as-is.

WITH classroom_observations AS (

    SELECT DISTINCT
        classroom_uid,
        academic_cycle,
        academic_quarter,
        submission_id,
        observation_date
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

ranked_latest_per_quarter AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY classroom_uid, academic_cycle, academic_quarter
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM classroom_observations

),

latest_per_quarter AS (

    SELECT
        classroom_uid,
        academic_cycle,
        academic_quarter,
        submission_id
    FROM ranked_latest_per_quarter
    WHERE rn = 1

)

SELECT
    l.classroom_uid,
    l.academic_cycle,
    l.academic_quarter,
    d.domain,
    COALESCE(c.indicator_count, 0) AS indicator_count
FROM latest_per_quarter AS l
CROSS JOIN domains AS d
LEFT JOIN indicator_counts AS c
    ON c.submission_id = l.submission_id
    AND c.classroom_uid = l.classroom_uid
    AND c.indicator_group = d.indicator_group