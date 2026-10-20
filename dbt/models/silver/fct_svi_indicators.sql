{{ config(
    materialized='table',
    schema='silver',
    alias='fct_svi_indicators'
) }}

WITH source AS (
    SELECT
        submission_id,
        svi_co_indicators_raw,
        svi_ct_indicators_raw,
        svi_cr_indicators_raw,
        svi_teacher_actions_raw
    FROM {{ ref('br_svi') }}
    WHERE submission_id IS NOT NULL
)

SELECT
    submission_id,
    'co_indicator' AS indicator_group,
    TRIM(code) AS indicator_code
FROM source,
UNNEST(
    SPLIT(
        REGEXP_REPLACE(
            COALESCE(svi_co_indicators_raw, ''),
            r'\s+',
            ' '
        ),
        ' '
    )
) AS code
WHERE TRIM(code) != ''

UNION ALL

SELECT
    submission_id,
    'ct_indicator' AS indicator_group,
    TRIM(code) AS indicator_code
FROM source,
UNNEST(
    SPLIT(
        REGEXP_REPLACE(
            COALESCE(svi_ct_indicators_raw, ''),
            r'\s+',
            ' '
        ),
        ' '
    )
) AS code
WHERE TRIM(code) != ''

UNION ALL

SELECT
    submission_id,
    'cr_indicator' AS indicator_group,
    TRIM(code) AS indicator_code
FROM source,
UNNEST(
    SPLIT(
        REGEXP_REPLACE(
            COALESCE(svi_cr_indicators_raw, ''),
            r'\s+',
            ' '
        ),
        ' '
    )
) AS code
WHERE TRIM(code) != ''

UNION ALL

SELECT
    submission_id,
    'teacher_action' AS indicator_group,
    TRIM(code) AS indicator_code
FROM source,
UNNEST(
    SPLIT(
        REGEXP_REPLACE(
            COALESCE(svi_teacher_actions_raw, ''),
            r'\s+',
            ' '
        ),
        ' '
    )
) AS code
WHERE TRIM(code) != ''
