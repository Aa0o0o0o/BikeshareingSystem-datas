from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from bike_rebalance.config import CostConfig, LSANSConfig, PipelineConfig  # noqa: E402
from bike_rebalance.coordination import RebalancingPipeline  # noqa: E402
from bike_rebalance.inventory import AnalyticalSOCPBackend, InventoryOptimizer  # noqa: E402
from bike_rebalance.models import Station, TripEvent, Vehicle  # noqa: E402
from bike_rebalance.reporting import (  # noqa: E402
    render_route_map_svg,
    render_schedule_report,
)


class ReportingTests(unittest.TestCase):
    def _run_pipeline(self):
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
        return pipeline.run(stations, vehicles, events), stations

    def test_report_contains_all_sections(self):
        schedule, stations = self._run_pipeline()
        with tempfile.TemporaryDirectory() as tmp:
            tex_path = render_schedule_report(schedule, stations, Path(tmp) / "report.tex")
            content = tex_path.read_text(encoding="utf-8")
        for marker in (
            "\\documentclass[11pt]{ctexart}",
            "\\end{document}",
            "目标函数分解",
            "车辆路线可视化",
            "站点库存对比",
            "车辆作业明细",
            "\\begin{axis}",
            "\\draw[->",
        ):
            self.assertIn(marker, content)

    def test_report_lists_every_station_and_visit(self):
        schedule, stations = self._run_pipeline()
        with tempfile.TemporaryDirectory() as tmp:
            tex_path = render_schedule_report(schedule, stations, Path(tmp) / "report.tex")
            content = tex_path.read_text(encoding="utf-8")
        for station in stations:
            self.assertIn(f"(s{station.station_id}) at", content)
        for plan in schedule.vehicle_plans:
            for visit in plan.visits:
                self.assertIn(
                    f"{visit.sequence} & {visit.station_id} & {visit.pickup} & {visit.dropoff}",
                    content,
                )
    def test_route_map_svg_lists_every_station_and_vehicle(self):
        schedule, stations = self._run_pipeline()
        with tempfile.TemporaryDirectory() as tmp:
            svg_path = render_route_map_svg(schedule, stations, Path(tmp) / "route_map.svg")
            content = svg_path.read_text(encoding="utf-8")
        self.assertIn("<svg", content)
        for station in stations:
            self.assertIn(f">{station.station_id}</text>", content)
        for route in schedule.routes:
            self.assertIn(f"车辆 {route.vehicle_id}（车场 {route.depot_station_id}）", content)


if __name__ == "__main__":
    unittest.main()
