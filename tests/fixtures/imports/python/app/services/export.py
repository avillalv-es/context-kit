"""Export entry points.

Three of the strings below are multi-line and sit in the middle of the file
rather than at the top, so a tracker that only expects a triple-quoted block
on line 1, or that stops tracking once the module docstring closes, reads
their contents as code. Each one contains a statement that would resolve to
a file that really exists.

``import logging`` is the stdlib module. There is exactly one ``logging.py``
in this tree - ``app/util/logging.py`` - so a resolver that falls back to a
unique-basename search wires this file to it. Nothing else here points at
that file, so the invented edge has nowhere to hide.
"""

import logging

from . import ingest, report
from .. import models
from ..util.text import *
from .adapters import csv_adapter

EXPORT_SQL = """
SELECT station_id, taken_at, temp_c
FROM readings
-- the line below is data, at column zero, and is not an import
from app.config import Settings
ORDER BY taken_at
"""

SHELL_SNIPPET = '''
python - <<'PY'
import app.models.reading
PY
'''

NESTED_DOC = '''
Example::

    """
    from app.config import Settings
    """
'''

from_station = "KSLC"


_log = logging.getLogger(__name__)


def export_rows(settings):
    """Return the report body, the Reading class and a slugified station."""
    _log.debug("exporting %s", settings.station_id)
    rows = ingest.ingest_readings(settings)
    return (
        report.render_report(rows),
        models.Reading,
        slugify(from_station),
        csv_adapter.to_csv,
    )
