{{ config(
    materialized='table',
    schema='gold',
    alias='classroom_21c_summary'
) }}

-- Grain: one row per classroom x academic_cycle x academic_quarter.
-- Feeds IM04 ("Teachers integrating 21C skills" KPI + trend, IM09 trend).
--
-- Confirmed rule: an observation counts as "21C integrated" if it has
-- >= 5 distinct SV-aligned teacher-action codes (TA_SV_*, excluding
-- 'none'). A classroom is integrated in the period if ANY of its
-- observations in that period hit that threshold.
--
-- Note: the KPI card on the dashboard is worded "Teachers integrating
-- 21C skills" but the confirmed grain is classroom x cycle - if you
-- also want a teacher-level version of this same >=5-actions rule, say
-- so and I'll add gold_teacher_21c_summary alongside this one.

WITH action_counts_per_observation AS (

    SELECT
        submission_id,
        classroom_uid,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        COUNT(DISTINCT indicator_code) AS n_sv_actions
    FROM {{ ref('gold_svi_indicator_responses') }}
    WHERE is_sv_aligned_teacher_action
    GROUP BY submission_id, classroom_uid, teacher_uid, academic_cycle, academic_quarter

),

observation_flags AS (

    SELECT
        submission_id,
        classroom_uid,
        teacher_uid,
        academic_cycle,
        academic_quarter,
        COALESCE(n_sv_actions, 0) AS n_sv_actions,
        COALESCE(n_sv_actions, 0) >= 5 AS is_21c_integrated_observation
    FROM action_counts_per_observation

),

classroom_period_obs AS (

    SELECT DISTINCT
        classroom_uid,
        academic_cycle,
        academic_quarter,
        submission_id
    FROM {{ ref('gold_svi_indicator_responses') }}

)

SELECT
    o.classroom_uid,
    o.academic_cycle,
    o.academic_quarter,
    COUNT(DISTINCT o.submission_id) AS n_observations,
    COUNTIF(f.is_21c_integrated_observation) AS n_21c_integrated_observations,
    LOGICAL_OR(COALESCE(f.is_21c_integrated_observation, FALSE)) AS is_21c_integrated
FROM classroom_period_obs AS o
LEFT JOIN observation_flags AS f
    ON o.submission_id = f.submission_id
    AND o.classroom_uid = f.classroom_uid
GROUP BY o.classroom_uid, o.academic_cycle, o.academic_quarter
