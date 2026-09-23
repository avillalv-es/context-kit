"""Trap: a backslash-continued double-quoted string whose content includes
three single-quote characters in a row ("it'''s") — that is NOT the start
of a triple-quoted string, just apostrophes inside an ordinary string. The
only real import is "import app.reports" after it.
"""
x = "a \
it'''s"
import app.reports


def value() -> str:
    return f"{x}:{app.reports.summarize()}"
