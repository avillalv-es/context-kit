import os, sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import Settings


@pytest.fixture()
def settings() -> Settings:
    return Settings(station_id="KBOI")
