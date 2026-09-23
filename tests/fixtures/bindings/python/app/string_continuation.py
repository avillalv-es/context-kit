"""Trap: a string literal continued across a backslash-newline INSIDE the
quotes, so the text "import app.evil" inside it is just string content, not
code. Only "import app.util" after the string closes is a real import.
"""
x = "a; \
import app.evil"; import app.util


def value() -> str:
    return x
