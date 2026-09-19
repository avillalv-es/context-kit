"""JSON adapter.

The line with the semicolon holds two complete import statements. A matcher
anchored at the start of the line sees the first one and never looks past
the ``;``, so the second module - a real file in this repo - is missed
silently. Splitting the logical line on ``;`` before matching is what finds
it.
"""
from __future__ import annotations

import json; import app.util.reading

from ...models.reading import Reading


def rows_to_json(readings: list[Reading]) -> str:
    return json.dumps([r.as_row() for r in readings])


def parse(station_id: str, row: dict) -> Reading:
    return app.util.reading.parse_row(station_id, row)
