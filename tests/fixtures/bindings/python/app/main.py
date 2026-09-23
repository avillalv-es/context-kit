"""Trap: a parenthesised import list opened mid-line rather than right
after the opening paren — "(base, database as db," starts the list on the
`from` line itself, and only "thing)" is on its own line.
"""
from app.models import (base, database as db,
    thing)

import a_package_not_in_this_tree  # bare specifier: resolves to nothing


def summary() -> str:
    return f"{base.NAME}-{db.NAME}-{thing.NAME}"
