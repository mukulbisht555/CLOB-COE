{{ config(
    materialized='table',
    schema='gold',
    alias='SV05_svi_indicator_frequency'
) }}

-- Grain: one row per academic_cycle x academic_quarter x domain
--        x indicator_code.
-- Feeds SV05 ("Top SV indicators observed - by domain": ranked bars of
-- how many observations recorded each indicator, grouped by
-- Collaboration / Critical Thinking / Creativity) and SV06 (the
-- drill-down of all indicators for one selected domain). One mart
-- serves both - SV06 is the same data filtered to a single domain.
--
--   academic_cycle      - e.g. "2025-26" (Apr-Mar year)
--   academic_quarter     - Q1-Q4
--   domain               - Collaboration, Critical Thinking or Creativity
--                          (the co_indicator, ct_indicator and
--                          cr_indicator groups)
--   indicator_code       - the indicator code exactly as recorded (B1.2,
--                          T1.1, V2.1 ...). Codes are kept as-is on
--                          purpose: the indicator label sheet is blended
--                          in Looker Studio on this code.
--   observation_count    - number of distinct observations in that
--                          period in which the indicator was recorded
--
-- Rules (from the SV05/SV06 definitions and the page filters):
--   * The unit is OBSERVATIONS, and every observation counts - not just
--     the latest per classroom. An observation counts once per
--     indicator even when it names two classrooms (gold_svi_indicator_
--     responses is fanned out per classroom, so the count is DISTINCT
--     submission_id).
--   * Only the three student-facing domains (is_21c_domain_indicator);
--     teacher_action rows belong to the 6E charts (SV07/SV08).
--   * Code 'none' means nothing was observed and is excluded.
--   * Filters supported: academic_cycle + academic_quarter. The count is
--     additive across periods, so Looker Studio's SUM(observation_count)
--     stays right for any cycle/quarter selection.
--
-- Choice made here: only indicators that were recorded at least once in
-- a period get a row. The sheet asks for the top / observed indicators,
-- so indicators with zero observations are not needed (unlike the
-- "least used" charts CS03 and FL06).
--
-- Ranking (highest to lowest) and "top N" are done in Looker Studio.
-- Nothing in Layers 1-2 is modified; gold_svi_indicator_responses is
-- read as-is.

WITH indicators AS (

    SELECT
        academic_cycle,
        academic_quarter,
        CASE indicator_group
            WHEN 'co_indicator' THEN 'Collaboration'
            WHEN 'ct_indicator' THEN 'Critical Thinking'
            WHEN 'cr_indicator' THEN 'Creativity'
        END AS domain,
        TRIM(indicator_code) AS indicator_code,
        submission_id
    FROM {{ ref('gold_svi_indicator_responses') }}
    WHERE is_21c_domain_indicator
      AND indicator_code IS NOT NULL
      AND LOWER(TRIM(indicator_code)) != 'none'

)

SELECT
    academic_cycle,
    academic_quarter,
    domain,
    indicator_code,
    COUNT(DISTINCT submission_id) AS observation_count
FROM indicators
GROUP BY
    academic_cycle,
    academic_quarter,
    domain,
    indicator_code