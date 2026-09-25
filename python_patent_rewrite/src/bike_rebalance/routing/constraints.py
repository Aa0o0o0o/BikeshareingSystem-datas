"""Explicit route constraint checks."""

from dataclasses import dataclass
from typing import Mapping, Sequence

from ..config import CostConfig, LSANSConfig
from ..models import Station, Vehicle, VehicleRoute
from .distance import route_distance_km


@dataclass(frozen=True)
class RouteConstraintResult:
    feasible: bool
    violations: tuple[str, ...]


def validate_routes(
    routes: Sequence[VehicleRoute],
    stations: Mapping[int, Station],
    vehicles: Mapping[int, Vehicle],
    cost: CostConfig,
    lsans: LSANSConfig,
) -> RouteConstraintResult:
    """Validate coverage, continuity, work time, and minimum task limits."""

    violations: list[str] = []
    known = set(stations)
    vehicle_ids = set(vehicles)
    if {route.vehicle_id for route in routes} != vehicle_ids:
        violations.append("route vehicle IDs do not match the vehicle set")

    seen: list[int] = []
    for route in routes:
        if route.vehicle_id not in vehicles:
            violations.append(f"unknown vehicle {route.vehicle_id}")
            continue
        if route.depot_station_id != vehicles[route.vehicle_id].depot_station_id:
            violations.append(f"vehicle {route.vehicle_id} has an invalid depot")
        if any(station_id not in known for station_id in route.station_ids):
            violations.append(f"vehicle {route.vehicle_id} visits an unknown station")
        if len(route.station_ids) < lsans.min_stations_per_vehicle:
            violations.append(f"vehicle {route.vehicle_id} violates minimum task count")
        seen.extend(route.station_ids)
        distance = route_distance_km(route, stations)
        work_hours = distance / 40.0 + len(route.station_ids) * cost.service_time_minutes / 60.0
        if distance > cost.max_route_distance_km + 1e-9:
            violations.append(f"vehicle {route.vehicle_id} exceeds route distance")
        if work_hours > cost.work_time_hours + 1e-9:
            violations.append(f"vehicle {route.vehicle_id} exceeds work time")

    if len(seen) != len(set(seen)):
        violations.append("a station is assigned to more than one vehicle")
    if set(seen) != known - {vehicle.depot_station_id for vehicle in vehicles.values()}:
        missing = sorted((known - {v.depot_station_id for v in vehicles.values()}) - set(seen))
        extra = sorted(set(seen) - known)
        if missing:
            violations.append(f"unvisited stations: {missing}")
        if extra:
            violations.append(f"unknown visited stations: {extra}")
    return RouteConstraintResult(not violations, tuple(violations))
