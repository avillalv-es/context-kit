"""Runtime settings.

Deployment note: the Terraform module for this service uses an ``import``
block to adopt the existing bucket. That is not Python and nothing here
parses it.
"""

import os
from dataclasses import dataclass

DEFAULT_SOURCE = "import requests from the upstream station feed"


@dataclass
class Settings:
    station_id: str = "KSLC"
    source: str = DEFAULT_SOURCE
    timeout_s: int = 10

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            station_id=os.environ.get("STATION_ID", "KSLC"),
            timeout_s=int(os.environ.get("STATION_TIMEOUT", "10")),
        )
