"""
errors.py

Custom exception hierarchy for the ELT pipeline.

Keeping these distinct (rather than raising bare Exception/ValueError
everywhere) lets main.py handle each failure category deliberately -
a bad config should be reported differently from a Kobo API outage,
which should be reported differently from a BigQuery load failure.
"""


class ETLError(Exception):
    """Base class for all pipeline errors. Catch this in main.py as a
    catch-all for "something in our own pipeline logic failed"."""


class ConfigError(ETLError):
    """Raised when required configuration is missing or invalid."""


class ExtractionError(ETLError):
    """Raised when extracting data from KoboToolbox fails."""


class LoadError(ETLError):
    """Raised when loading data into BigQuery fails."""
