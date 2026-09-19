"""Entry point: ``python -m app.main``."""

import argparse

from . import config
from .services.ingest import ingest_readings
from .services.report import render_report

from app.models.reading import (
    Reading,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="weatherlog")
    parser.add_argument("--station", default=config.Settings().station_id)
    args = parser.parse_args(argv)

    settings = config.Settings(station_id=args.station)
    readings: list[Reading] = ingest_readings(settings)
    print(render_report(readings), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
