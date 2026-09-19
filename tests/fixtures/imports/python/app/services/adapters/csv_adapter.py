"""CSV adapter.

Three packages deep (``app.services.adapters``), which is what makes the
three-dot climb below legal and the four-dot climb below that illegal.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from ...config import Settings
from ..report import render_report

if TYPE_CHECKING:
    # Type-checking-only imports are real file dependencies: renaming
    # Reading breaks this file. Indentation must not disqualify them.
    from ...models.reading import Reading
    from ...models.station import Station

try:  # pragma: no cover - deliberately invalid, kept as a fixture case
    # Four dots from app/services/adapters/ climbs to app/, then to the repo
    # root, then past it. Python raises "attempted relative import beyond
    # top-level package". A resolver that clamps the climb at the root
    # instead of dropping it lands on the decoy config.py sitting there.
    from ....config import Settings as _Escaped
except ImportError:
    _Escaped = None


def to_csv(settings: Settings, readings: "list[Reading]") -> str:
    assert isinstance(settings, Settings)
    return render_report(readings)


def describe(station: "Station") -> str:
    return station.station_id
