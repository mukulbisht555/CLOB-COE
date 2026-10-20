{{ config(
    materialized='table',
    schema='silver',
    alias='fct_language_practices'
) }}

-- Grain:
-- One row = one submission_id + one language practice
--            + one selected sub-language practice.

WITH source AS (
    SELECT
        submission_id,
        language_practice_codes,
        oral_sound_codes,
        letter_sound_recognition_codes,
        blending_segmenting_codes,
        reading_fluency_codes,
        vocabulary_practice_codes
        {# speaking_codes,
        writing_codes #}
    FROM {{ ref('br_language') }}
    WHERE submission_id IS NOT NULL
),

language_practices AS (
    SELECT
        submission_id,
        SPLIT(
            REGEXP_REPLACE(
                TRIM(COALESCE(language_practice_codes, '')),
                r'\s+',
                ' '
            ),
            ' '
        ) AS lp_codes,
        oral_sound_codes,
        letter_sound_recognition_codes,
        blending_segmenting_codes,
        reading_fluency_codes,
        vocabulary_practice_codes
        {# speaking_codes,
        writing_codes #}
    FROM source
),

lp1_oral_sound AS (
    SELECT
        submission_id,
        'LP1' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(COALESCE(oral_sound_codes, ''), r'\s+', ' '),
            ' '
        )
    ) AS code
    WHERE 'LP1' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
),

lp2_letter_sound AS (
    SELECT
        submission_id,
        'LP2' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(
                COALESCE(letter_sound_recognition_codes, ''),
                r'\s+',
                ' '
            ),
            ' '
        )
    ) AS code
    WHERE 'LP2' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
),

lp3_blending_segmenting AS (
    SELECT
        submission_id,
        'LP3' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(
                COALESCE(blending_segmenting_codes, ''),
                r'\s+',
                ' '
            ),
            ' '
        )
    ) AS code
    WHERE 'LP3' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
),

lp4_reading_fluency AS (
    SELECT
        submission_id,
        'LP4' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(
                COALESCE(reading_fluency_codes, ''),
                r'\s+',
                ' '
            ),
            ' '
        )
    ) AS code
    WHERE 'LP4' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
),

lp5_none AS (

    SELECT
        submission_id,
        'LP5' AS language_practice,
        CAST(NULL AS STRING) AS sub_language_practice

    FROM language_practices

    WHERE 'LP5' IN UNNEST(lp_codes)

),

lp6_vocabulary AS (
    SELECT
        submission_id,
        'LP6' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(
                COALESCE(vocabulary_practice_codes, ''),
                r'\s+',
                ' '
            ),
            ' '
        )
    ) AS code
    WHERE 'LP6' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
)

{# lp8_speaking AS (
    SELECT
        submission_id,
        'LP8' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(COALESCE(speaking_codes, ''), r'\s+', ' '),
            ' '
        )
    ) AS code
    WHERE 'LP8' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
),

lp9_writing AS (
    SELECT
        submission_id,
        'LP9' AS language_practice,
        TRIM(code) AS sub_language_practice
    FROM language_practices,
    UNNEST(
        SPLIT(
            REGEXP_REPLACE(COALESCE(writing_codes, ''), r'\s+', ' '),
            ' '
        )
    ) AS code
    WHERE 'LP9' IN UNNEST(lp_codes)
      AND TRIM(code) != ''
) #}

SELECT * FROM lp1_oral_sound

UNION ALL
SELECT * FROM lp2_letter_sound

UNION ALL
SELECT * FROM lp3_blending_segmenting

UNION ALL
SELECT * FROM lp4_reading_fluency

UNION ALL
SELECT * FROM lp5_none

UNION ALL
SELECT * FROM lp6_vocabulary

{# UNION ALL
SELECT * FROM lp8_speaking

UNION ALL
SELECT * FROM lp9_writing #}
