"""Trap: `base as baseline` — the renamed import's original name ("base")
contains the substring "as", inside a parenthesised import list split
across lines.
"""
from app.models import (database,
    base as baseline)

from a_missing_reporting_lib import build_chart  # bare specifier


def summarize() -> str:
    return f"{database.NAME}/{baseline.NAME}"
