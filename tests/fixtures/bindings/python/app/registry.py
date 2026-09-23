"""Trap: `as b` aliases only the first element of a comma-separated import
list — "app.models.thing" keeps its full dotted name, it is not aliased
too.
"""
import app.models.base as b, app.models.thing


def describe() -> str:
    return f"{b.NAME}-{app.models.thing.NAME}"
