"""Render the vehicle routes of a DispatchSchedule as a standalone SVG map.

Pure standard library: no matplotlib/Pillow required. The SVG can be viewed
in any browser and rasterized to PNG with headless Chrome/Edge when needed.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable, Mapping

from ..models import DispatchSchedule, Station

SVG_COLORS = ("#2563eb", "#dc2626", "#0d9488", "#ea580c", "#7c3aed", "#92400e")

_WIDTH, _HEIGHT, _MARGIN = 960, 640, 90
_NODE_R = 18


def _project(stations: Iterable[Station]) -> dict[int, tuple[float, float]]:
    """Project lon/lat to canvas pixels; y axis points up (north)."""

    stations = tuple(stations)
    mean_lat = math.radians(sum(s.latitude for s in stations) / len(stations))
    xs = [s.longitude * math.cos(mean_lat) for s in stations]
    ys = [s.latitude for s in stations]
    x_span = (max(xs) - min(xs)) or 1.0
    y_span = (max(ys) - min(ys)) or 1.0
    scale = min((_WIDTH - 2 * _MARGIN) / x_span, (_HEIGHT - 2 * _MARGIN) / y_span)
    x_off = (_WIDTH - x_span * scale) / 2
    y_off = (_HEIGHT - y_span * scale) / 2
    return {
        s.station_id: (x_off + (x - min(xs)) * scale, _HEIGHT - (y_off + (y - min(ys)) * scale))
        for s, x, y in zip(stations, xs, ys)
    }


def _trimmed_segment(
    a: tuple[float, float], b: tuple[float, float], trim: float
) -> tuple[float, float, float, float]:
    """Shorten segment a->b by ``trim`` px at both ends so arrows clear the nodes."""

    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy) or 1.0
    ux, uy = dx / length, dy / length
    return (a[0] + ux * trim, a[1] + uy * trim, b[0] - ux * trim, b[1] - uy * trim)


def _segment_svg(
    a: tuple[float, float],
    b: tuple[float, float],
    color: str,
    curved: bool,
) -> str:
    x1, y1, x2, y2 = _trimmed_segment(a, b, _NODE_R + 2)
    if not curved:
        return (
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{color}" stroke-width="3" marker-end="url(#arrow-{color.lstrip("#")})"/>'
        )
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1.0
    cx, cy = mx - dy / length * 30, my + dx / length * 30
    return (
        f'<path d="M{x1:.1f},{y1:.1f} Q{cx:.1f},{cy:.1f} {x2:.1f},{y2:.1f}" fill="none" '
        f'stroke="{color}" stroke-width="3" marker-end="url(#arrow-{color.lstrip("#")})"/>'
    )


def render_route_map_svg(
    schedule: DispatchSchedule,
    stations: Iterable[Station],
    output_path: Path,
) -> Path:
    """Write an SVG route map for ``schedule`` and return its path."""

    stations = tuple(stations)
    positions = _project(stations)
    depot_ids = {route.depot_station_id for route in schedule.routes}
    end_inventory = {s.station_id: s.initial_inventory for s in stations}
    for plan in schedule.vehicle_plans:
        for visit in plan.visits:
            end_inventory[visit.station_id] = visit.inventory_after

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{_WIDTH}" height="{_HEIGHT}" '
        f'viewBox="0 0 {_WIDTH} {_HEIGHT}" font-family="Microsoft YaHei, sans-serif">',
        f'<rect width="{_WIDTH}" height="{_HEIGHT}" fill="white"/>',
        "<defs>",
    ]
    for color in SVG_COLORS:
        marker_id = color.lstrip("#")
        parts.append(
            f'<marker id="arrow-{marker_id}" viewBox="0 0 10 10" refX="9" refY="5" '
            f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{color}"/></marker>'
        )
    parts.append("</defs>")

    parts.append(
        f'<text x="{_WIDTH / 2:.0f}" y="36" text-anchor="middle" font-size="20" '
        'font-weight="bold">车辆调度路线图</text>'
    )

    for index, route in enumerate(schedule.routes):
        color = SVG_COLORS[index % len(SVG_COLORS)]
        path = (route.depot_station_id, *route.station_ids, route.depot_station_id)
        for step, (a, b) in enumerate(zip(path, path[1:])):
            curved = step == len(path) - 2
            parts.append(_segment_svg(positions[a], positions[b], color, curved))

    for station in stations:
        x, y = positions[station.station_id]
        if station.station_id in depot_ids:
            parts.append(
                f'<rect x="{x - _NODE_R:.1f}" y="{y - _NODE_R:.1f}" '
                f'width="{2 * _NODE_R}" height="{2 * _NODE_R}" rx="4" '
                'fill="#d1d5db" stroke="#374151" stroke-width="2"/>'
            )
        else:
            parts.append(
                f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{_NODE_R}" '
                'fill="#dbeafe" stroke="#1e3a8a" stroke-width="2"/>'
            )
        parts.append(
            f'<text x="{x:.1f}" y="{y + 5:.1f}" text-anchor="middle" '
            f'font-size="15" font-weight="bold" fill="#111827">{station.station_id}</text>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{y + _NODE_R + 16:.1f}" text-anchor="middle" '
            f'font-size="12" fill="#4b5563">调度后 {end_inventory[station.station_id]}</text>'
        )

    legend_y = 64
    parts.append(
        f'<rect x="24" y="{legend_y - 20}" width="150" '
        f'height="{28 * len(schedule.routes) + 12}" fill="white" '
        'stroke="#d1d5db" rx="6" opacity="0.9"/>'
    )
    for index, route in enumerate(schedule.routes):
        color = SVG_COLORS[index % len(SVG_COLORS)]
        y = legend_y + index * 28
        parts.append(f'<line x1="36" y1="{y}" x2="66" y2="{y}" stroke="{color}" stroke-width="3"/>')
        parts.append(
            f'<text x="74" y="{y + 5}" font-size="14" fill="#111827">'
            f'车辆 {route.vehicle_id}（车场 {route.depot_station_id}）</text>'
        )
    parts.append("</svg>")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(parts), encoding="utf-8")
    return output_path
