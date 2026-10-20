{{ config(
    materialized='table',
    schema='silver',
    alias='fct_math_indicators'
) }}

WITH source AS (

    SELECT
        submission_id,

        math_cc_1,
        math_cc_2,
        math_cc_3,
        math_cc_4,
        math_cc_5,

        math_psr_1,
        math_psr_2,
        math_psr_3,
        math_psr_4,
        math_psr_5,
        math_psr_6,
        math_psr_7,
        math_psr_8,

        math_tr_1,
        math_tr_2,
        math_tr_3,
        math_tr_4,
        math_tr_5,
        math_tr_6,
        math_tr_7,

        math_gm1,
        math_gm2

    FROM {{ ref('br_math') }}

    WHERE submission_id IS NOT NULL

),

unpivoted AS (

    SELECT
        submission_id,
        indicator_code,
        indicator_value

    FROM source

    UNPIVOT (
        indicator_value FOR indicator_code IN (

            math_cc_1,
            math_cc_2,
            math_cc_3,
            math_cc_4,
            math_cc_5,

            math_psr_1,
            math_psr_2,
            math_psr_3,
            math_psr_4,
            math_psr_5,
            math_psr_6,
            math_psr_7,
            math_psr_8,

            math_tr_1,
            math_tr_2,
            math_tr_3,
            math_tr_4,
            math_tr_5,
            math_tr_6,
            math_tr_7,

            math_gm1,
            math_gm2

        )
    )

)

SELECT
    submission_id,
    indicator_code,
    indicator_value

FROM unpivoted

WHERE indicator_value IS NOT NULL