{{ config(
    materialized='table',
    schema='gold',
    alias='math_indicator_responses'
) }}

-- Grain: one row per observation submission x math indicator code
-- (math_cc_1..5, math_psr_1..8, math_tr_1..7, math_gm1..2).
-- math_domain is parsed from the indicator_code prefix: cc, psr, tr, gm.
-- indicator_value is a confirmed 5-value scale:
-- notyet / somewhat / mostly / vproficient / na.
-- Feeds gold_teacher_math_summary (IM02 KPI + trend, FL08-FL11, FL12, FL13).

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
    b.program_name,

    m.indicator_code,
    REGEXP_EXTRACT(m.indicator_code, r'^math_([a-z]+)') AS math_domain,
    m.indicator_value AS indicator_value_raw,
    CASE m.indicator_value
        WHEN 'notyet' THEN 1
        WHEN 'somewhat' THEN 2
        WHEN 'mostly' THEN 3
        WHEN 'vproficient' THEN 4
        ELSE NULL -- 'na' (not applicable) has no rank
    END AS indicator_rating_rank,
    m.indicator_value IN ('mostly', 'vproficient') AS is_mostly_or_vproficient,
    m.indicator_value = 'na' AS is_not_applicable
FROM {{ ref('gold_observation_base') }} AS b
INNER JOIN {{ ref('fct_math_indicators') }} AS m
    ON b.submission_id = m.submission_id
