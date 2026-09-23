"""Trap: a statement following the closing paren of a parenthesised import
list, on the very same physical line — "import app.reports" here is not
part of the "from app import (...)" list above it.
"""
from app import (models,
    util); import app.reports


def touch() -> str:
    return f"{app.reports.summarize()}"
