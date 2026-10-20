{{ config(
    materialized='table',
    schema='bronze',
    alias='br_math'
) }}

{# SELECT

    -- Stable linkage key
    SAFE_CAST(
        JSON_VALUE(data, '$._id')
        AS INT64
    ) AS submission_id,

    -- Math lesson/domain
    JSON_VALUE(
        data,
        '$."math_block/math_lesson"'
    ) AS math_lesson,

    -- Context & Connections
    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_1"'
    ) AS math_cc_1,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_2"'
    ) AS math_cc_2,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_3"'
    ) AS math_cc_3,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_4"'
    ) AS math_cc_4,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_5"'
    ) AS math_cc_5,

    -- Problem Solving & Reasoning
    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_1"'
    ) AS math_psr_1,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_2"'
    ) AS math_psr_2,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_3"'
    ) AS math_psr_3,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_4"'
    ) AS math_psr_4,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_5"'
    ) AS math_psr_5,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_6"'
    ) AS math_psr_6,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_7"'
    ) AS math_psr_7,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_8"'
    ) AS math_psr_8,

    -- Tools & Representations
    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_yn"'
    ) AS math_tr_yn,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_names"'
    ) AS math_tr_names,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_1"'
    ) AS math_tr_1,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_2"'
    ) AS math_tr_2,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_3"'
    ) AS math_tr_3,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_4"'
    ) AS math_tr_4,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_5"'
    ) AS math_tr_5,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_6"'
    ) AS math_tr_6,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_7"'
    ) AS math_tr_7,

    -- Growth Mindset
    JSON_VALUE(
        data,
        '$."math_block/math_gm/math_gm1"'
    ) AS math_gm1,

    JSON_VALUE(
        data,
        '$."math_block/math_gm/math_gm2"'
    ) AS math_gm2

FROM {{ source('raw', 'submissions') }}

WHERE
    JSON_VALUE(data, '$._id') IS NOT NULL

    -- Keep ONLY Math observations
    AND LOWER(
        JSON_VALUE(
            data,
            '$."fl_block/subject_observed"'
        )
    ) = 'math' #}

    {# {{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='submission_id',
    on_schema_change='append_new_columns',
    schema='bronze',
    alias='br_math'
) }} #}

SELECT

    -- Stable linkage key
    SAFE_CAST(
        JSON_VALUE(data, '$._id')
        AS INT64
    ) AS submission_id,

    -- Math lesson/domain
    JSON_VALUE(
        data,
        '$."math_block/math_lesson"'
    ) AS math_lesson,

    -- Context & Connections
    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_1"'
    ) AS math_cc_1,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_2"'
    ) AS math_cc_2,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_3"'
    ) AS math_cc_3,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_4"'
    ) AS math_cc_4,

    JSON_VALUE(
        data,
        '$."math_block/math_cc/math_cc_5"'
    ) AS math_cc_5,

    -- Problem Solving & Reasoning
    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_1"'
    ) AS math_psr_1,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_2"'
    ) AS math_psr_2,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_3"'
    ) AS math_psr_3,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_4"'
    ) AS math_psr_4,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_5"'
    ) AS math_psr_5,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_6"'
    ) AS math_psr_6,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_7"'
    ) AS math_psr_7,

    JSON_VALUE(
        data,
        '$."math_block/math_psr/math_psr_8"'
    ) AS math_psr_8,

    -- Tools & Representations
    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_yn"'
    ) AS math_tr_yn,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_names"'
    ) AS math_tr_names,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_1"'
    ) AS math_tr_1,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_2"'
    ) AS math_tr_2,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_3"'
    ) AS math_tr_3,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_4"'
    ) AS math_tr_4,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_5"'
    ) AS math_tr_5,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_6"'
    ) AS math_tr_6,

    JSON_VALUE(
        data,
        '$."math_block/math_tr/math_tr_7"'
    ) AS math_tr_7,

    -- Growth Mindset
    JSON_VALUE(
        data,
        '$."math_block/math_gm/math_gm1"'
    ) AS math_gm1,

    JSON_VALUE(
        data,
        '$."math_block/math_gm/math_gm2"'
    ) AS math_gm2

FROM {{ source('raw', 'observation_submissions') }} AS src

WHERE
    JSON_VALUE(data, '$._id') IS NOT NULL
    {# AND {{ new_submissions_only('src.submission_id') }} #}

    -- Keep ONLY Math observations
    AND LOWER(
        JSON_VALUE(
            data,
            '$."fl_block/subject_observed"'
        )
    ) = 'math'