"""
logger.py

Centralized logging setup for the ELT pipeline.

Design notes
------------
- Logs to both the console (stdout, so `docker compose up` / `docker logs`
  show everything) and a size-rotated local log file (so it can't grow forever), for
  after-the-fact debugging.
- configure_logging() is idempotent: safe to call more than once without
  attaching duplicate handlers (which would otherwise double up every log
  line).
- If the filesystem is read-only (some hardened container setups), file
  logging is skipped with a warning rather than crashing the pipeline -
  console logging alone is enough to keep the pipeline usable.
"""

from __future__ import annotations

import logging
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path

LOG_DIR = Path("logs")
LOG_FILE = LOG_DIR / "pipeline.log"
LOG_MAX_BYTES = 5 * 1024 * 1024  # rotate at 5 MB, keep 3 old files
LOG_BACKUP_COUNT = 3


def configure_logging(level: str = "INFO") -> None:
    """Configure the root logger with a console handler and a file handler."""
    root_logger = logging.getLogger()

    if root_logger.handlers:
        # Already configured elsewhere in this process - don't duplicate handlers.
        return

    root_logger.setLevel(level.upper())

    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)

    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        file_handler = RotatingFileHandler(
            LOG_FILE, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT, encoding="utf-8"
        )
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
    except OSError:
        root_logger.warning(
            "Could not create log file at %s; continuing with console logging only.",
            LOG_FILE,
        )


def get_logger(name: str) -> logging.Logger:
    """Return a named logger. Call configure_logging() once at startup first."""
    return logging.getLogger(name)
