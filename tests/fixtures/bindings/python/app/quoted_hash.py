"""Trap: a backslash-continued string whose joined halves contain a "#"
character — ordinary string content, not a comment start. The real imports
are "import app.util" and "import app.models"; "y" is just a plain string.
"""
x = 'a \
b # c'
import app.util
y = "q"
import app.models


def value() -> str:
    return f"{x}:{y}"
