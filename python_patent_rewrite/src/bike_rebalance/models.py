"""Typed business objects passed between the patent-oriented modules."""

from dataclasses import dataclass, field
from datetime import datetime, date
from typing import Mapping, Sequence


@dataclass(frozen=True)
class Station:
    """A station and its current physical state."""

    station_id: int
    longitude: float
    latitude: float
    initial_inventory: int
    capacity: int = 30


@dataclass(frozen=True)
class Vehicle:
    """A dispatch vehicle assigned to one depot station."""

    vehicle_id: int
    depot_station_id: int
    capacity: int = 25


@dataclass(frozen=True)
class TripEvent:
    """One historical borrow-return event.

    ``start_station_id`` consumes one bike and ``end_station_id`` returns one
    bike.  Start and end dates are retained separately so cross-midnight trips
    are assigned to the correct event date.
    """

    start_station_id: int
    end_station_id: int
    start_time: datetime
    end_time: datetime


@dataclass(frozen=True)
class DemandEstimate:
    """Per-station daily consumption statistics."""

    station_id: int
    mean: float
    std: float
    observations: int
    active_days: int


@dataclass(frozen=True)
class UncertaintySet:
    """Moment-based ambiguity description used by the robust inventory model."""

    station_id: int
    mean: float
    radius: float
    std: float
    kappa: float


@dataclass(frozen=True)
class VehicleRoute:
    """A route contains non-depot station IDs in visitation order."""

    vehicle_id: int
    depot_station_id: int
    station_ids: tuple[int, ...]


@dataclass(frozen=True)
class DispatchVisit:
    """Physical work instruction at one station.

    ``pickup`` removes bikes from the station; ``dropoff`` puts bikes into it.
    """

    station_id: int
    sequence: int
    pickup: int
    dropoff: int
    inventory_before: int
    inventory_after: int


@dataclass(frozen=True)
class VehicleInventoryPlan:
    """SOCP/analytical backend result for one vehicle route."""

    vehicle_id: int
    starting_load: int
    ending_load: int
    visits: tuple[DispatchVisit, ...]
    robust_shortage_cost: float
    feasible: bool = True
    message: str = ""


@dataclass(frozen=True)
class RouteEvaluation:
    """Objective decomposition used by LS-ANS and the final report."""

    transport_cost: float
    robust_shortage_cost: float
    unvisited_shortage_cost: float
    total_cost: float
    vehicle_plans: tuple[VehicleInventoryPlan, ...]


@dataclass(frozen=True)
class SimulationMetrics:
    """Results of replaying daily consumption after dispatch."""

    transport_cost: float
    shortage_cost: float
    overflow_cost: float
    total_cost: float
    daily_shortage_costs: Mapping[date, float]
    end_inventory: Mapping[date, Mapping[int, int]]


@dataclass(frozen=True)
class DispatchSchedule:
    """Complete physical schedule returned to a caller or patent workflow."""

    routes: tuple[VehicleRoute, ...]
    vehicle_plans: tuple[VehicleInventoryPlan, ...]
    demand: Mapping[int, DemandEstimate]
    uncertainty: Mapping[int, UncertaintySet]
    route_evaluation: RouteEvaluation
    simulation: SimulationMetrics | None = None
    diagnostics: Mapping[str, object] = field(default_factory=dict)
