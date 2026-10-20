{{ config(
    materialized='table',
    schema='gold',
    alias='svi_indicator_responses'
) }}

-- Grain: one row per observation submission x classroom code (via the
-- classroom bridge) x SVI indicator group x code.
-- indicator_group in ('co_indicator','ct_indicator','cr_indicator','teacher_action').
--
-- Two different flags for two different pages/metrics - confirmed these
-- are NOT the same rule:
--   is_21c_domain_indicator      -> student-facing co/ct/cr indicators,
--                                    used by SV01-SV05 (21C Skills page)
--   is_sv_aligned_teacher_action -> teacher_action rows whose code is
--                                    prefixed TA_SV_ (excludes the
--                                    'none' placeholder), used by IM04
--                                    ("Teachers integrating 21C skills",
--                                    >=5 per observation) and also maps
--                                    onto the 6E lesson stages (Evoke/
--                                    Explore/Explain/Extend/Embody/
--                                    Evaluate) once blended with the 6E
--                                    codebook in Looker Studio - SV07/SV08.

SELECT
    cb.submission_id,
    cb.observation_date,
    cb.academic_cycle,
    cb.academic_quarter,
    cb.calendar_year,
    cb.school_name,
    cb.school_key,
    cb.classroom_uid,
    cb.teacher_uid,
    cb.teaching_type,
    cb.program_name,

    v.indicator_group,
    v.indicator_code,
    v.indicator_group IN ('co_indicator', 'ct_indicator', 'cr_indicator') AS is_21c_domain_indicator,
    (v.indicator_group = 'teacher_action'
        AND v.indicator_code != 'none'
        AND v.indicator_code LIKE 'TA\\_SV\\_%') AS is_sv_aligned_teacher_action
FROM {{ ref('gold_observation_classroom_bridge') }} AS cb
INNER JOIN {{ ref('fct_svi_indicators') }} AS v
    ON cb.submission_id = v.submission_id
