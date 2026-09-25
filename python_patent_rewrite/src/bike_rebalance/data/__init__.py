"""Input adapters and demand aggregation."""

from .events import (
    build_daily_consumption,
    estimate_daily_demand,
    load_trip_events_csv,
)

__all__ = ["build_daily_consumption", "estimate_daily_demand", "load_trip_events_csv"]
