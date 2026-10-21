{{ config(
    materialized='table',
    schema='bronze',
    alias='tl_br_touchpoints'
) }}

SELECT
    SAFE_CAST(JSON_VALUE(data, '$._id') AS INT64) AS submission_id,

    -- Retain source payload for debugging
    data AS raw_data,

    -- General submission details
    JSON_VALUE(data, '$."intro_block/coach_name"') AS coach_name,
    JSON_VALUE(data, '$."intro_block/Date_for_which_you_are_filling"') AS submission_date,
    JSON_VALUE(data, '$."intro_block/school_code"') AS school_name,
    JSON_VALUE(data, '$."intro_block/classroom_name"') AS classroom_name,
    JSON_VALUE(data, '$."intro_block/teacher_name"') AS teacher_name,
    JSON_VALUE(data, '$."intro_block/classroom_type"') AS classroom_type,

    -- Teaching Learning Materials
    JSON_VALUE(data, '$."group_jq5ju35/tlm_check"') AS tlm_introduced,
    JSON_VALUE(data, '$."group_jq5ju35/tlm_list"') AS tlm_types,
    {# JSON_VALUE(data, '$."group_jq5ju35/name_tlm"') AS tlm_name, #}

    -- Selected coaching touchpoints
    JSON_VALUE(
        data,
        '$."group_jq5ju35/coaching_touchpoints"'
    ) AS coaching_touchpoints,

    -- Co-teaching
    JSON_VALUE(data, '$."group_jq5ju35/co-teaching_block/subject_co_teaching"') AS co_teaching_subject,
    JSON_VALUE(data, '$."group_jq5ju35/co-teaching_block/co-teaching_objective"') AS co_teaching_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/co-teaching_block/co-teaching_rating"') AS INT64) AS co_teaching_rating,
    JSON_VALUE(data, '$."group_jq5ju35/co-teaching_block/co-teaching_evidence"') AS co_teaching_evidence,

    -- Co-planning
    JSON_VALUE(data, '$."group_jq5ju35/co-planning_block/subject"') AS co_planning_subject,
    JSON_VALUE(data, '$."group_jq5ju35/co-planning_block/co-planning_objective"') AS co_planning_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/co-planning_block/co-planning_rating"') AS INT64) AS co_planning_rating,
    JSON_VALUE(data, '$."group_jq5ju35/co-planning_block/co-planning_evidence"') AS co_planning_evidence,

    -- Modelling
    JSON_VALUE(data, '$."group_jq5ju35/modelling_block/subject_001"') AS modelling_subject,
    JSON_VALUE(data, '$."group_jq5ju35/modelling_block/modelling_objective"') AS modelling_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/modelling_block/modelling_rating"') AS INT64) AS modelling_rating,
    JSON_VALUE(data, '$."group_jq5ju35/modelling_block/modelling_evidence"') AS modelling_evidence,

    -- Debrief
    JSON_VALUE(data, '$."group_jq5ju35/debrief_block/subject_002"') AS debrief_subject,
    JSON_VALUE(data, '$."group_jq5ju35/debrief_block/debrief_objective"') AS debrief_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/debrief_block/debrief_rating"') AS INT64) AS debrief_rating,
    JSON_VALUE(data, '$."group_jq5ju35/debrief_block/debrief_evidence"') AS debrief_evidence,

    -- Training workshop
    JSON_VALUE(data, '$."group_jq5ju35/training_workshop_block/subject_003"') AS training_workshop_subject,
    JSON_VALUE(data, '$."group_jq5ju35/training_workshop_block/trainingworkshop_block_001"') AS training_workshop_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/training_workshop_block/training_workshop_rating"') AS INT64) AS training_workshop_rating,
    JSON_VALUE(data, '$."group_jq5ju35/training_workshop_block/training_workshop_evidence"') AS training_workshop_evidence,

    -- Other
    JSON_VALUE(data, '$."group_jq5ju35/other_block/other_name"') AS other_touchpoint_type,
    JSON_VALUE(data, '$."group_jq5ju35/other_block/subject_004"') AS other_subject,
    JSON_VALUE(data, '$."group_jq5ju35/other_block/What_was_the_objecti_coaching_touchpoint"') AS other_objective,
     SAFE_CAST(JSON_VALUE(data, '$."group_jq5ju35/other_block/How_effectively_was_this_objective_met"') AS INT64) AS other_rating,
    JSON_VALUE(data, '$."group_jq5ju35/other_block/Share_evidence_for_y_were_the_challenges"') AS other_evidence

FROM {{ source('raw', 'teacher_submissions') }}

WHERE JSON_VALUE(data, '$._id') IS NOT NULL
