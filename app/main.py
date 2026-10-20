"""
main.py

Entry point for the KoboToolbox -> BigQuery ELT pipeline.

Pipeline flow (per configured source - see app.config.settings.Settings.
get_sources(), currently CLOB-COE classroom observations and the Teacher
Submission form)
-------------------------------------------------------------------------
1. Validate configuration - fail fast if anything required is missing,
   across every configured source, before touching the network at all.
2. For each source, independently:
   a. Ensure that source's destination BigQuery table exists.
   b. Read the current watermark (MAX(submission_id)) from that table.
      This is the pipeline's only "memory" of what's already been loaded
      for that source - nothing is persisted locally, so the container
      can be recreated at any time with no risk of losing state or
      reloading duplicates.
   c. Stream only submissions newer than that watermark from that
      source's Kobo form, one page at a time.
   d. Load each page into that source's table as it arrives (a second,
      defensive dedup check also happens inside the loader). If a run
      dies part-way, the pages already loaded are kept and the next run
      resumes from the new watermark.
3. Every source is attempted even if an earlier one fails, so one form
   being unreachable doesn't block loading the other. The process exits
   non-zero if *any* source failed, so a scheduler/orchestrator (or the
   `&& dbt build` step in docker-compose) correctly treats a partial
   failure as "this run needs attention" - even though the sources that
   did succeed are already safely committed in BigQuery.
"""

from __future__ import annotations

import sys
import time

from app.config.settings import SourceConfig, settings
from app.extractors.kobo_extractor import KoboExtractor
from app.loaders.bigquery_loader import BigQueryLoader
from app.utils.errors import ConfigError, ETLError
from app.utils.logger import configure_logging, get_logger

logger = get_logger(__name__)


def run_source(source: SourceConfig) -> None:
    """
    Run one end-to-end extraction + load cycle for a single source.

    Raises ETLError (or a subclass) on failure - the caller decides how to
    aggregate failures across sources, this function only handles one.
    """
    logger.info("Processing source '%s' (Kobo form %s)", source.name, source.kobo_form_id)

    extractor = KoboExtractor(form_id=source.kobo_form_id)
    loader = BigQueryLoader(table_id=source.bigquery_table_id)

    # Prepare BigQuery + read the watermark
    loader.ensure_table_exists()
    watermark = loader.get_watermark()
    logger.info("[%s] Current watermark (last loaded _id): %s", source.name, watermark)

    # Extract only what's new and load it page by page
    fetched = 0
    loaded = 0
    for page in extractor.iter_pages(since_id=watermark):
        fetched += len(page)
        loaded += loader.load_rows(page, watermark=watermark)

    if fetched == 0:
        logger.info("[%s] No new submissions found. Nothing to load.", source.name)
    else:
        logger.info("[%s] Fetched %d and loaded %d new submission(s).", source.name, fetched, loaded)


def run_pipeline() -> int:
    """Run one end-to-end extraction + load cycle for every configured source. Returns a process exit code."""
    start = time.time()

    try:
        # Configuration must be valid before we do anything else, including
        # setting up logging (which reads settings.LOG_LEVEL).
        settings.validate()
        configure_logging(settings.LOG_LEVEL)

        sources = settings.get_sources()

        logger.info(
            "Kobo -> BigQuery ELT pipeline started (env=%s, sources=%s)",
            settings.APP_ENV,
            ", ".join(source.name for source in sources),
        )

        failures: dict[str, Exception] = {}
        for source in sources:
            try:
                run_source(source)
            except ETLError as exc:
                # Log and keep going - a failure in one source (e.g. the
                # Teacher Submission form being temporarily unreachable)
                # should not prevent the other source from being extracted
                # and loaded in the same run.
                logger.exception("[%s] Source failed: %s", source.name, exc)
                failures[source.name] = exc

        elapsed = time.time() - start
        if failures:
            logger.error(
                "Pipeline finished in %.2fs with %d/%d source(s) failing: %s",
                elapsed,
                len(failures),
                len(sources),
                ", ".join(failures.keys()),
            )
            return 1

        logger.info("Pipeline completed successfully in %.2fs", elapsed)
        return 0

    except ConfigError as exc:
        # Configuration errors can happen before logging is configured, so
        # make sure this is visible regardless (stderr, always unbuffered).
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 1

    except Exception as exc:  # noqa: BLE001 - last-resort catch-all, always logged
        logger.exception("Unexpected error: %s", exc)
        return 1


if __name__ == "__main__":
    sys.exit(run_pipeline())
