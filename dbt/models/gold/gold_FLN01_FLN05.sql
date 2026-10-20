{{ config(
    materialized='table',
    schema='gold',
    alias='fln01_05_teacher_language_practice_summary'
) }}

-- Grain: one row per teacher_uid x academic_cycle x language_practice.
-- Feeds FL01-FL05 (KPI cards "Teachers proficient" for each language
-- practice: Oral sound awareness LP1, Letter-sound recognition LP2,
-- Blending & segmenting LP3, Reading fluency LP4, Vocabulary practice
-- LP6). One mart serves all five cards - each card just filters
-- language_practice in Looker Studio.
--
--   teacher_uid                  - the teacher
--   academic_cycle                - e.g. "2025-26" (Apr-Mar year)
--   language_practice             - LP1, LP2, LP3, LP4, LP6 ... as in
--                                   gold_language_practice_responses
--   language_practice_name        - readable name of the practice
--   latest_pct_steps_observed     - share (0 to 1) of this practice's
--                                   steps recorded on the teacher's
--                                   LATEST qualifying observation in the
--                                   cycle; 0 when that observation
--                                   recorded none of the practice's steps
--   baseline_pct_steps_observed   - same share, on the teacher's very
--                                   FIRST EVER qualifying observation - a
--                                   constant per teacher x practice, the
--                                   same in every cycle row
--
-- The 70% threshold ("at least 70% steps observed") is applied in
-- Looker Studio, not here. The sheet marks the threshold as "confirm",
-- so the raw share is kept and changing it needs no rebuild:
--   COUNT_DISTINCT(CASE WHEN latest_pct_steps_observed >= 0.7
--                  THEN teacher_uid END) / COUNT_DISTINCT(teacher_uid)
--
-- Rules carried over from IM03, so FL01-FL05 reconcile with it:
--   * Qualifying observation = subject_observed is hindi or english.
--   * The teacher's single LATEST qualifying observation in the cycle
--     decides - not any observation.
--   * Every teacher with a qualifying observation in the cycle is in the
--     denominator for every practice; a teacher whose latest observation
--     recorded no steps of a practice counts as 0% for it (not
--     proficient), so the practice row is still produced.
--   * Baseline = first-ever qualifying observation.
--   * Filter supported: academic_cycle only (no quarter/school columns).
--
-- Observation set: built from gold_language_practice_responses, exactly
-- like IM03, so a hindi/english observation with no language step
-- recorded at all is not in this set.
-- A teacher with only one qualifying observation has baseline = latest.
-- Ties on the same observation_date fall back to submission_id.
--
-- The step share itself (steps recorded / total steps of the practice)
-- is computed in gold_language_practice_responses (pct_steps_observed);
-- it is read as-is here, not recomputed, so the step totals live in one
-- place only. Nothing in Layers 1-2 is modified.

WITH qualifying_submissions AS (

    SELECT DISTINCT
        submission_id,
        teacher_uid,
        academic_cycle,
        observation_date
    FROM {{ ref('gold_language_practice_responses') }}
    WHERE subject_observed IN ('hindi', 'english')

),

practices AS (

    SELECT DISTINCT
        language_practice,
        language_practice_name
    FROM {{ ref('gold_language_practice_responses') }}

),

submission_practice_pct AS (

    -- layer 2 repeats the share on every step row of a practice, so
    -- collapse to one value per submission x practice
    SELECT
        submission_id,
        language_practice,
        MAX(pct_steps_observed) AS pct_steps_observed
    FROM {{ ref('gold_language_practice_responses') }}
    GROUP BY submission_id, language_practice

),

-- ---------------------------------------------------------------
-- LATEST qualifying observation per teacher x cycle
-- ---------------------------------------------------------------

ranked_latest_per_cycle AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid, academic_cycle
            ORDER BY observation_date DESC, submission_id DESC
        ) AS rn
    FROM qualifying_submissions

),

latest_per_cycle AS (

    SELECT
        teacher_uid,
        academic_cycle,
        submission_id
    FROM ranked_latest_per_cycle
    WHERE rn = 1

),

-- ---------------------------------------------------------------
-- BASELINE: FIRST EVER qualifying observation per teacher
-- (spans all cycles on purpose)
-- ---------------------------------------------------------------

ranked_first_ever AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY teacher_uid
            ORDER BY observation_date ASC, submission_id ASC
        ) AS rn
    FROM qualifying_submissions

),

first_ever AS (

    SELECT
        teacher_uid,
        submission_id
    FROM ranked_first_ever
    WHERE rn = 1

)

SELECT
    l.teacher_uid,
    l.academic_cycle,
    p.language_practice,
    p.language_practice_name,
    COALESCE(lp.pct_steps_observed, 0) AS latest_pct_steps_observed,
    COALESCE(bp.pct_steps_observed, 0) AS baseline_pct_steps_observed
FROM latest_per_cycle AS l
INNER JOIN first_ever AS f
    ON l.teacher_uid = f.teacher_uid
CROSS JOIN practices AS p
LEFT JOIN submission_practice_pct AS lp
    ON l.submission_id = lp.submission_id
    AND p.language_practice = lp.language_practice
LEFT JOIN submission_practice_pct AS bp
    ON f.submission_id = bp.submission_id
    AND p.language_practice = bp.language_practice