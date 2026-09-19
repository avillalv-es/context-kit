from ..config import Settings
import app.models.reading

# This file is stored the way an editor on Windows saves it: a UTF-8 BOM in
# front of the first byte and CRLF at the end of every line. Both are silent
# misses rather than false edges, which is what makes them easy to ship.
#
# The BOM sits before the `f` of `from` on line 1, so a pattern anchored with
# ^[ \t]* matches nothing there and the edge to app/config.py disappears.
#
# The CR sits after the last character of line 2, so the dotted module comes
# out as "app.models.reading\r", fails the identifier check or the index
# lookup, and the edge to app/models/reading.py disappears.


def station_path(settings: Settings) -> str:
    name = app.models.reading.Reading.__name__
    return "%s/%s.csv" % (settings.station_id, name)
