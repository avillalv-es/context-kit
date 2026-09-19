from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class Reading:
    station_id: str
    taken_at: datetime
    temp_c: float

    def as_row(self) -> tuple[str, str, float]:
        return (self.station_id, self.taken_at.isoformat(), self.temp_c)
