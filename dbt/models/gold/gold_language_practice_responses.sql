{{ config(
    materialized='table',
    schema='gold',
    alias='language_practice_responses'
) }}

-- Grain: one row per observation submission x language practice x
-- selected sub-practice step.
-- Only 8 of the practices are real (LP1,LP2,LP3,LP4,LP6,LP7,LP8,LP9 -
-- LP5 does not exist / has no row below and will fall out of the join).
-- total_steps and is_practice_hit (>=70% of that practice's steps
-- observed) come from the confirmed step counts below, computed
-- directly here - no Looker Studio blend needed for this one.
-- Feeds gold_teacher_language_summary (IM03 KPI + trend, FL01-FL07).
--
-- Step counts confirmed by the program team (kept inline here since
-- this is the only mart that needs them - move to a seed/macro instead
-- if a second model ever needs the same lookup):
--   LP1 Oral sound awareness   = 4
--   LP2 Letter-Sound Recognition = 5
--   LP3 Blending & Segmenting  = 4
--   LP4 Reading Fluency        = 4
--   LP6 Vocabulary Practice    = 6
--   LP7 Reading Comprehension  = 7
--   LP8 Speaking               = 7
--   LP9 Writing                = 6

WITH language_practice_step_totals AS (

    SELECT 'LP1' AS language_practice, 'Oral sound awareness' AS language_practice_name, 4 AS total_steps UNION ALL
    SELECT 'LP2', 'Letter-Sound Recognition', 5 UNION ALL
    SELECT 'LP3', 'Blending & Segmenting', 4 UNION ALL
    SELECT 'LP4', 'Reading Fluency', 4 UNION ALL
    SELECT 'LP6', 'Vocabulary Practice', 6 UNION ALL
    SELECT 'LP7', 'Reading Comprehension', 7 UNION ALL
    SELECT 'LP8', 'Speaking', 7 UNION ALL
    SELECT 'LP9', 'Writing', 6

),

practice_steps AS (

    SELECT
        submission_id,
        language_practice,
        sub_language_practice,
        COUNT(sub_language_practice) OVER (
            PARTITION BY submission_id, language_practice
        ) AS steps_observed_count
    FROM {{ ref('fct_language_practices') }}

)

SELECT
    b.submission_id,
    b.observation_date,
    b.academic_cycle,
    b.academic_quarter,
    b.calendar_year,
    b.school_name,
    b.school_key,
    b.teacher_uid,
    b.teaching_type,
    b.subject_observed,
    b.program_name,

    p.language_practice,
    t.language_practice_name,
    p.sub_language_practice,
    p.steps_observed_count,
    t.total_steps,
    SAFE_DIVIDE(p.steps_observed_count, t.total_steps) AS pct_steps_observed,
    SAFE_DIVIDE(p.steps_observed_count, t.total_steps) >= 0.70 AS is_practice_hit
FROM {{ ref('gold_observation_base') }} AS b
INNER JOIN practice_steps AS p
    ON b.submission_id = p.submission_id
INNER JOIN language_practice_step_totals AS t
    ON p.language_practice = t.language_practice
