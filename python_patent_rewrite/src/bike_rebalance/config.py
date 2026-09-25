"""Central configuration objects for the reproducible pipeline."""

from dataclasses import dataclass


@dataclass(frozen=True)
class CostConfig:
    """Economic and physical limits used by routing and inventory modules."""

    shortage_cost: float = 5.0
    overflow_cost: float = 5.0
    transport_cost_per_km: float = 0.1
    station_capacity: int = 30
    vehicle_capacity: int = 25
    service_time_minutes: float = 2.0
    max_route_distance_km: float = 400.0
    work_time_hours: float = 10.0


@dataclass(frozen=True)
class LSANSConfig:
    """Controls the adaptive large-neighborhood search."""

    iterations: int = 120
    local_search_iterations: int = 5
    no_improvement_limit: int = 35
    min_stations_per_vehicle: int = 1
    destroy_fraction: float = 0.25
    initial_temperature: float = 2.0
    cooling_rate: float = 0.97
    reaction_factor: float = 0.2
    random_seed: int = 42


@dataclass(frozen=True)
class SimulationConfig:
    """Controls the deterministic daily replay."""

    random_seed: int = 42
    apply_dispatch_once: bool = True


@dataclass(frozen=True)
class PipelineConfig:
    """Top-level settings shared by the end-to-end example."""

    cost: CostConfig = CostConfig()
    lsans: LSANSConfig = LSANSConfig()
    simulation: SimulationConfig = SimulationConfig()
    uncertainty_kappa: float = 1.0
