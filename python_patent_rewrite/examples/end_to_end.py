"""Run the complete shared-bike robust rebalancing workflow.

Usage from this directory:
    python examples/end_to_end.py

The report is written to ``outputs/representative_schedule.tex`` and, when
XeLaTeX is available, compiled to ``outputs/representative_schedule.pdf``.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from bike_rebalance.config import CostConfig, LSANSConfig, PipelineConfig  # noqa: E402
from bike_rebalance.coordination import RebalancingPipeline  # noqa: E402
from bike_rebalance.inventory import AnalyticalSOCPBackend, InventoryOptimizer  # noqa: E402
from bike_rebalance.models import Station, TripEvent, Vehicle  # noqa: E402
from bike_rebalance.reporting import (  # noqa: E402
    compile_tex,
    render_route_map_svg,
    render_schedule_report,
)


def build_case() -> tuple[tuple[Station, ...], tuple[Vehicle, ...], tuple[TripEvent, ...]]:
    """Create a small deterministic case with two depots and six service stations."""

    locations = {
        1: (-73.5600, 45.5200),
        2: (-73.5500, 45.5200),
        3: (-73.5570, 45.5260),
        4: (-73.5530, 45.5140),
        5: (-73.5650, 45.5230),
        6: (-73.5450, 45.5270),
        7: (-73.5420, 45.5140),
        8: (-73.5680, 45.5130),
    }
    initial = {1: 20, 2: 20, 3: 4, 4: 26, 5: 8, 6: 22, 7: 6, 8: 24}
    stations = tuple(
        Station(station_id, lon, lat, initial[station_id], capacity=30)
        for station_id, (lon, lat) in locations.items()
    )
    vehicles = (
        Vehicle(vehicle_id=1, depot_station_id=1, capacity=25),
        Vehicle(vehicle_id=2, depot_station_id=2, capacity=25),
    )

    events: list[TripEvent] = []
    start_day = datetime(2026, 1, 5, 8, 0)
    service_stations = tuple(range(3, 9))
    for day_offset in range(6):
        day = start_day + timedelta(days=day_offset)
        for index, origin in enumerate(service_stations):
            count = 1 + (index + day_offset) % 3
            destination = service_stations[(index + day_offset + 1) % len(service_stations)]
            for event_index in range(count):
                events.append(
                    TripEvent(
                        start_station_id=origin,
                        end_station_id=destination,
                        start_time=day + timedelta(minutes=event_index * 3),
                        end_time=day + timedelta(minutes=event_index * 3 + 20),
                    )
                )
    return stations, vehicles, tuple(events)


def main() -> None:
    stations, vehicles, events = build_case()
    config = PipelineConfig(
        cost=CostConfig(
            shortage_cost=5.0,
            overflow_cost=5.0,
            transport_cost_per_km=0.1,
            station_capacity=30,
            vehicle_capacity=25,
            max_route_distance_km=25.0,
            work_time_hours=10.0,
        ),
        lsans=LSANSConfig(
            iterations=80,
            local_search_iterations=3,
            no_improvement_limit=25,
            random_seed=2026,
        ),
        uncertainty_kappa=1.0,
    )
    pipeline = RebalancingPipeline(config, InventoryOptimizer(AnalyticalSOCPBackend()))
    schedule = pipeline.run(stations, vehicles, events)

    for route in schedule.routes:
        chain = " -> ".join(
            str(s) for s in (route.depot_station_id, *route.station_ids, route.depot_station_id)
        )
        print(f"Vehicle {route.vehicle_id}: {chain}")
    evaluation = schedule.route_evaluation
    print(f"Transport cost:          {evaluation.transport_cost:.2f}")
    print(f"Robust shortage cost:    {evaluation.robust_shortage_cost:.2f}")
    print(f"Unvisited shortage cost: {evaluation.unvisited_shortage_cost:.2f}")
    print(f"Total objective:         {evaluation.total_cost:.2f}")

    tex_path = render_schedule_report(
        schedule, stations, ROOT / "outputs" / "representative_schedule.tex"
    )
    print(f"\nSaved LaTeX report to {tex_path}")
    pdf_path = compile_tex(tex_path)
    if pdf_path is not None:
        print(f"Compiled PDF report to {pdf_path}")
    else:
        print("XeLaTeX not available or compilation failed; compile the .tex with xelatex manually.")

    svg_path = render_route_map_svg(schedule, stations, ROOT / "outputs" / "route_map.svg")
    print(f"Saved route map to {svg_path}")


if __name__ == "__main__":
    main()
