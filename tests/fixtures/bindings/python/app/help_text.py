"""Trap: a string literal containing "; from app import (x" — text that
looks like the start of a parenthesised import list is just data inside a
quoted string, not real syntax. The two import statements below it are the
only real imports in this file.
"""
HELP = "usage: a; from app import (x"
import app.models
from app import util

print(HELP)
