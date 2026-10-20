{{ config(
    materialized='table',
    schema='silver',
    alias='fct_safety_actions'
) }}

WITH source AS (
    SELECT
        submission_id,
        safety_level,
        safety_actions_raw
    FROM {{ ref('br_safety') }}
    WHERE submission_id IS NOT NULL
)

SELECT
    submission_id,
    safety_level,
    TRIM(action_code) AS safety_action
FROM source,
UNNEST(
    SPLIT(
        REGEXP_REPLACE(
            COALESCE(safety_actions_raw, ''),
            r'\s+',
            ' '
        ),
        ' '
    )
) AS action_code
WHERE TRIM(action_code) != ''
