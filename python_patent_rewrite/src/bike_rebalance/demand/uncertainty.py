"""Moment-based ambiguity sets and robust shortage calculations."""

from math import sqrt
from typing import Mapping

from ..models import DemandEstimate, UncertaintySet


def build_uncertainty_sets(
    demand: Mapping[int, DemandEstimate],
    kappa: float = 1.0,
) -> dict[int, UncertaintySet]:
    """Construct a station-wise moment ambiguity set.

    The radius is ``kappa * sigma``.  The object retains both the original
    standard deviation and the radius so downstream explanations can state
    exactly which uncertainty parameter was used.
    """

    if kappa < 0:
        raise ValueError("kappa must be non-negative")
    return {
        station_id: UncertaintySet(
            station_id=station_id,
            mean=estimate.mean,
            radius=kappa * max(estimate.std, 0.0),
            std=max(estimate.std, 0.0),
            kappa=kappa,
        )
        for station_id, estimate in demand.items()
    }


def robust_shortage_units(
    inventory: float,
    uncertainty: UncertaintySet,
) -> float:
    """Evaluate the fixed-inventory moment-robust shortage expression.

    For ``d`` with mean ``mu`` and radius ``rho``, the expression is
    ``0.5 * (mu-s + sqrt((s-mu)^2 + rho^2))``.  It is the analytical form of
    the fixed-route SOC epigraph used by the default solver backend.
    """

    gap = uncertainty.mean - inventory
    return 0.5 * (gap + sqrt(gap * gap + uncertainty.radius**2))


def robust_shortage_cost(
    inventory: float,
    uncertainty: UncertaintySet,
    unit_cost: float,
) -> float:
    """Return robust shortage loss in cost units."""

    return unit_cost * robust_shortage_units(inventory, uncertainty)
