"""End-to-end coordination of data, uncertainty, routing, inventory, and replay."""

from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence

from ..config import PipelineConfig
from ..data.events import build_daily_consumption, estimate_daily_demand
from ..demand.uncertainty import build_uncertainty_sets, robust_shortage_cost
from ..inventory.analytical_socp import InfeasibleInventoryPlan
from ..inventory.backend import InventoryOptimizer
from ..models import (
    DemandEstimate,
    DispatchSchedule,
    RouteEvaluation,
    Station,
    TripEvent,
    UncertaintySet,
    Vehicle,
    VehicleInventoryPlan,
    VehicleRoute,
)
from ..routing.distance import route_distance_km
from ..routing.ls_ans import LSANS, RoutePlan
from ..simulation.replay import replay_daily_consumption


class RebalancingPipeline:
    """Coordinate the six patent-oriented processing stages."""

    def __init__(self, config: PipelineConfig, inventory_optimizer: InventoryOptimizer) -> None:
        self.config = config
        self.inventory_optimizer = inventory_optimizer

    def run(
        self,
        stations: Sequence[Station],
        vehicles: Sequence[Vehicle],
        events: Iterable[TripEvent],
    ) -> DispatchSchedule:
        """Run the complete chain and return physical dispatch instructions."""

        station_map = {station.station_id: station for station in stations}
        vehicle_map = {vehicle.vehicle_id: vehicle for vehicle in vehicles}
        station_ids = tuple(station_map)
        daily_consumption = build_daily_consumption(events, station_ids)
        demand = estimate_daily_demand(daily_consumption, station_ids)
        uncertainty = build_uncertainty_sets(demand, self.config.uncertainty_kappa)

        def evaluate(routes: tuple[VehicleRoute, ...]) -> float:
            evaluation = self.evaluate_routes(
                routes, station_map, vehicle_map, demand, uncertainty
            )
            return evaluation.total_cost

        search = LSANS(
            station_map,
            vehicles,
            demand,
            self.config.cost,
            self.config.lsans,
            evaluate,
        )
        route_plan = search.solve()
        evaluation = self.evaluate_routes(
            route_plan.routes,
            station_map,
            vehicle_map,
            demand,
            uncertainty,
        )
        simulation = replay_daily_consumption(
            stations,
            route_plan.routes,
            evaluation.vehicle_plans,
            daily_consumption,
            self.config.cost,
        )
        return DispatchSchedule(
            routes=route_plan.routes,
            vehicle_plans=evaluation.vehicle_plans,
            demand=demand,
            uncertainty=uncertainty,
            route_evaluation=evaluation,
            simulation=simulation,
            diagnostics={
                "backend": getattr(self.inventory_optimizer.backend, "backend_name", "unknown"),
                "daily_consumption_days": len(daily_consumption),
                "lsans_iterations": route_plan.iterations,
                "lsans_accepted_moves": route_plan.accepted_moves,
                "lsans_weights": dict(route_plan.weights),
                "lsans_trace": route_plan.trace,
            },
        )

    def evaluate_routes(
        self,
        routes: Sequence[VehicleRoute],
        stations: Mapping[int, Station],
        vehicles: Mapping[int, Vehicle],
        demand: Mapping[int, DemandEstimate],
        uncertainty: Mapping[int, UncertaintySet],
    ) -> RouteEvaluation:
        """Evaluate routing and inventory decisions as one coupled objective."""

        plans: list[VehicleInventoryPlan] = []
        dropped: set[int] = set()
        for route in routes:
            try:
                plans.append(
                    self.inventory_optimizer.optimize_route(
                        route, stations, vehicles, demand, uncertainty, self.config.cost
                    )
                )
            except InfeasibleInventoryPlan:
                dropped.update(route.station_ids)
        visited = {station_id for route in routes for station_id in route.station_ids} - dropped
        depots = {vehicle.depot_station_id for vehicle in vehicles.values()}
        unvisited_cost = sum(
            robust_shortage_cost(
                stations[station_id].initial_inventory,
                uncertainty[station_id],
                self.config.cost.shortage_cost,
            )
            for station_id in stations
            if station_id not in visited and station_id not in depots
        )
        transport = sum(
            route_distance_km(route, stations) * self.config.cost.transport_cost_per_km
            for route in routes
        )
        robust_cost = sum(plan.robust_shortage_cost for plan in plans)
        return RouteEvaluation(
            transport_cost=transport,
            robust_shortage_cost=robust_cost,
            unvisited_shortage_cost=unvisited_cost,
            total_cost=transport + robust_cost + unvisited_cost,
            vehicle_plans=tuple(plans),
        )
