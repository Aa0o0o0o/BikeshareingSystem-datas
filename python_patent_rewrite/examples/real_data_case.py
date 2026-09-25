"""Run the rebalancing workflow on real MATLAB-exported data.

Reads the CSVs produced by ``export_cluster_csv.m`` (cluster 2, May trips)
from ``examples/data/`` and renders the LaTeX report plus the SVG route map.

Usage from this directory:
    python examples/real_data_case.py
"""

from __future__ import annotations

import sys
from csv import DictReader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from bike_rebalance.config import CostConfig, LSANSConfig, PipelineConfig  # noqa: E402
from bike_rebalance.coordination import RebalancingPipeline  # noqa: E402
from bike_rebalance.data import load_trip_events_csv  # noqa: E402
from bike_rebalance.inventory import AnalyticalSOCPBackend, InventoryOptimizer  # noqa: E402
from bike_rebalance.models import Station, Vehicle  # noqa: E402
from bike_rebalance.reporting import (  # noqa: E402
    compile_tex,
    render_route_map_svg,
    render_schedule_report,
)

DATA_DIR = Path(__file__).resolve().parent / "data"
STATIONS_CSV = DATA_DIR / "cluster2_stations.csv"
TRIPS_CSV = DATA_DIR / "cluster2_may_trips.csv"
N_VEHICLES = 2


def load_stations(path: Path) -> tuple[Station, ...]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(DictReader(handle))
    return tuple(
        Station(
            station_id=int(row["station_id"]),
            longitude=float(row["longitude"]),
            latitude=float(row["latitude"]),
            initial_inventory=int(float(row["initial_inventory"])),
            capacity=30,
        )
        for row in rows
    )


def main() -> None:
    stations = load_stations(STATIONS_CSV)
    events = load_trip_events_csv(TRIPS_CSV)
    print(f"Loaded {len(stations)} stations, {len(events)} real trips from {TRIPS_CSV.name}")

    depot_ids = tuple(
        s.station_id
        for s in sorted(stations, key=lambda s: s.initial_inventory, reverse=True)[:N_VEHICLES]
    )
    vehicles = tuple(
        Vehicle(vehicle_id=i + 1, depot_station_id=depot_id, capacity=25)
        for i, depot_id in enumerate(depot_ids)
    )
    print(f"Depots (highest initial inventory): {depot_ids}")

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
        schedule, stations, ROOT / "outputs" / "real_cluster2_report.tex"
    )
    print(f"\nSaved LaTeX report to {tex_path}")
    pdf_path = compile_tex(tex_path)
    if pdf_path is not None:
        print(f"Compiled PDF report to {pdf_path}")
    else:
        print("XeLaTeX not available or compilation failed; compile the .tex with xelatex manually.")

    svg_path = render_route_map_svg(schedule, stations, ROOT / "outputs" / "real_cluster2_route_map.svg")
    print(f"Saved route map to {svg_path}")


if __name__ == "__main__":
    main()
