"""Adaptive large-neighborhood search for multi-vehicle station routes."""

from dataclasses import dataclass
from math import exp
from random import Random
from typing import Callable, Mapping, Sequence

from ..config import CostConfig, LSANSConfig
from ..models import DemandEstimate, Station, Vehicle, VehicleRoute
from ..utils.randomness import make_rng
from .constraints import validate_routes
from .distance import route_distance_km
from .operators import relocate_station, reverse_segment, swap_stations


@dataclass(frozen=True)
class RoutePlan:
    """Search result with traceable acceptance and weight diagnostics."""

    routes: tuple[VehicleRoute, ...]
    objective: float
    iterations: int
    accepted_moves: int
    weights: Mapping[str, float]
    trace: tuple[Mapping[str, object], ...]


class LSANS:
    """LS-ANS implementation with explicit destroy/repair/local neighborhoods.

    The evaluator is injected by the coordination layer.  It therefore sees
    the full route-plus-inventory objective and the routing search does not
    silently optimize distance alone.
    """

    def __init__(
        self,
        stations: Mapping[int, Station],
        vehicles: Sequence[Vehicle],
        demand: Mapping[int, DemandEstimate],
        cost: CostConfig,
        config: LSANSConfig,
        evaluator: Callable[[tuple[VehicleRoute, ...]], float],
    ) -> None:
        self.stations = stations
        self.vehicles = tuple(vehicles)
        self.vehicle_map = {vehicle.vehicle_id: vehicle for vehicle in vehicles}
        self.demand = demand
        self.cost = cost
        self.config = config
        self.evaluator = evaluator
        self.rng = make_rng(config.random_seed)
        self.weights: dict[str, float] = {
            "destroy_random": 1.0,
            "destroy_worst": 1.0,
            "repair_random": 1.0,
            "repair_greedy": 1.0,
            "local_swap": 1.0,
            "local_relocate": 1.0,
            "local_reverse": 1.0,
        }

    def solve(self) -> RoutePlan:
        """Run deterministic adaptive search and return the best feasible plan."""

        current = self.initial_solution()
        current_cost = self.evaluator(current)
        best, best_cost = current, current_cost
        no_improvement = 0
        temperature = self.config.initial_temperature
        accepted = 0
        trace: list[Mapping[str, object]] = []

        for iteration in range(1, self.config.iterations + 1):
            destroy_name = self._choose("destroy_random", "destroy_worst")
            repair_name = self._choose("repair_random", "repair_greedy")
            destroyed = self._destroy(current, destroy_name)
            candidate = self._repair(destroyed, repair_name)
            local_name = self._choose("local_swap", "local_relocate", "local_reverse")
            candidate = self._local_improve(candidate, local_name)
            if not self._feasible(candidate):
                no_improvement += 1
                continue

            candidate_cost = self.evaluator(candidate)
            delta = candidate_cost - current_cost
            accept = delta <= 0 or self.rng.random() < exp(-delta / max(temperature, 1e-9))
            if accept:
                current, current_cost = candidate, candidate_cost
                accepted += 1
                self._update_weight(destroy_name, 3.0 if delta < 0 else 1.0)
                self._update_weight(repair_name, 3.0 if delta < 0 else 1.0)
                self._update_weight(local_name, 3.0 if delta < 0 else 1.0)
                no_improvement = 0 if candidate_cost < best_cost - 1e-9 else no_improvement + 1
                if candidate_cost < best_cost - 1e-9:
                    best, best_cost = candidate, candidate_cost
            else:
                no_improvement += 1
            trace.append(
                {
                    "iteration": iteration,
                    "destroy": destroy_name,
                    "repair": repair_name,
                    "local": local_name,
                    "candidate_cost": candidate_cost,
                    "accepted": accept,
                    "best_cost": best_cost,
                }
            )
            temperature *= self.config.cooling_rate
            if no_improvement >= self.config.no_improvement_limit:
                break

        return RoutePlan(
            routes=best,
            objective=best_cost,
            iterations=len(trace),
            accepted_moves=accepted,
            weights=dict(self.weights),
            trace=tuple(trace),
        )

    def initial_solution(self) -> tuple[VehicleRoute, ...]:
        """Assign high-risk stations greedily to their nearest current route."""

        routes = [
            VehicleRoute(vehicle.vehicle_id, vehicle.depot_station_id, ())
            for vehicle in self.vehicles
        ]
        depots = {vehicle.depot_station_id for vehicle in self.vehicles}
        candidates = [station_id for station_id in self.stations if station_id not in depots]
        candidates.sort(key=self._risk_score, reverse=True)
        for station_id in candidates:
            best_index = min(
                range(len(routes)),
                key=lambda index: self._append_distance(routes[index], station_id),
            )
            route = routes[best_index]
            routes[best_index] = VehicleRoute(
                route.vehicle_id,
                route.depot_station_id,
                route.station_ids + (station_id,),
            )
        return self._repair_minimum_tasks(tuple(routes))

    def _risk_score(self, station_id: int) -> float:
        estimate = self.demand[station_id]
        return abs(estimate.mean) / max(estimate.std, 1e-9)

    def _append_distance(self, route: VehicleRoute, station_id: int) -> float:
        trial = VehicleRoute(
            route.vehicle_id,
            route.depot_station_id,
            route.station_ids + (station_id,),
        )
        return route_distance_km(trial, self.stations)

    def _choose(self, *names: str) -> str:
        total = sum(self.weights[name] for name in names)
        draw = self.rng.random() * total
        for name in names:
            draw -= self.weights[name]
            if draw <= 0:
                return name
        return names[-1]

    def _destroy(self, routes: tuple[VehicleRoute, ...], name: str) -> tuple[VehicleRoute, ...]:
        mutable = [list(route.station_ids) for route in routes]
        all_positions = [(r, p) for r, route in enumerate(mutable) for p in range(len(route))]
        if not all_positions:
            return routes
        count = max(1, int(len(all_positions) * self.config.destroy_fraction))
        if name == "destroy_worst":
            all_positions.sort(
                key=lambda item: self._risk_score(mutable[item[0]][item[1]]), reverse=True
            )
        else:
            self.rng.shuffle(all_positions)
        for route_index, position in sorted(all_positions[:count], reverse=True):
            mutable[route_index].pop(position)
        return tuple(
            VehicleRoute(route.vehicle_id, route.depot_station_id, tuple(mutable[i]))
            for i, route in enumerate(routes)
        )

    def _repair(self, routes: tuple[VehicleRoute, ...], name: str) -> tuple[VehicleRoute, ...]:
        depots = {vehicle.depot_station_id for vehicle in self.vehicles}
        visited = {station_id for route in routes for station_id in route.station_ids}
        unvisited = [
            station_id
            for station_id in self.stations
            if station_id not in depots | visited
        ]
        if name == "repair_greedy":
            unvisited.sort(key=self._risk_score, reverse=True)
        else:
            self.rng.shuffle(unvisited)
        current = routes
        for station_id in unvisited:
            choices: list[tuple[float, int, int]] = []
            for route_index, route in enumerate(current):
                for position in range(len(route.station_ids) + 1):
                    trial = self._insert(current, route_index, position, station_id)
                    if self._feasible(trial):
                        choices.append((self.evaluator(trial), route_index, position))
            if choices:
                if name == "repair_greedy":
                    _, route_index, position = min(choices)
                else:
                    _, route_index, position = self.rng.choice(choices)
                current = self._insert(current, route_index, position, station_id)
        return self._repair_minimum_tasks(current)

    def _local_improve(
        self, routes: tuple[VehicleRoute, ...], name: str
    ) -> tuple[VehicleRoute, ...]:
        current = routes
        current_cost = self.evaluator(current)
        for _ in range(self.config.local_search_iterations):
            candidates = self._neighbors(current, name)
            improved = [
                (self.evaluator(candidate), candidate)
                for candidate in candidates
                if self._feasible(candidate)
            ]
            if not improved:
                break
            best_cost, best_candidate = min(improved, key=lambda item: item[0])
            if best_cost >= current_cost - 1e-9:
                break
            current, current_cost = best_candidate, best_cost
        return current

    def _neighbors(self, routes: tuple[VehicleRoute, ...], name: str):
        positions = [
            (r, p)
            for r, route in enumerate(routes)
            for p in range(len(route.station_ids))
        ]
        if name == "local_swap":
            pairs = (
                (x, y)
                for x in range(len(positions))
                for y in range(x + 1, len(positions))
            )
            for index, (first, second) in enumerate(pairs):
                yield swap_stations(routes, first, second)
                if index >= 30:
                    break
        elif name == "local_relocate":
            for source_route, source_pos in positions:
                for target_route, target in enumerate(routes):
                    for target_pos in range(len(target.station_ids) + 1):
                        if source_route == target_route and target_pos in (
                            source_pos,
                            source_pos + 1,
                        ):
                            continue
                        yield relocate_station(
                            routes,
                            source_route,
                            source_pos,
                            target_route,
                            target_pos,
                        )
        else:
            for route_index, route in enumerate(routes):
                for start in range(len(route.station_ids) - 1):
                    for end in range(start + 1, len(route.station_ids)):
                        yield reverse_segment(routes, route_index, start, end)

    def _insert(self, routes, route_index: int, position: int, station_id: int):
        updated = list(routes)
        route = updated[route_index]
        updated[route_index] = VehicleRoute(
            route.vehicle_id,
            route.depot_station_id,
            route.station_ids[:position] + (station_id,) + route.station_ids[position:],
        )
        return tuple(updated)

    def _repair_minimum_tasks(self, routes):
        # Keep the representation feasible for the minimum-task constraint by
        # moving stations from the longest route to an underfilled route.
        mutable = [list(route.station_ids) for route in routes]
        minimum = self.config.min_stations_per_vehicle
        for target in range(len(mutable)):
            while len(mutable[target]) < minimum:
                source = max(range(len(mutable)), key=lambda i: len(mutable[i]))
                if source == target or len(mutable[source]) <= minimum:
                    break
                mutable[target].append(mutable[source].pop())
        return tuple(
            VehicleRoute(route.vehicle_id, route.depot_station_id, tuple(mutable[i]))
            for i, route in enumerate(routes)
        )

    def _feasible(self, routes) -> bool:
        result = validate_routes(
            routes,
            self.stations,
            self.vehicle_map,
            self.cost,
            self.config,
        )
        return result.feasible

    def _update_weight(self, name: str, reward: float) -> None:
        old = self.weights[name]
        self.weights[name] = (
            (1 - self.config.reaction_factor) * old
            + self.config.reaction_factor * reward
        )
