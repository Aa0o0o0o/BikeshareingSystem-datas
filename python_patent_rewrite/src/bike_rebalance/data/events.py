"""Historical trip ingestion and station-level daily demand construction."""

from collections import defaultdict
from csv import DictReader
from datetime import date, datetime
from math import sqrt
from pathlib import Path
from statistics import mean, pstdev
from typing import Iterable, Mapping, Sequence

from ..models import DemandEstimate, TripEvent


def _parse_datetime(value: str) -> datetime:
    """Parse ISO timestamps used by the CSV adapter."""

    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_trip_events_csv(path: str | Path) -> tuple[TripEvent, ...]:
    """Load ``start_station_id,end_station_id,start_time,end_time`` records."""

    events: list[TripEvent] = []
    with Path(path).open("r", encoding="utf-8-sig", newline="") as handle:
        for row in DictReader(handle):
            events.append(
                TripEvent(
                    start_station_id=int(row["start_station_id"]),
                    end_station_id=int(row["end_station_id"]),
                    start_time=_parse_datetime(row["start_time"]),
                    end_time=_parse_datetime(row["end_time"]),
                )
            )
    return tuple(events)


def build_daily_consumption(
    events: Iterable[TripEvent],
    station_ids: Sequence[int],
) -> dict[date, dict[int, int]]:
    """Aggregate daily consumption ``d = borrows - returns``.

    This sign convention is explicit because the MATLAB prototype often used
    the opposite net-flow convention.  Borrow dates and return dates are
    handled separately, including cross-midnight trips.
    """

    known = set(station_ids)
    daily: dict[date, dict[int, int]] = defaultdict(
        lambda: {station_id: 0 for station_id in station_ids}
    )
    for event in events:
        start_day = event.start_time.date()
        end_day = event.end_time.date()
        if event.start_station_id in known:
            daily[start_day][event.start_station_id] += 1
        if event.end_station_id in known:
            daily[end_day][event.end_station_id] -= 1
    return {day: daily[day] for day in sorted(daily)}


def estimate_daily_demand(
    daily_consumption: Mapping[date, Mapping[int, int]],
    station_ids: Sequence[int],
) -> dict[int, DemandEstimate]:
    """Estimate per-station mean and population standard deviation.

    Missing station-day observations are treated as zero demand, which makes
    the observation window explicit and prevents high-activity stations from
    silently receiving a smaller denominator.
    """

    days = sorted(daily_consumption)
    estimates: dict[int, DemandEstimate] = {}
    for station_id in station_ids:
        values = [daily_consumption[day].get(station_id, 0) for day in days]
        avg = mean(values) if values else 0.0
        std = pstdev(values) if len(values) > 1 else 0.0
        active_days = sum(value != 0 for value in values)
        estimates[station_id] = DemandEstimate(
            station_id=station_id,
            mean=float(avg),
            std=float(std),
            observations=len(values),
            active_days=active_days,
        )
    return estimates


def daily_matrix(
    daily_consumption: Mapping[date, Mapping[int, int]],
    station_ids: Sequence[int],
) -> tuple[tuple[date, ...], tuple[tuple[int, ...], ...]]:
    """Return deterministic date and station-major views for simulation/tests."""

    days = tuple(sorted(daily_consumption))
    matrix = tuple(
        tuple(daily_consumption[day].get(station_id, 0) for day in days)
        for station_id in station_ids
    )
    return days, matrix
