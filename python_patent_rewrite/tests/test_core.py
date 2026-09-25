from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from bike_rebalance.config import CostConfig, LSANSConfig, PipelineConfig  # noqa: E402
from bike_rebalance.coordination import RebalancingPipeline  # noqa: E402
from bike_rebalance.data.events import build_daily_consumption, estimate_daily_demand  # noqa: E402
from bike_rebalance.demand.uncertainty import (  # noqa: E402
    build_uncertainty_sets,
    robust_shortage_cost,
)
from bike_rebalance.inventory import AnalyticalSOCPBackend, InventoryOptimizer  # noqa: E402
from bike_rebalance.models import (  # noqa: E402
    DemandEstimate,
    Station,
    TripEvent,
    UncertaintySet,
    Vehicle,
    VehicleRoute,
)
from bike_rebalance.routing.distance import route_distance_km  # noqa: E402


class CoreTests(unittest.TestCase):
    def test_demand_sign_and_cross_midnight(self):
        event = TripEvent(
            start_station_id=1,
            end_station_id=2,
            start_time=datetime(2026, 1, 1, 23, 55),
            end_time=datetime(2026, 1, 2, 0, 10),
        )
        daily = build_daily_consumption((event,), (1, 2))
        self.assertEqual(daily[datetime(2026, 1, 1).date()][1], 1)
        self.assertEqual(daily[datetime(2026, 1, 2).date()][2], -1)
        demand = estimate_daily_demand(daily, (1, 2))
        self.assertEqual(demand[1].mean, 0.5)
        self.assertEqual(demand[2].mean, -0.5)

    def test_robust_shortage_matches_closed_form(self):
        uncertainty = UncertaintySet(1, mean=10.0, radius=4.0, std=4.0, kappa=1.0)
        self.assertAlmostEqual(robust_shortage_cost(10.0, uncertainty, 5.0), 10.0)
        self.assertAlmostEqual(
            robust_shortage_cost(20.0, uncertainty, 5.0),
            5 * 0.5 * (-10 + 10.7703296143),
            places=8,
        )

    def test_inventory_conservation_and_capacity(self):
        stations = {
            1: Station(1, 0, 0, 15, 30),
            2: Station(2, 0.01, 0, 2, 30),
            3: Station(3, 0.02, 0, 28, 30),
        }
        vehicles = {1: Vehicle(1, 1, 25)}
        demand = {
            2: DemandEstimate(2, 8, 2, 4, 4),
            3: DemandEstimate(3, -5, 2, 4, 4),
        }
        uncertainty = build_uncertainty_sets(demand)
        route = VehicleRoute(1, 1, (2, 3))
        plan = AnalyticalSOCPBackend().optimize(
            route, stations, vehicles, demand, uncertainty, CostConfig()
        )
        self.assertEqual(sum(v.dropoff - v.pickup for v in plan.visits), 0)
        self.assertTrue(all(0 <= v.inventory_after <= 30 for v in plan.visits))
        self.assertLessEqual(plan.starting_load, 25)

    def test_inventory_rejects_intermediate_vehicle_overload(self):
        stations = {
            1: Station(1, 0, 0, 15, 30),
            2: Station(2, 0.01, 0, 29, 30),
            3: Station(3, 0.02, 0, 0, 30),
        }
        vehicles = {1: Vehicle(1, 1, 2)}
        demand = {
            2: DemandEstimate(2, -20, 1, 4, 4),
            3: DemandEstimate(3, 20, 1, 4, 4),
        }
        uncertainty = build_uncertainty_sets(demand)
        route = VehicleRoute(1, 1, (2, 3))
        with self.assertRaises(ValueError):
            AnalyticalSOCPBackend().optimize(
                route, stations, vehicles, demand, uncertainty, CostConfig()
            )

    def test_route_distance_returns_to_depot(self):
        stations = {
            1: Station(1, 0, 0, 10),
            2: Station(2, 0.01, 0, 10),
        }
        route = VehicleRoute(1, 1, (2,))
        self.assertGreater(route_distance_km(route, stations), 2.0)

    def test_pipeline_is_reproducible_and_returns_physical_output(self):
        stations = (
            Station(1, -73.56, 45.52, 20),
            Station(2, -73.55, 45.52, 20),
            Station(3, -73.555, 45.525, 4),
            Station(4, -73.545, 45.515, 26),
            Station(5, -73.565, 45.515, 8),
        )
        vehicles = (Vehicle(1, 1), Vehicle(2, 2))
        events = []
        for day_offset in range(4):
            day = datetime(2026, 2, 1) + timedelta(days=day_offset)
            events.extend(
                (
                    TripEvent(3, 4, day, day + timedelta(minutes=10)),
                    TripEvent(3, 5, day + timedelta(minutes=20), day + timedelta(minutes=30)),
                    TripEvent(4, 3, day + timedelta(minutes=40), day + timedelta(minutes=50)),
                )
            )
        config = PipelineConfig(
            cost=CostConfig(max_route_distance_km=30),
            lsans=LSANSConfig(
                iterations=20,
                local_search_iterations=1,
                no_improvement_limit=8,
                random_seed=7,
            ),
        )
        pipeline = RebalancingPipeline(config, InventoryOptimizer(AnalyticalSOCPBackend()))
        first = pipeline.run(stations, vehicles, events)
        second = pipeline.run(stations, vehicles, events)
        self.assertEqual(first.routes, second.routes)
        self.assertEqual(first.route_evaluation.total_cost, second.route_evaluation.total_cost)
        self.assertTrue(first.vehicle_plans)
        self.assertIsNotNone(first.simulation)
        for plan in first.vehicle_plans:
            for visit in plan.visits:
                self.assertEqual(
                    visit.inventory_after,
                    visit.inventory_before + visit.dropoff - visit.pickup,
                )
    def test_pipeline_treats_infeasible_route_as_unvisited(self):
        stations = {
            1: Station(1, 0, 0, 15, 30),
            2: Station(2, 0.01, 0, 29, 30),
            3: Station(3, 0.02, 0, 0, 30),
        }
        vehicles = {1: Vehicle(1, 1, 2)}
        demand = {
            2: DemandEstimate(2, -20, 1, 4, 4),
            3: DemandEstimate(3, 20, 1, 4, 4),
        }
        uncertainty = build_uncertainty_sets(demand)
        pipeline = RebalancingPipeline(
            PipelineConfig(), InventoryOptimizer(AnalyticalSOCPBackend())
        )
        evaluation = pipeline.evaluate_routes(
            (VehicleRoute(1, 1, (2, 3)),), stations, vehicles, demand, uncertainty
        )
        self.assertEqual(evaluation.vehicle_plans, ())
        self.assertGreater(evaluation.unvisited_shortage_cost, 0)
        self.assertGreater(evaluation.total_cost, evaluation.transport_cost)


if __name__ == "__main__":
    unittest.main()
