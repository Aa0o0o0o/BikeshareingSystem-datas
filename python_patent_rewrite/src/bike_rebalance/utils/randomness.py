"""Deterministic random-number helper."""

import random


def make_rng(seed: int) -> random.Random:
    """Return an isolated RNG so callers do not mutate global random state."""

    return random.Random(seed)
