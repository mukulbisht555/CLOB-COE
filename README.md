# KoboToolbox -> BigQuery ELT Pipeline

Extracts submissions from a KoboToolbox form and loads them into BigQuery,
incrementally and without duplicates.

## How incremental loading works

KoboToolbox's `_id` field is a sequential integer assigned to each
submission. Instead of re-downloading every submission on every run, this
pipeline:

1. Asks BigQuery for `MAX(submission_id)` already loaded (the "watermark").
2. Asks Kobo for only submissions with `_id` greater than that watermark
   (`query={"_id":{"$gt": watermark}}`, sorted ascending), paginating until
   there's nothing left.
3. Loads only those rows into BigQuery.

There is **no local checkpoint file anywhere in this project.** The
watermark is read fresh from BigQuery at the start of every run, so the
pipeline is fully stateless between runs - the container can be destroyed
and recreated at any time with no risk of losing track of progress or
re-loading duplicate data. A second, defensive filter also runs inside the
loader itself in case rows are ever passed in without going through the
incremental extractor (e.g. a manual backfill).

## Project layout

```
app/
  main.py                    # orchestrates one extract -> load run
  config/settings.py         # environment-driven configuration
  extractors/kobo_extractor.py  # incremental Kobo API extraction
  loaders/bigquery_loader.py    # schema, table creation, dedup, load
  utils/errors.py            # ConfigError / ExtractionError / LoadError
  utils/logger.py            # console + file logging setup
dbt/
  dbt_project.yml            # dbt transformation project
  profiles.yml               # local dbt BigQuery profile
  models/
    sources.yml              # raw BigQuery source table
    bronze/                  # bronze dataset models
    silver/                  # silver dataset models
    gold/                    # gold dataset models
  macros/generate_schema_name.sql # keeps dataset names exactly bronze/silver/gold
```

## Running locally

```bash
cp .env.example .env   # fill in your real values
docker compose up --build
```

`docker compose up --build` runs both steps inside the `clob-coe` container:
first the Python loader, then dbt if the load step succeeds.

## Running dbt transformations

The dbt project builds three BigQuery datasets:

- `bronze` - deduplicated raw Kobo submissions with typed loader metadata.
- `silver` - cleaned submissions with common Kobo metadata promoted to columns.
- `gold` - reporting marts, currently a daily submission summary.

The Python loader still owns the raw table. dbt reads that table through
`dbt/models/sources.yml` and writes the modeled layers into the exact BigQuery
datasets above.

Build the Docker image after the new dbt dependency is installed:

```bash
docker compose build
```

Then run dbt from the same container and `.env` configuration:

```bash
docker compose run --rm clob-coe dbt debug --project-dir dbt --profiles-dir dbt
docker compose run --rm clob-coe dbt build --project-dir dbt --profiles-dir dbt
```

If your raw source table uses the environment-specific variables
`LOCAL_BIGQUERY_*` or `PROD_BIGQUERY_*`, dbt can read the local values
automatically. For production or any custom source, set these explicit dbt
overrides in `.env`:

```bash
DBT_TARGET=prod
DBT_RAW_PROJECT=your-gcp-project
DBT_RAW_DATASET=your_raw_dataset
DBT_RAW_TABLE=your_raw_table
DBT_BIGQUERY_KEYFILE=/app/secrets/local-service-account.json
```

## Configuration

See `.env.example` for the full list of environment variables. Notable ones:

- `KOBOTOOLBOX_PAGE_SIZE` - submissions requested per page (default 500).
- `LOCAL_BIGQUERY_*` / `PROD_BIGQUERY_*` - environment-specific dataset,
  table, and credentials overrides, selected automatically based on
  `APP_ENV`.

## Error handling

Three exception types (`ConfigError`, `ExtractionError`, `LoadError`) let
`main.py` react appropriately to each failure category:

- `ConfigError` - printed to stderr immediately (logging may not be
  configured yet), then a non-zero exit.
- `ExtractionError` / `LoadError` - logged with a full traceback via the
  configured logger, then a non-zero exit.
- Any other unexpected exception is still caught, logged, and reported as
  a failure rather than crashing silently.

`main.py` exits `0` on success and `1` on any failure, so it can be wired
into cron, CI, or an orchestrator's retry/alerting logic.

## Possible next steps

- A pytest suite mocking `requests` and the BigQuery SDK.
- Form-specific silver/gold models once the Kobo questionnaire fields are
  finalized.
