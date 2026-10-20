{#
    Academic-year / quarter helpers.

    ASSUMPTION (please confirm): CoE Delhi runs an April -> March academic
    cycle, e.g. an observation on 2025-06-15 falls in cycle "2025-26",
    Q1 = Apr-Jun, Q2 = Jul-Sep, Q3 = Oct-Dec, Q4 = Jan-Mar.

    If the real program cycle differs (e.g. calendar year, or a different
    quarter start), only these two macros need to change - every gold
    model inherits the definition from gold_observation_base.
#}

{% macro academic_cycle_label(date_column) -%}
    CASE
        WHEN {{ date_column }} IS NULL THEN NULL
        WHEN EXTRACT(MONTH FROM {{ date_column }}) >= 4
            THEN CONCAT(
                CAST(EXTRACT(YEAR FROM {{ date_column }}) AS STRING),
                '-',
                SUBSTR(CAST(EXTRACT(YEAR FROM {{ date_column }}) + 1 AS STRING), 3, 2)
            )
        ELSE CONCAT(
            CAST(EXTRACT(YEAR FROM {{ date_column }}) - 1 AS STRING),
            '-',
            SUBSTR(CAST(EXTRACT(YEAR FROM {{ date_column }}) AS STRING), 3, 2)
        )
    END
{%- endmacro %}

{% macro academic_quarter_label(date_column) -%}
    CASE
        WHEN {{ date_column }} IS NULL THEN NULL
        WHEN EXTRACT(MONTH FROM {{ date_column }}) IN (4, 5, 6) THEN 'Q1'
        WHEN EXTRACT(MONTH FROM {{ date_column }}) IN (7, 8, 9) THEN 'Q2'
        WHEN EXTRACT(MONTH FROM {{ date_column }}) IN (10, 11, 12) THEN 'Q3'
        WHEN EXTRACT(MONTH FROM {{ date_column }}) IN (1, 2, 3) THEN 'Q4'
    END
{%- endmacro %}
