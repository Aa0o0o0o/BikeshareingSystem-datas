"""Dependency-free fixed-route robust inventory backend.

The backend exposes the same subproblem boundary as a conic solver.  It uses
the closed-form SOC epigraph expression for shortage and a bounded projection
for the route conservation constraint, so the representative pipeline remains
reproducible without Gurobi, MOSEK, or CVXPY.  A future conic backend can
implement :class:`SolverBackend` without changing routing or coordination.
"""

from dataclasses import dataclass
from typing import Mapping

from ..config import CostConfig
from ..demand.uncertainty import robust_shortage_cost
from ..models import (
    DemandEstimate,
    DispatchVisit,
    UncertaintySet,
    Vehicle,
    VehicleInventoryPlan,
    VehicleRoute,
    Station,
)


class InfeasibleInventoryPlan(ValueError):
    """Raised when route actions cannot fit the vehicle or station limits."""


class AnalyticalSOCPBackend:
    """Analytical fixed-route solution of the robust inventory subproblem."""

    backend_name = "analytical-socp-epigraph"

    def optimize(
        self,
        route: VehicleRoute,
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
        cost: CostConfig,
    ) -> VehicleInventoryPlan:
        vehicle = vehicles[route.vehicle_id]
        if not route.station_ids:
            return VehicleInventoryPlan(
                vehicle_id=route.vehicle_id,
                starting_load=0,
                ending_load=0,
                visits=(),
                robust_shortage_cost=0.0,
            )

        # Unconstrained target: mean consumption plus the ambiguity radius.
        # It is then projected onto station bounds and route conservation.
        desired = {
            station_id: self._clamp(
                demand[station_id].mean + uncertainty[station_id].radius,
                0,
                stations[station_id].capacity,
            )
            for station_id in route.station_ids
        }
        lower = {
            station_id: -stations[station_id].initial_inventory
            for station_id in route.station_ids
        }
        upper = {
            station_id: stations[station_id].capacity - stations[station_id].initial_inventory
            for station_id in route.station_ids
        }
        raw_delta = {
            station_id: desired[station_id] - stations[station_id].initial_inventory
            for station_id in route.station_ids
        }
        delta = self._project_with_conservation(raw_delta, lower, upper)
        integer_delta = self._integerize(delta, lower, upper)
        visits = self._build_visits(route, stations, integer_delta, uncertainty, cost)

        # The vehicle may be loaded at the depot before its first visit.  This
        # makes the route constraint explicit instead of silently allowing
        # negative vehicle load when a drop-off precedes a pickup.
        prefix = 0
        required_start_load = 0
        for visit in visits:
            prefix += visit.dropoff - visit.pickup
            required_start_load = max(required_start_load, prefix)
        if required_start_load > vehicle.capacity:
            raise InfeasibleInventoryPlan(
                f"vehicle {vehicle.vehicle_id} needs {required_start_load} bikes "
                f"but capacity is {vehicle.capacity}"
            )
        prefix = 0
        maximum_load = required_start_load
        for visit in visits:
            prefix += visit.dropoff - visit.pickup
            maximum_load = max(maximum_load, required_start_load - prefix)
        if maximum_load > vehicle.capacity:
            raise InfeasibleInventoryPlan(
                f"vehicle {vehicle.vehicle_id} reaches {maximum_load} bikes "
                f"on route but capacity is {vehicle.capacity}"
            )
        ending_load = required_start_load - sum(v.pickup - v.dropoff for v in visits)
        robust_cost = sum(
            robust_shortage_cost(
                visit.inventory_after,
                uncertainty[visit.station_id],
                cost.shortage_cost,
            )
            for visit in visits
        )
        return VehicleInventoryPlan(
            vehicle_id=vehicle.vehicle_id,
            starting_load=required_start_load,
            ending_load=ending_load,
            visits=tuple(visits),
            robust_shortage_cost=robust_cost,
        )

    @staticmethod
    def _clamp(value: float, low: float, high: float) -> float:
        return min(high, max(low, value))

    def _project_with_conservation(self, values, lower, upper):
        """Project signed station adjustments so their sum is zero."""

        result = dict(values)
        residual = sum(result.values())
        # Reducing positive adjustments or increasing negative adjustments is
        # equivalent to a bounded water-filling projection for this 1-D balance.
        if residual > 0:
            for station_id in sorted(result, key=lambda x: result[x], reverse=True):
                available = result[station_id] - lower[station_id]
                change = min(residual, max(0.0, available))
                result[station_id] -= change
                residual -= change
                if residual <= 1e-9:
                    break
        elif residual < 0:
            for station_id in sorted(result, key=lambda x: result[x]):
                available = upper[station_id] - result[station_id]
                change = min(-residual, max(0.0, available))
                result[station_id] += change
                residual += change
                if residual >= -1e-9:
                    break
        if abs(sum(result.values())) > 1e-6:
            raise InfeasibleInventoryPlan("station adjustment conservation is infeasible")
        return result

    @staticmethod
    def _integerize(values, lower, upper):
        result = {station_id: int(round(value)) for station_id, value in values.items()}
        for station_id in result:
            result[station_id] = max(
                int(round(lower[station_id])),
                min(int(round(upper[station_id])), result[station_id]),
            )
        residual = -sum(result.values())
        while residual:
            candidates = [
                station_id
                for station_id in result
                if lower[station_id]
                <= result[station_id] + residual / abs(residual)
                <= upper[station_id]
            ]
            if not candidates:
                raise InfeasibleInventoryPlan(
                    "integer station adjustment conservation is infeasible"
                )
            station_id = candidates[0]
            result[station_id] += residual // abs(residual)
            residual -= residual // abs(residual)
        return result

    @staticmethod
    def _build_visits(route, stations, delta, uncertainty, cost):
        visits = []
        for sequence, station_id in enumerate(route.station_ids, start=1):
            station = stations[station_id]
            adjustment = delta[station_id]
            pickup = max(0, -adjustment)
            dropoff = max(0, adjustment)
            before = station.initial_inventory
            after = before + dropoff - pickup
            if not 0 <= after <= station.capacity:
                raise InfeasibleInventoryPlan(f"station {station_id} inventory bound violated")
            visits.append(
                DispatchVisit(
                    station_id=station_id,
                    sequence=sequence,
                    pickup=pickup,
                    dropoff=dropoff,
                    inventory_before=before,
                    inventory_after=after,
                )
            )
        return visits
