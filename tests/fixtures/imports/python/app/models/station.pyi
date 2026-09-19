"""Typing stub for the station record.

There is no ``station.py`` beside this file: the module exists only at
type-check time, which is why the single import that reaches it sits under
``if TYPE_CHECKING``. An extractor that only indexes ``.py`` will drop that
edge; one that indexes ``.pyi`` too will find it.

``app/services/ingest.py`` also mentions ``..models.station`` - in a comment.
That one must stay dropped even though this file now makes the target real.
"""

class Station:
    station_id: str
    name: str
    elevation_m: float
