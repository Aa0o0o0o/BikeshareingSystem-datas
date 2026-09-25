"""Solver backend protocol and business-facing optimizer facade."""

from typing import Mapping, Protocol, Sequence

from ..config import CostConfig
from ..models import (
    DemandEstimate,
    UncertaintySet,
    Vehicle,
    VehicleInventoryPlan,
    VehicleRoute,
    Station,
)


class SolverBackend(Protocol):
    """Interface implemented by analytical, CVXPY, or commercial backends."""

    backend_name: str

    def optimize(
        self,
        route: VehicleRoute,
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
        cost: CostConfig,
    ) -> VehicleInventoryPlan:
        """Solve the route-constrained inventory subproblem."""


class InventoryOptimizer:
    """Keep business logic independent from a particular optimization solver."""

    def __init__(self, backend: SolverBackend) -> None:
        self.backend = backend

    def optimize_route(
        self,
        route: VehicleRoute,
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
        cost: CostConfig,
    ) -> VehicleInventoryPlan:
        """Solve one route and return its physical visit plan."""

        return self.backend.optimize(route, stations, vehicles, demand, uncertainty, cost)

    def optimize_routes(
        self,
        routes: Sequence[VehicleRoute],
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
        cost: CostConfig,
    ) -> tuple[VehicleInventoryPlan, ...]:
        """Solve every route and return physical visit plans."""

        return tuple(
            self.backend.optimize(route, stations, vehicles, demand, uncertainty, cost)
            for route in routes
        )
