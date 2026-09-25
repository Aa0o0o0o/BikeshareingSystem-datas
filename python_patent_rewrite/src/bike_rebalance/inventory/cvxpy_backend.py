"""Optional explicit CVXPY SOCP backend.

This module is intentionally lazy: importing the package does not require
CVXPY.  When installed, the backend exposes the same ``SolverBackend`` API as
the dependency-free analytical backend and makes the SOC epigraph explicit.
"""

from typing import Mapping

from ..config import CostConfig
from ..models import (
    DemandEstimate,
    DispatchVisit,
    UncertaintySet,
    Vehicle,
    VehicleInventoryPlan,
    VehicleRoute,
    Station,
)


class CVXPYSOCPBackend:
    """Solve a fixed route with an explicit second-order cone model."""

    backend_name = "cvxpy-socp"

    def __init__(self, solver: str | None = None) -> None:
        self.solver = solver

    def optimize(
        self,
        route: VehicleRoute,
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
        cost: CostConfig,
    ) -> VehicleInventoryPlan:
        try:
            import cvxpy as cp
        except ImportError as exc:  # pragma: no cover - depends on environment
            raise RuntimeError(
                "CVXPY is optional; install the 'solver' extra to use this backend"
            ) from exc

        vehicle = vehicles[route.vehicle_id]
        station_ids = route.station_ids
        n = len(station_ids)
        if n == 0:
            return VehicleInventoryPlan(route.vehicle_id, 0, 0, (), 0.0)

        pickup = cp.Variable(n, nonneg=True)
        dropoff = cp.Variable(n, nonneg=True)
        target = cp.Variable(n)
        shortage_epigraph = cp.Variable(n, nonneg=True)
        starting_load = cp.Variable(nonneg=True)
        constraints = [starting_load <= vehicle.capacity, cp.sum(dropoff - pickup) == 0]
        for index, station_id in enumerate(station_ids):
            station = stations[station_id]
            estimate = demand[station_id]
            ambiguity = uncertainty[station_id]
            constraints.extend(
                [
                    target[index] == station.initial_inventory + dropoff[index] - pickup[index],
                    target[index] >= 0,
                    target[index] <= station.capacity,
                    # ||[s-mu, rho]||_2 <= 2t + (s-mu)
                    cp.SOC(
                        2 * shortage_epigraph[index] + target[index] - estimate.mean,
                        cp.hstack([target[index] - estimate.mean, ambiguity.radius]),
                    ),
                ]
            )
            prefix_q = cp.sum(dropoff[: index + 1] - pickup[: index + 1])
            constraints.extend(
                [
                    starting_load - prefix_q >= 0,
                    starting_load - prefix_q <= vehicle.capacity,
                ]
            )
        objective = cp.Minimize(
            cost.shortage_cost * cp.sum(shortage_epigraph)
            + 1e-6 * cp.sum(pickup + dropoff)
        )
        problem = cp.Problem(objective, constraints)
        solver = self.solver
        if solver is None:
            installed = set(cp.installed_solvers())
            solver = "CLARABEL" if "CLARABEL" in installed else "SCS"
        problem.solve(solver=solver, verbose=False)
        if problem.status not in (cp.OPTIMAL, cp.OPTIMAL_INACCURATE):
            raise ValueError(f"CVXPY SOCP did not solve route: {problem.status}")

        start = int(round(float(starting_load.value)))
        visits = []
        robust_cost = 0.0
        for index, station_id in enumerate(station_ids, start=1):
            station = stations[station_id]
            pick = max(0, int(round(float(pickup.value[index - 1]))))
            put = max(0, int(round(float(dropoff.value[index - 1]))))
            before = station.initial_inventory
            after = before + put - pick
            # The continuous conic solution is rounded into a physical bike
            # instruction.  The caller can rerun the analytical backend if an
            # application requires an integer-certified post-processing step.
            after = max(0, min(station.capacity, after))
            visits.append(DispatchVisit(station_id, index, pick, put, before, after))
            robust_cost += cost.shortage_cost * float(shortage_epigraph.value[index - 1])
        return VehicleInventoryPlan(
            vehicle_id=route.vehicle_id,
            starting_load=start,
            ending_load=start,
            visits=tuple(visits),
            robust_shortage_cost=robust_cost,
            message="continuous SOC solution rounded to bike quantities",
        )
