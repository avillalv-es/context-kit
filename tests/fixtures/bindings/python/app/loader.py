"""Trap: backslash line continuation, once after a semicolon-joined
statement and once in a plain dotted import list. Stored with CRLF line
endings, on top of the continuation trap itself.
"""
import os; from app.models import database, \
    base

import app.util, \
    app.util.base


def paths() -> str:
    return f"{os.name}:{database.NAME}:{base.NAME}:{app.util.base.NAME}"
