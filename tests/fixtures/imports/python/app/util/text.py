"""Text helpers.

``app.util`` is a namespace package: there is deliberately no
``app/util/__init__.py`` next to this file.
"""

import re

_NON_WORD = re.compile(r"[^a-z0-9]+")


def slugify(value: str) -> str:
    return _NON_WORD.sub("-", value.lower()).strip("-")


def escape_html(value: str) -> str:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
