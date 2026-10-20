{{ config(
    materialized='table',
    schema='gold',
    alias='FLN06_language_step_frequency'
) }}

-- Grain: one row per academic_cycle x academic_quarter x language_practice
--        x sub_language_practice (step).
-- Feeds FL06 ("Most & least used steps - by language practice": horizontal
-- bars, % of applicable observations in which each step was recorded,
-- sorted high to low; the bottom steps are the coaching focus).
--
--   academic_cycle           - e.g. "2025-26" (Apr-Mar year)
--   academic_quarter          - Q1-Q4
--   language_practice         - LP1, LP2, LP3, LP4, LP6 ...
--   language_practice_name    - readable practice name
--   sub_language_practice     - the step code exactly as recorded (OS1,
--                               LSR2, BS3, RF1 ...). Codes are kept as-is
--                               on purpose: the step label sheet is
--                               blended in Looker Studio on this code.
--   observations_with_step    - observations in that period in which the
--                               step was recorded
--   applicable_observations   - hindi/english observations in that
--                               period (the denominator; the same number
--                               on every step row of the period)
--
-- The percentage is NOT stored. Both counts add up correctly across
-- periods, so Looker Studio computes
--   SUM(observations_with_step) / SUM(applicable_observations)
-- and it stays right for any cycle/quarter selection. A stored
-- percentage would be wrong as soon as more than one period is selected.
--
-- Confirmed rule:
--   * Applicable observation = subject_observed is hindi or english
--     (the subject comes from the observation table).
--
-- Choices made here (change them if they are wrong):
--   * The denominator counts EVERY hindi/english observation from
--     gold_observation_base, including one where no language step was
--     recorded at all. A step that was not recorded then counts as "not
--     enacted" in that observation.
--   * Steps that exist in the data but were never recorded in a period
--     still get a row with observations_with_step = 0. Without that, the
--     least-used steps - the ones this chart exists to show - would be
--     missing from the bottom of the ranking.
--   * The step list is taken from the steps that appear anywhere in
--     gold_language_practice_responses. A step that has never been
--     recorded in any observation cannot appear.
--   * An observation counts once per step, however many classrooms or
--     rows it has.
--
-- Nothing in Layers 1-2 is modified; both are read as-is.

WITH applicable AS (

    SELECT
        academic_cycle,
        academic_quarter,
        COUNT(DISTINCT submission_id) AS applicable_observations
    FROM {{ ref('gold_observation_base') }}
    WHERE subject_observed IN ('hindi', 'english')
    GROUP BY
        academic_cycle,
        academic_quarter

),

steps AS (

    SELECT DISTINCT
        language_practice,
        language_practice_name,
        sub_language_practice
    FROM {{ ref('gold_language_practice_responses') }}
    WHERE sub_language_practice IS NOT NULL

),

step_counts AS (

    SELECT
        academic_cycle,
        academic_quarter,
        language_practice,
        sub_language_practice,
        COUNT(DISTINCT submission_id) AS observations_with_step
    FROM {{ ref('gold_language_practice_responses') }}
    WHERE subject_observed IN ('hindi', 'english')
      AND sub_language_practice IS NOT NULL
    GROUP BY
        academic_cycle,
        academic_quarter,
        language_practice,
        sub_language_practice

)

SELECT
    a.academic_cycle,
    a.academic_quarter,
    s.language_practice,
    s.language_practice_name,
    s.sub_language_practice,
    COALESCE(c.observations_with_step, 0) AS observations_with_step,
    a.applicable_observations
FROM applicable AS a
CROSS JOIN steps AS s
LEFT JOIN step_counts AS c
    ON a.academic_cycle = c.academic_cycle
    AND a.academic_quarter = c.academic_quarter
    AND s.language_practice = c.language_practice
    AND s.sub_language_practice = c.sub_language_practice