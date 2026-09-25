"""Pure route neighborhood operators used by LS-ANS."""

from typing import Iterable

from ..models import VehicleRoute


def replace_route(
    routes: tuple[VehicleRoute, ...], index: int, route: VehicleRoute
) -> tuple[VehicleRoute, ...]:
    updated = list(routes)
    updated[index] = route
    return tuple(updated)


def swap_stations(
    routes: tuple[VehicleRoute, ...], first: int, second: int
) -> tuple[VehicleRoute, ...]:
    """Swap positions across routes while preserving vehicle ownership."""

    mutable = [list(route.station_ids) for route in routes]
    a_route, a_pos = _locate(mutable, first)
    b_route, b_pos = _locate(mutable, second)
    mutable[a_route][a_pos], mutable[b_route][b_pos] = (
        mutable[b_route][b_pos], mutable[a_route][a_pos]
    )
    return tuple(
        VehicleRoute(route.vehicle_id, route.depot_station_id, tuple(mutable[i]))
        for i, route in enumerate(routes)
    )


def relocate_station(
    routes: tuple[VehicleRoute, ...],
    source_route: int,
    source_pos: int,
    target_route: int,
    target_pos: int,
) -> tuple[VehicleRoute, ...]:
    """Move one station to another position, including another vehicle."""

    mutable = [list(route.station_ids) for route in routes]
    station_id = mutable[source_route].pop(source_pos)
    mutable[target_route].insert(target_pos, station_id)
    return tuple(
        VehicleRoute(route.vehicle_id, route.depot_station_id, tuple(mutable[i]))
        for i, route in enumerate(routes)
    )


def reverse_segment(
    routes: tuple[VehicleRoute, ...], route_index: int, start: int, end: int
) -> tuple[VehicleRoute, ...]:
    """Reverse a contiguous segment of one route."""

    mutable = [list(route.station_ids) for route in routes]
    mutable[route_index][start : end + 1] = reversed(mutable[route_index][start : end + 1])
    return tuple(
        VehicleRoute(route.vehicle_id, route.depot_station_id, tuple(mutable[i]))
        for i, route in enumerate(routes)
    )


def _locate(routes: list[list[int]], flat_index: int) -> tuple[int, int]:
    offset = 0
    for route_index, route in enumerate(routes):
        if flat_index < offset + len(route):
            return route_index, flat_index - offset
        offset += len(route)
    raise IndexError("flat station index out of range")
