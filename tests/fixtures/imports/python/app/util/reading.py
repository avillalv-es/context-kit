"""Row-parsing helpers.

Deliberate basename collision with ``app/models/reading.py``. Nothing here is
the Reading dataclass; this module only builds one. A resolver that matches
``reading`` by basename has two files to choose from and no way to choose.

The stdlib-shadowing case that ``app/util/logging.py`` sets up is exercised
from ``app/services/export.py``, not from here: this file has a legitimate
edge to ``app/util/logging.py`` already, and a false edge to the same file
would be swallowed by deduplication on the (from, to) pair.
"""

from .logging import get_logger
from ..models.reading import Reading

_log = get_logger(__name__)


def parse_row(station_id: str, row: dict) -> Reading:
    _log.debug("parsing a row for %s", station_id)
    return Reading(station_id, row["taken_at"], float(row["temp_c"]))
