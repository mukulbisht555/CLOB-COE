"""
settings.py

Centralized, environment-driven configuration for the KoboToolbox ->
BigQuery ELT pipeline.

Design notes
------------
- Every setting comes from an environment variable (optionally loaded from
  a local .env file). Nothing is hardcoded, and this module never writes
  anything to disk - the pipeline's only persistent "memory" of what's
  already been loaded lives inside BigQuery itself (see
  BigQueryLoader.get_watermark()), not in a local file.
- LOCAL_*/PROD_* overrides let local runs point at a sandbox dataset and
  prod runs at the real one, without duplicating any config logic.
- Nothing in this module can raise at import time: values that need parsing
  (e.g. the page size) are parsed inside validate(), so a bad value surfaces
  as a clean ConfigError instead of a traceback during `import`.
- validate() collects every missing/invalid setting into a single error
  instead of stopping at the first one, so you can fix everything in one
  pass.
- Multi-source support: this pipeline reads from more than one KoboToolbox
  form - CLOB-COE classroom observations, and the Teacher Submission
  (teacher log) form. Each source is just a (name, Kobo form ID,
  destination BigQuery table) triple - see SourceConfig / get_sources().
  Both forms load into the same BigQuery project/dataset (`raw`), under
  different tables, using the same credentials and the same Kobo
  account/token - only the form ID and table name differ per source.
  Adding a third form later means adding one more SourceConfig entry, not
  writing new pipeline code.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import List

from dotenv import load_dotenv

from app.utils.errors import ConfigError

# Load variables from a local .env file if present. Real environment
# variables (e.g. injected by docker-compose's env_file) always take
# precedence, since load_dotenv() does not override already-set variables.
load_dotenv()

VALID_LOG_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}

# Upper bound accepted by the KoboToolbox v2 data endpoint for `limit`.
KOBO_MAX_PAGE_SIZE = 30000


@dataclass(frozen=True)
class SourceConfig:
    """
    One KoboToolbox form -> BigQuery table pairing.

    `name` is only used for logging/readability (e.g. "clob_coe",
    "teacher_submission") - it never touches BigQuery or Kobo directly.
    """

    name: str
    kobo_form_id: str
    bigquery_table_id: str


class Settings:
    """Process-wide configuration, read once from the environment at import time."""

    # -- Environment -------------------------------------------------------
    APP_ENV = os.getenv("APP_ENV", "local").strip().lower()
    IS_PROD = APP_ENV in {"prod", "production"}
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").strip().upper()

    # -- KoboToolbox ---------------------------------------------------------
    KOBOTOOLBOX_API_URL = os.getenv("KOBOTOOLBOX_API_URL", "https://kf.kobotoolbox.org").strip().rstrip("/")
    KOBOTOOLBOX_TOKEN = os.getenv("KOBOTOOLBOX_TOKEN", "").strip()
    # Submissions requested per page. Kept as text here and parsed in
    # get_page_size(), so a typo can't crash the import. Shared across
    # every source - there's no reason to page differently per form.
    _PAGE_SIZE_RAW = os.getenv("KOBOTOOLBOX_PAGE_SIZE", "").strip() or "500"

    # Per-source Kobo form (asset) IDs.
    # KOBO_CLOB_COE_FORM_ID falls back to the old KOBOTOOLBOX_FORM_ID name so
    # an existing .env from before multi-source support still works
    # unchanged - only someone adding the new Teacher Submission source
    # needs to touch their .env at all.
    KOBO_CLOB_COE_FORM_ID = os.getenv("KOBO_CLOB_COE_FORM_ID", os.getenv("KOBOTOOLBOX_FORM_ID", "")).strip()
    KOBO_TEACHER_SUBMISSION_FORM_ID = os.getenv("KOBO_TEACHER_SUBMISSION_FORM_ID", "").strip()

    # -- BigQuery --------------------------------------------------------------
    BIGQUERY_PROJECT_ID = os.getenv("BIGQUERY_PROJECT_ID", "").strip()
    BIGQUERY_LOCATION = os.getenv("BIGQUERY_LOCATION", "US").strip()

    # Dataset and credentials are shared across every source - both forms
    # load into tables within the same raw dataset, using the same
    # service account (or Application Default Credentials).
    BIGQUERY_DATASET_ID = os.getenv("BIGQUERY_DATASET_ID", "").strip()
    BIGQUERY_CREDENTIALS_FILE = os.getenv("BIGQUERY_CREDENTIALS_FILE", "").strip()

    # Per-source destination tables, both in the `raw` dataset.
    # BIGQUERY_CLOB_COE_TABLE_ID falls back to the old BIGQUERY_TABLE_ID name
    # for the same backward-compatibility reason as the form ID above.
    BIGQUERY_CLOB_COE_TABLE_ID = os.getenv(
        "BIGQUERY_CLOB_COE_TABLE_ID", os.getenv("BIGQUERY_TABLE_ID", "observation_submissions")
    ).strip()
    BIGQUERY_TEACHER_SUBMISSION_TABLE_ID = os.getenv(
        "BIGQUERY_TEACHER_SUBMISSION_TABLE_ID", "teacher_submission"
    ).strip()

    # Environment-specific overrides (shared across all sources).
    LOCAL_BIGQUERY_DATASET_ID = os.getenv("LOCAL_BIGQUERY_DATASET_ID", "").strip()
    PROD_BIGQUERY_DATASET_ID = os.getenv("PROD_BIGQUERY_DATASET_ID", "").strip()
    LOCAL_BIGQUERY_CREDENTIALS_FILE = os.getenv("LOCAL_BIGQUERY_CREDENTIALS_FILE", "").strip()
    PROD_BIGQUERY_CREDENTIALS_FILE = os.getenv("PROD_BIGQUERY_CREDENTIALS_FILE", "").strip()

    # -- Resolvers: prefer the environment-specific value, fall back to the shared one --

    @classmethod
    def get_bigquery_dataset_id(cls) -> str:
        env_specific = cls.PROD_BIGQUERY_DATASET_ID if cls.IS_PROD else cls.LOCAL_BIGQUERY_DATASET_ID
        return env_specific or cls.BIGQUERY_DATASET_ID

    @classmethod
    def get_bigquery_credentials_file(cls) -> str:
        env_specific = cls.PROD_BIGQUERY_CREDENTIALS_FILE if cls.IS_PROD else cls.LOCAL_BIGQUERY_CREDENTIALS_FILE
        return env_specific or cls.BIGQUERY_CREDENTIALS_FILE

    @classmethod
    def get_page_size(cls) -> int:
        """Return the validated Kobo page size, or raise ConfigError."""
        try:
            value = int(cls._PAGE_SIZE_RAW)
        except ValueError:
            raise ConfigError(f"KOBOTOOLBOX_PAGE_SIZE must be an integer (got '{cls._PAGE_SIZE_RAW}')") from None
        if not 1 <= value <= KOBO_MAX_PAGE_SIZE:
            raise ConfigError(f"KOBOTOOLBOX_PAGE_SIZE must be between 1 and {KOBO_MAX_PAGE_SIZE} (got {value})")
        return value

    @classmethod
    def get_sources(cls) -> List[SourceConfig]:
        """
        Build the list of configured Kobo -> BigQuery sources to process.

        A source is only included if its Kobo form ID is actually set - so
        an environment that hasn't configured the Teacher Submission form
        yet simply runs CLOB-COE alone, exactly as this pipeline behaved
        before multi-source support existed. This is what makes the
        fallback to the old KOBOTOOLBOX_FORM_ID/BIGQUERY_TABLE_ID names
        above safe: an untouched old .env still produces exactly one
        source.
        """
        candidates = [
            SourceConfig("clob_coe", cls.KOBO_CLOB_COE_FORM_ID, cls.BIGQUERY_CLOB_COE_TABLE_ID),
            SourceConfig(
                "teacher_submission", cls.KOBO_TEACHER_SUBMISSION_FORM_ID, cls.BIGQUERY_TEACHER_SUBMISSION_TABLE_ID
            ),
        ]
        return [source for source in candidates if source.kobo_form_id]

    @classmethod
    def validate(cls) -> None:
        """Fail fast with one clear error listing everything that's missing or invalid."""
        missing: list[str] = []
        invalid: list[str] = []

        if not cls.KOBOTOOLBOX_TOKEN:
            missing.append("KOBOTOOLBOX_TOKEN")
        if not cls.BIGQUERY_PROJECT_ID:
            missing.append("BIGQUERY_PROJECT_ID")
        if not cls.get_bigquery_dataset_id():
            missing.append("BIGQUERY_DATASET_ID (or LOCAL_/PROD_ variant)")

        sources = cls.get_sources()
        if not sources:
            missing.append(
                "at least one Kobo source "
                "(KOBO_CLOB_COE_FORM_ID and/or KOBO_TEACHER_SUBMISSION_FORM_ID)"
            )
        else:
            # Every configured source needs a non-empty destination table -
            # this only fails if someone explicitly blanks out a table ID
            # while leaving its form ID set, since both have safe defaults.
            for source in sources:
                if not source.bigquery_table_id:
                    missing.append(f"BigQuery table ID for source '{source.name}'")

        # The credentials file is optional: when unset, the BigQuery client
        # falls back to Application Default Credentials. But if a path IS
        # given it must exist - fail here, at startup, rather than deep
        # inside the BigQuery client the first time a query runs.
        credentials_file = cls.get_bigquery_credentials_file()
        if credentials_file and not Path(credentials_file).is_file():
            invalid.append(f"BigQuery credentials file does not exist: {credentials_file}")

        try:
            cls.get_page_size()
        except ConfigError as exc:
            invalid.append(str(exc))

        if cls.LOG_LEVEL not in VALID_LOG_LEVELS:
            invalid.append(f"LOG_LEVEL must be one of {sorted(VALID_LOG_LEVELS)} (got '{cls.LOG_LEVEL}')")

        problems: list[str] = []
        if missing:
            problems.append(f"Missing required configuration: {', '.join(missing)}")
        problems.extend(invalid)
        if problems:
            raise ConfigError("; ".join(problems))


settings = Settings()
