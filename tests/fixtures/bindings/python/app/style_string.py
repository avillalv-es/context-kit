"""Trap: a backslash-continued string whose second half starts with "#333"
— that "#" is ordinary string content, not a comment start, even though a
line-oriented scanner might mistake it for one. The real import is
"from app import util"; the "import app.reports as r" text further down is
just inside a string, never executed as an import.
"""
STYLE = "color: \
#333"
from app import util
msg = "; import app.reports as r"


def value() -> str:
    return f"{STYLE}:{msg}:{util}"
