"""Geographic distance and route constraint helpers."""

from math import asin, cos, radians, sin, sqrt
from typing import Mapping, Sequence

from ..models import Station, VehicleRoute


def haversine_km(a: Station, b: Station) -> float:
    """Great-circle distance between two stations in kilometres."""

    earth_radius = 6371.0088
    lat1, lat2 = radians(a.latitude), radians(b.latitude)
    d_lat = lat2 - lat1
    d_lon = radians(b.longitude - a.longitude)
    h = sin(d_lat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(d_lon / 2) ** 2
    return 2 * earth_radius * asin(min(1.0, sqrt(h)))


def route_distance_km(
    route: VehicleRoute,
    stations: Mapping[int, Station],
) -> float:
    """Distance for depot -> visits -> depot."""

    path = (route.depot_station_id,) + route.station_ids + (
        route.depot_station_id,
    )
    return sum(haversine_km(stations[x], stations[y]) for x, y in zip(path, path[1:]))


def route_distances(
    routes: Sequence[VehicleRoute],
    stations: Mapping[int, Station],
) -> dict[int, float]:
    """Return distances keyed by vehicle ID."""

    return {route.vehicle_id: route_distance_km(route, stations) for route in routes}
