"""Replay actual daily consumption after a dispatch decision."""

from datetime import date
from typing import Mapping, Sequence

from ..config import CostConfig
from ..models import (
    SimulationMetrics,
    Station,
    VehicleInventoryPlan,
    VehicleRoute,
)
from ..routing.distance import route_distance_km


def replay_daily_consumption(
    stations: Sequence[Station],
    routes: Sequence[VehicleRoute],
    vehicle_plans: Sequence[VehicleInventoryPlan],
    daily_consumption: Mapping[date, Mapping[int, int]],
    cost: CostConfig,
) -> SimulationMetrics:
    """Apply the dispatch once and replay each day with capacity accounting."""

    station_map = {station.station_id: station for station in stations}
    inventory = {station.station_id: station.initial_inventory for station in stations}
    for plan in vehicle_plans:
        for visit in plan.visits:
            inventory[visit.station_id] = visit.inventory_after

    transport = sum(
        route_distance_km(route, station_map) * cost.transport_cost_per_km
        for route in routes
    )
    daily_shortage: dict[date, float] = {}
    end_inventory: dict[date, dict[int, int]] = {}
    total_shortage = 0.0
    total_overflow = 0.0
    for day in sorted(daily_consumption):
        shortage_units = 0.0
        overflow_units = 0.0
        for station in stations:
            inventory[station.station_id] -= daily_consumption[day].get(station.station_id, 0)
            if inventory[station.station_id] < 0:
                shortage_units += -inventory[station.station_id]
                inventory[station.station_id] = 0
            elif inventory[station.station_id] > station.capacity:
                overflow_units += inventory[station.station_id] - station.capacity
                inventory[station.station_id] = station.capacity
        shortage_cost = shortage_units * cost.shortage_cost
        daily_shortage[day] = shortage_cost
        total_shortage += shortage_cost
        total_overflow += overflow_units * cost.overflow_cost
        end_inventory[day] = dict(inventory)
    return SimulationMetrics(
        transport_cost=transport,
        shortage_cost=total_shortage,
        overflow_cost=total_overflow,
        total_cost=transport + total_shortage + total_overflow,
        daily_shortage_costs=daily_shortage,
        end_inventory=end_inventory,
    )
