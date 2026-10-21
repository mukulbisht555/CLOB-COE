
{{ config(
    materialized='table',
    schema='silver',
    alias='tl_fct_teacher_touchpoints'
) }}

WITH source_data AS (

    SELECT *
    FROM {{ ref('tl_br_observations') }}

),

touchpoints AS (

    SELECT
        b.submission_id,

        tp.touchpoint,
        tp.other_touchpoint_type,
        tp.subject,
        tp.objective,
        tp.rating AS rating_raw,

        COALESCE(
            SAFE_CAST(NULLIF(TRIM(tp.rating), '') AS INT64),
            CASE LOWER(TRIM(tp.rating))
                WHEN 'not effective at all' THEN 1
                WHEN 'somewhat effective' THEN 2
                WHEN 'effective' THEN 3
                WHEN 'very effective' THEN 4
                ELSE NULL
            END
        ) AS rating,

        tp.evidence

    FROM source_data AS b

    CROSS JOIN UNNEST([

        STRUCT(
            'Co-teaching' AS touchpoint,
            CAST(NULL AS STRING) AS other_touchpoint_type,
            b.co_teaching_subject AS subject,
            b.co_teaching_objective AS objective,
            b.co_teaching_rating AS rating,
            b.co_teaching_evidence AS evidence
        ),

        STRUCT(
            'Co-planning' AS touchpoint,
            CAST(NULL AS STRING) AS other_touchpoint_type,
            b.co_planning_subject AS subject,
            b.co_planning_objective AS objective,
            b.co_planning_rating AS rating,
            b.co_planning_evidence AS evidence
        ),

        STRUCT(
            'Modelling' AS touchpoint,
            CAST(NULL AS STRING) AS other_touchpoint_type,
            b.modelling_subject AS subject,
            b.modelling_objective AS objective,
            b.modelling_rating AS rating,
            b.modelling_evidence AS evidence
        ),

        STRUCT(
            'Debrief' AS touchpoint,
            CAST(NULL AS STRING) AS other_touchpoint_type,
            b.debrief_subject AS subject,
            b.debrief_objective AS objective,
            b.debrief_rating AS rating,
            b.debrief_evidence AS evidence
        ),

        STRUCT(
            'Training Workshop' AS touchpoint,
            CAST(NULL AS STRING) AS other_touchpoint_type,
            b.training_workshop_subject AS subject,
            b.training_workshop_objective AS objective,
            b.training_workshop_rating AS rating,
            b.training_workshop_evidence AS evidence
        ),

        STRUCT(
            'Other' AS touchpoint,
            b.other_touchpoint_type AS other_touchpoint_type,
            b.other_subject AS subject,
            b.other_objective AS objective,
            b.other_rating AS rating,
            b.other_evidence AS evidence
        )

    ]) AS tp

    WHERE REGEXP_CONTAINS(
        LOWER(COALESCE(b.coaching_touchpoints, '')),
        CASE tp.touchpoint
            WHEN 'Co-teaching' THEN
                r'(^|[\s,])co[-_ ]?teaching($|[\s,])'
            WHEN 'Co-planning' THEN
                r'(^|[\s,])co[-_ ]?planning($|[\s,])'
            WHEN 'Modelling' THEN
                r'(^|[\s,])modelling($|[\s,])'
            WHEN 'Debrief' THEN
                r'(^|[\s,])debrief($|[\s,])'
            WHEN 'Training Workshop' THEN
                r'(^|[\s,])training[-_ ]workshop($|[\s,])'
            WHEN 'Other' THEN
                r'(^|[\s,])other($|[\s,])'
        END
    )

)

SELECT
    t.submission_id,

    l.observation_date,
    l.coach_name,
    l.school_name,
    l.classroom_name,
    l.teacher_name,
    l.classroom_type,

    t.touchpoint,
    NULLIF(TRIM(t.other_touchpoint_type), '') AS other_touchpoint_type,
    NULLIF(TRIM(t.subject), '') AS subject,
    NULLIF(TRIM(t.objective), '') AS objective,

    t.rating,
    t.rating_raw,

    NULLIF(TRIM(t.evidence), '') AS evidence

FROM touchpoints AS t

LEFT JOIN {{ ref('tl_fct_teacher_log') }} AS l
    ON t.submission_id = l.submission_id