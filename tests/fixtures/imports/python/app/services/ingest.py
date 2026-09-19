"""Pull readings from the upstream station API."""

import json

import requests

from ..config import Settings
from ..models.reading import Reading
from app.util.text import slugify

# from ..models.station import Station  # dropped in v0.2, kept for history


def ingest_readings(settings: Settings) -> list[Reading]:
    url = "https://example.invalid/stations/%s/readings" % slugify(settings.station_id)
    response = requests.get(url, timeout=settings.timeout_s)
    payload = json.loads(response.text)
    return [
        Reading(settings.station_id, row["taken_at"], row["temp_c"])
        for row in payload
    ]
