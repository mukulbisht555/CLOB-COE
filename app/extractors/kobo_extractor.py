"""
kobo_extractor.py

Extracts submissions from a KoboToolbox form, incrementally.

Design notes
------------
- Uses Kobo's `_id` field (a sequential integer) as the increment cursor:
  query={"_id": {"$gt": since_id}}, sorted ascending by `_id`. This means
  we only ever download submissions newer than what's already been loaded,
  instead of re-downloading the whole form on every run.
- `since_id` is passed in by the caller (main.py), which gets it from
  BigQueryLoader.get_watermark(). This module holds no state of its own
  and writes nothing to disk.
- Submissions are yielded one page at a time (iter_pages) rather than
  collected into one big list. The caller can load each page as it arrives,
  so memory stays flat and a failure halfway through a large backfill keeps
  everything already loaded - the next run simply resumes from the new
  watermark.
- Pagination advances the cursor to the highest `_id` seen in each page (not
  an offset), and only stops on an EMPTY page. It deliberately does not
  treat a short page as "the end", because the server may cap the page size
  below what we asked for.
- Transient failures (HTTP 429/5xx, connection resets) are retried with
  exponential backoff before an ExtractionError is raised.
"""

from __future__ import annotations

import json
from typing import Any, Dict, Iterator, List, Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from app.config.settings import settings
from app.utils.errors import ExtractionError
from app.utils.logger import get_logger

logger = get_logger(__name__)

# (connect timeout, read timeout) in seconds.
REQUEST_TIMEOUT = (10, 60)
RETRY_STATUS_CODES = (429, 500, 502, 503, 504)


class KoboExtractor:
    """
    Fetches submissions from a single KoboToolbox form/asset.

    One instance = one form. This pipeline creates one KoboExtractor per
    configured Kobo source (see app.config.settings.Settings.get_sources()
    and app/main.py) - the API URL, token, and page size are shared across
    all of them (same Kobo account), only `form_id` differs.
    """

    def __init__(self, form_id: str) -> None:
        if not form_id:
            raise ExtractionError("Kobo form ID is not configured")
        if not settings.KOBOTOOLBOX_TOKEN:
            raise ExtractionError("Kobo API token is not configured")

        self.form_id = form_id
        self.page_size = settings.get_page_size()
        # KoboToolbox v2 data endpoint for this specific form/asset.
        self.data_url = f"{settings.KOBOTOOLBOX_API_URL}/api/v2/assets/{self.form_id}/data/"
        self._session = self._build_session()

    @staticmethod
    def _build_session() -> requests.Session:
        """One reusable HTTP session (connection pooling + retry with backoff)."""
        session = requests.Session()
        session.headers.update(
            {
                "Authorization": f"Token {settings.KOBOTOOLBOX_TOKEN}",
                "Accept": "application/json",
            }
        )
        retry = Retry(
            total=5,
            backoff_factor=1.5,
            status_forcelist=RETRY_STATUS_CODES,
            allowed_methods=frozenset({"GET"}),
            respect_retry_after_header=True,
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount("https://", adapter)
        session.mount("http://", adapter)
        return session

    def _build_params(self, since_id: Optional[int]) -> Dict[str, Any]:
        """Build the query params for one page of the incremental request."""
        params: Dict[str, Any] = {
            "format": "json",
            "limit": self.page_size,
            # Ascending order so the cursor only ever moves forward.
            "sort": json.dumps({"_id": 1}),
        }
        if since_id is not None:
            params["query"] = json.dumps({"_id": {"$gt": since_id}})
        return params

    def _fetch_page(self, since_id: Optional[int]) -> List[Dict[str, Any]]:
        """Request one page of submissions with `_id` greater than `since_id`."""
        try:
            response = self._session.get(
                self.data_url, params=self._build_params(since_id), timeout=REQUEST_TIMEOUT
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise ExtractionError(f"Failed to fetch Kobo submissions: {exc}") from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise ExtractionError("Invalid JSON returned by Kobo API") from exc

        results = payload.get("results") if isinstance(payload, dict) else None
        if not isinstance(results, list):
            raise ExtractionError("Unexpected Kobo API response structure (missing 'results' list)")
        return results

    @staticmethod
    def _page_max_id(results: List[Dict[str, Any]]) -> int:
        """Highest integer `_id` in a page. Raises if none can be found."""
        ids = [row["_id"] for row in results if isinstance(row, dict) and isinstance(row.get("_id"), int)]
        if not ids:
            # Without an _id we can't advance the cursor - looping on would
            # re-fetch the same page forever.
            raise ExtractionError("Kobo page contained no integer '_id' values; cannot advance cursor")
        return max(ids)

    def iter_pages(self, since_id: Optional[int] = None) -> Iterator[List[Dict[str, Any]]]:
        """
        Yield pages of submissions newer than `since_id`, oldest first.

        Parameters
        ----------
        since_id:
            The last submission `_id` already loaded downstream. Pass None
            to fetch the entire form (the very first run, before anything
            has been loaded into BigQuery).

        Yields
        ------
        list[dict]
            One page of raw Kobo submission records (never empty).
        """
        cursor = since_id
        total = 0
        logger.info(
            "Starting Kobo extraction (form_id=%s, since_id=%s, page_size=%d)",
            self.form_id,
            cursor,
            self.page_size,
        )

        while True:
            results = self._fetch_page(cursor)
            if not results:
                break

            page_max = self._page_max_id(results)
            if cursor is not None and page_max <= cursor:
                raise ExtractionError(
                    f"Kobo returned no rows newer than cursor {cursor} despite the _id filter; aborting"
                )

            total += len(results)
            logger.info("Fetched page of %d submission(s) (total so far: %d)", len(results), total)
            yield results
            cursor = page_max

        logger.info("Kobo extraction complete. Total new submission(s): %d", total)
