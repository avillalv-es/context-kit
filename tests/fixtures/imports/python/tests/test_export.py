"""Export-path tests."""
import importlib

import app.models
from app.util import text

from .util.text import fake_slug

from app.services.export import (  # noqa: F401
    EXPORT_SQL,
    export_rows,
)

# from app.services.report import render_html  # disabled: needs the html extra

# A triple quote """ written inside a comment opens nothing. An extractor
# that counts delimiters before it strips comments flips into block-string
# mode here and swallows every import below, reporting no error.
import app.services.ingest

HASH_NOTE = "# import app.config"


def test_dynamic_imports_are_not_static_edges():
    mod = importlib.import_module("app.config")
    other = __import__("app.models.reading")
    assert mod is not None and other is not None


def test_helpers():
    assert text.slugify("Salt Lake") == "salt-lake"
    assert fake_slug("Salt Lake") == "salt-lake"
    assert app.models.Reading is not None
    assert EXPORT_SQL.strip().startswith("SELECT")
    assert callable(export_rows)
    assert callable(app.services.ingest.ingest_readings)
    assert HASH_NOTE.startswith("#")
