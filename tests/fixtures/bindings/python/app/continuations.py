"""Trap: two backslash-continuation shapes. The first line pairs a
comma-joined dotted import list with a semicolon-separated second import,
both folded into one continued logical line. The second shows a
continuation that ends before a comment line, so "import app.util" after it
is its own statement, not swallowed by the continuation above it.
"""
import app.models, \
    app.util; import app.reports

x = 1 + \
    2
# note
import app.util


def touch() -> str:
    return f"{x}:{app.reports.summarize()}"
