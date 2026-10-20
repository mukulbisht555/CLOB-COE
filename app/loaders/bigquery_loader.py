"""
bigquery_loader.py

Loads KoboToolbox submissions into BigQuery.

Design notes
------------
- The destination table's schema is defined explicitly (TABLE_SCHEMA) so
  BigQuery never silently trusts a stale or auto-detected schema - this was
  the root cause of an earlier "No such field: submission_id" load failure.
- The dataset and table are created automatically on first run if missing.
- "No duplicates" is achieved via a watermark: get_watermark() reads
  MAX(submission_id) directly from BigQuery before each run. There is no
  local checkpoint file anywhere in this project - BigQuery itself is the
  single source of truth for "what has already been loaded", so the
  pipeline stays fully stateless and safe to run from a fresh container
  every time.
- _filter_new_rows() is a second, defensive layer of dedup: even if rows
  are ever passed in without going through the incremental extractor (e.g.
  a manual backfill), anything at/below the watermark is still skipped.
- The full Kobo submission is stored untouched in the `data` column; dbt's
  bronze models parse it with JSON_VALUE. `submission_id` and
  `submission_date` are only promoted for the watermark and partitioning.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from google.api_core.exceptions import GoogleAPIError, NotFound
from google.cloud import bigquery
from google.oauth2 import service_account

from app.config.settings import settings
from app.utils.errors import LoadError
from app.utils.logger import get_logger

logger = get_logger(__name__)

# Explicit schema - the single source of truth for this table.
# submission_id maps to Kobo's `_id` (a sequential integer), which also
# doubles as the incremental watermark used throughout the pipeline.
TABLE_SCHEMA = [
    bigquery.SchemaField("submission_id", "INTEGER", mode="REQUIRED"),
    bigquery.SchemaField("submission_date", "TIMESTAMP", mode="NULLABLE"),
    bigquery.SchemaField("data", "STRING", mode="NULLABLE"),  # raw submission JSON, as a string
    bigquery.SchemaField("_loaded_at", "TIMESTAMP", mode="NULLABLE"),
]


class BigQueryLoader:
    """
    Handles table setup, watermark lookups, and loading rows into BigQuery
    for a single destination table.

    One instance = one table. This pipeline creates one BigQueryLoader per
    configured Kobo source (see app.config.settings.Settings.get_sources()
    and app/main.py) - project, dataset, location, and credentials are
    shared across all of them (same BigQuery project/dataset), only
    `table_id` differs.
    """

    def __init__(self, table_id: str) -> None:
        if not table_id:
            raise LoadError("BigQueryLoader requires a non-empty table_id")

        self.project_id = settings.BIGQUERY_PROJECT_ID
        self.dataset_id = settings.get_bigquery_dataset_id()
        self.table_id = table_id
        self.location = settings.BIGQUERY_LOCATION
        self._client: Optional[bigquery.Client] = None
        self._table_ready = False

    @property
    def client(self) -> bigquery.Client:
        """Lazily build (and cache) the BigQuery client."""
        if self._client is None:
            credentials_file = settings.get_bigquery_credentials_file()
            if credentials_file:
                credentials = service_account.Credentials.from_service_account_file(credentials_file)
                self._client = bigquery.Client(
                    project=self.project_id, credentials=credentials, location=self.location
                )
            else:
                # Falls back to Application Default Credentials, e.g. when
                # running on GCP infrastructure that already has an identity.
                self._client = bigquery.Client(project=self.project_id, location=self.location)
        return self._client

    @property
    def full_table_name(self) -> str:
        return f"{self.project_id}.{self.dataset_id}.{self.table_id}"

    @property
    def table_ref(self) -> bigquery.TableReference:
        dataset_ref = bigquery.DatasetReference(self.project_id, self.dataset_id)
        return dataset_ref.table(self.table_id)

    def ensure_table_exists(self) -> None:
        """
        Create the dataset and/or table if either doesn't exist yet.

        Safe to call repeatedly: after the first successful check the result
        is cached for the life of this loader, so later calls cost nothing.
        """
        if self._table_ready:
            return
        if not self.project_id or not self.dataset_id or not self.table_id:
            raise LoadError("BigQuery configuration is incomplete")

        dataset_ref = bigquery.DatasetReference(self.project_id, self.dataset_id)

        try:
            try:
                self.client.get_dataset(dataset_ref)
            except NotFound:
                logger.info("Dataset '%s' not found, creating it", self.dataset_id)
                dataset = bigquery.Dataset(dataset_ref)
                dataset.location = self.location
                self.client.create_dataset(dataset, exists_ok=True)

            try:
                self.client.get_table(self.table_ref)
            except NotFound:
                logger.info("Table '%s' not found, creating it", self.table_id)
                table = bigquery.Table(self.table_ref, schema=TABLE_SCHEMA)
                table.time_partitioning = bigquery.TimePartitioning(
                    type_=bigquery.TimePartitioningType.DAY,
                    field="submission_date",
                )
                table.clustering_fields = ["submission_id"]
                self.client.create_table(table, exists_ok=True)
        except GoogleAPIError as exc:
            raise LoadError(f"Could not prepare BigQuery table {self.full_table_name}: {exc}") from exc

        self._table_ready = True

    def get_watermark(self) -> Optional[int]:
        """
        Return the highest submission_id already loaded, or None if the
        table doesn't exist yet or is still empty (first run).

        This single value is used both to ask Kobo for only new
        submissions, and to filter out anything already loaded.
        """
        query = f"SELECT MAX(submission_id) AS max_submission_id FROM `{self.full_table_name}`"
        try:
            result = list(self.client.query(query).result())
        except NotFound:
            return None
        except GoogleAPIError as exc:
            raise LoadError(f"Could not read watermark from {self.full_table_name}: {exc}") from exc

        if not result or result[0].max_submission_id is None:
            return None
        return int(result[0].max_submission_id)

    @staticmethod
    def _normalize_rows(rows: List[Dict[str, Any]], loaded_at: str) -> List[Dict[str, Any]]:
        """Convert raw Kobo submission dicts into rows matching TABLE_SCHEMA."""
        normalized_rows: List[Dict[str, Any]] = []
        for row in rows:
            try:
                submission_id = int(row["_id"])
            except (KeyError, TypeError, ValueError):
                logger.warning("Skipping row with missing/non-numeric _id: %s", row.get("_id"))
                continue

            normalized_rows.append(
                {
                    "submission_id": row.get("_id"),
                    # Kobo v2 exposes the submission timestamp as `_submission_time`
                    # (UTC, no offset) - the same field the dbt bronze models read.
                    "submission_date": row.get("_submission_time"),
                    "data": json.dumps(row, ensure_ascii=False),
                    "_loaded_at": loaded_at,
                }
            )
        return normalized_rows

    @staticmethod
    def _filter_new_rows(
        normalized_rows: List[Dict[str, Any]], watermark: Optional[int]
    ) -> List[Dict[str, Any]]:
        """Defensive second layer of dedup: drop anything at/below the watermark."""
        if watermark is None:
            return normalized_rows
        return [row for row in normalized_rows if row["submission_id"] > watermark]

    def load_rows(self, rows: List[Dict[str, Any]], watermark: Optional[int] = None) -> int:
        """
        Normalize, dedupe, and load one batch of submissions into BigQuery.

        Parameters
        ----------
        rows:
            Raw Kobo submissions, e.g. one page from KoboExtractor.iter_pages().
        watermark:
            The value from get_watermark() taken before extraction started.
            Rows with a submission_id at or below it are skipped. Pass None
            when the table is empty (no filtering is applied).

        Returns
        -------
        int
            Number of rows actually inserted.
        """
        if not rows:
            logger.info("No rows to load")
            return 0

        self.ensure_table_exists()

        loaded_at = datetime.now(timezone.utc).isoformat()
        new_rows = self._filter_new_rows(self._normalize_rows(rows, loaded_at), watermark)

        if not new_rows:
            logger.info("No new rows to load (watermark: %s)", watermark)
            return 0

        job_config = bigquery.LoadJobConfig(
            schema=TABLE_SCHEMA,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        )

        try:
            load_job = self.client.load_table_from_json(new_rows, self.table_ref, job_config=job_config)
            load_job.result()  # blocks; raises on any job failure
        except GoogleAPIError as exc:
            raise LoadError(f"BigQuery load job into {self.full_table_name} failed: {exc}") from exc

        logger.info("Loaded %d new row(s) into %s (watermark was: %s)", len(new_rows), self.full_table_name, watermark)
        return len(new_rows)
