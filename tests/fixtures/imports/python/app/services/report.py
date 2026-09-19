"""Render readings as a plain-text report."""

from ..models import Reading
from app.util.text import slugify

HEADER = "station,taken_at,temp_c"


def render_report(readings: list[Reading]) -> str:
    lines = [HEADER]
    for reading in readings:
        row = reading.as_row()
        lines.append("%s,%s,%.1f" % (slugify(row[0]), row[1], row[2]))
    return "\n".join(lines) + "\n"


def render_html(readings: list[Reading]) -> str:
    """Optional HTML rendering; jinja2 ships in the ``html`` extra."""
    try:
        from jinja2 import Template
    except ImportError:  # pragma: no cover - fallback path
        from app.util.text import escape_html

        return "<pre>%s</pre>" % escape_html(render_report(readings))
    return Template("<pre>{{ body }}</pre>").render(body=render_report(readings))
