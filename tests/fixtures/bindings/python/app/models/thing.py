"""Trap: a self-import. This module imports its own package's "thing"
attribute (itself) alongside "base", via the relative package import
`from . import ...`. A resolver that follows the edge naively records a
self-loop app.models.thing -> app.models.thing.
"""
from . import thing, base

NAME = "thing"
