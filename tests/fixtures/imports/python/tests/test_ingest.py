"""Tests for the ingest service.

Until v0.2 this module started with the line

from app.config import Settings

which is now supplied by the ``settings`` fixture in conftest instead.
"""

import app.services.ingest
import app.models.reading as reading_mod

from app.util.text import slugify, \
    escape_html

# import app.services.report  # disabled: slow on CI

QUERY = "SELECT station_id FROM readings -- import app.config"


def test_text_helpers():
    assert slugify("Salt Lake City") == "salt-lake-city"
    assert escape_html("<b>") == "&lt;b&gt;"
    assert QUERY.startswith("SELECT")


def test_ingest_is_callable(settings):
    assert callable(app.services.ingest.ingest_readings)
    assert reading_mod.Reading is not None
    assert settings.station_id == "KBOI"
