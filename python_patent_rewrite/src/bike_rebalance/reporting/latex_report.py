"""Render a DispatchSchedule as a Chinese LaTeX report with TikZ/pgfplots figures.

The generated ``.tex`` uses ``ctexart`` and must be compiled with XeLaTeX.
Only standard-library Python is used; figures are pure TikZ/pgfplots code.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Iterable, Mapping

from ..models import DispatchSchedule, Station

VEHICLE_COLORS = ("blue", "red", "teal", "orange", "violet", "brown")


def _fmt(value: float, digits: int = 2) -> str:
    return f"{value:.{digits}f}"


def _tex_escape(text: object) -> str:
    return (
        str(text)
        .replace("\\", r"\textbackslash{}")
        .replace("_", r"\_")
        .replace("%", r"\%")
        .replace("&", r"\&")
        .replace("#", r"\#")
    )


def _scaled_positions(stations: Iterable[Station]) -> dict[int, tuple[float, float]]:
    stations = tuple(stations)
    lons = [s.longitude for s in stations]
    lats = [s.latitude for s in stations]
    lon_span = (max(lons) - min(lons)) or 1.0
    lat_span = (max(lats) - min(lats)) or 1.0
    return {
        s.station_id: (
            (s.longitude - min(lons)) / lon_span * 12.0,
            (s.latitude - min(lats)) / lat_span * 8.0,
        )
        for s in stations
    }


def _end_inventory(schedule: DispatchSchedule, stations: Iterable[Station]) -> dict[int, int]:
    """Inventory right after dispatch: last visit for visited stations, else initial."""

    end = {s.station_id: s.initial_inventory for s in stations}
    for plan in schedule.vehicle_plans:
        for visit in plan.visits:
            end[visit.station_id] = visit.inventory_after
    return end


def _objective_section(schedule: DispatchSchedule) -> str:
    evaluation = schedule.route_evaluation
    rows = [
        ("运输成本", evaluation.transport_cost),
        ("已访问站点鲁棒缺车成本", evaluation.robust_shortage_cost),
        ("未访问站点鲁棒损失", evaluation.unvisited_shortage_cost),
        ("鲁棒总目标", evaluation.total_cost),
    ]
    lines = [
        "\\section{目标函数分解}",
        "\\begin{table}[H]\\centering",
        "\\begin{tabular}{lr}",
        "\\toprule",
        "成本项 & 数值 \\\\",
        "\\midrule",
    ]
    lines += [f"{name} & {_fmt(value)} \\\\" for name, value in rows]
    lines += ["\\bottomrule", "\\end{tabular}", "\\caption{鲁棒调度目标分解}", "\\end{table}"]
    if schedule.simulation is not None:
        sim = schedule.simulation
        sim_rows = [
            ("运输成本", sim.transport_cost),
            ("缺车成本", sim.shortage_cost),
            ("溢出成本", sim.overflow_cost),
            ("日级仿真总成本", sim.total_cost),
        ]
        lines += [
            "\\begin{table}[H]\\centering",
            "\\begin{tabular}{lr}",
            "\\toprule",
            "成本项 & 数值 \\\\",
            "\\midrule",
        ]
        lines += [f"{name} & {_fmt(value)} \\\\" for name, value in sim_rows]
        lines += ["\\bottomrule", "\\end{tabular}", "\\caption{调度后日级库存回放成本}", "\\end{table}"]
    return "\n".join(lines)


def _route_figure(
    schedule: DispatchSchedule,
    stations: Iterable[Station],
    end_inventory: Mapping[int, int],
) -> str:
    stations = tuple(stations)
    positions = _scaled_positions(stations)
    depot_ids = {route.depot_station_id for route in schedule.routes}

    lines = [
        "\\section{车辆路线可视化}",
        "\\begin{figure}[H]\\centering",
        "\\begin{tikzpicture}[font=\\small]",
    ]
    for station in stations:
        x, y = positions[station.station_id]
        if station.station_id in depot_ids:
            style = "draw, rectangle, fill=gray!30, minimum size=8mm"
        else:
            style = "draw, circle, fill=blue!12, minimum size=7mm"
        label = f"调度后 {end_inventory[station.station_id]}"
        lines.append(
            f"  \\node[{style}, label=below:{{\\scriptsize {label}}}] "
            f"(s{station.station_id}) at ({x:.2f},{y:.2f}) {{{station.station_id}}};"
        )
    legend = []
    for index, route in enumerate(schedule.routes):
        color = VEHICLE_COLORS[index % len(VEHICLE_COLORS)]
        legend.append(f"\\textcolor{{{color}}}{{车辆 {route.vehicle_id}}}")
        path = (route.depot_station_id, *route.station_ids, route.depot_station_id)
        for step, (a, b) in enumerate(zip(path, path[1:])):
            bend = ", bend left=18" if step == len(path) - 2 else ""
            lines.append(f"  \\draw[->, very thick, {color}{bend}] (s{a}) -- (s{b});")
    lines += [
        "\\end{tikzpicture}",
        "\\caption{车辆调度路线（矩形为车场，圆形为服务站点，箭头为访问顺序）："
        + "；".join(legend)
        + "}",
        "\\end{figure}",
    ]
    return "\n".join(lines)


def _inventory_figure(
    schedule: DispatchSchedule,
    stations: Iterable[Station],
    end_inventory: Mapping[int, int],
) -> str:
    stations = tuple(sorted(stations, key=lambda s: s.station_id))
    ids = [str(s.station_id) for s in stations]
    before = "".join(f"({s.station_id},{s.initial_inventory})" for s in stations)
    after = "".join(f"({s.station_id},{end_inventory[s.station_id]})" for s in stations)
    capacity = stations[0].capacity
    return "\n".join(
        [
            "\\section{站点库存对比}",
            "\\begin{figure}[H]\\centering",
            "\\begin{tikzpicture}",
            "\\begin{axis}[",
            "    width=0.9\\textwidth, height=7cm,",
            "    ybar, bar width=7pt,",
            f"    symbolic x coords={{ {','.join(ids)} }},",
            "    xtick=data, xlabel={站点编号}, ylabel={库存（辆）},",
            f"    ymin=0, ymax={capacity + 4},",
            "    legend style={at={(0.5,1.03)}, anchor=south, legend columns=3},",
            "]",
            f"\\addplot+[ybar, fill=blue!50] coordinates {{{before}}};",
            f"\\addplot+[ybar, fill=orange!60] coordinates {{{after}}};",
            f"\\addplot[red, dashed, thick, no markers] coordinates {{({ids[0]},{capacity})({ids[-1]},{capacity})}};",
            "\\legend{调度前, 调度后, 容量上限}",
            "\\end{axis}",
            "\\end{tikzpicture}",
            "\\caption{调度前后各站点库存对比}",
            "\\end{figure}",
        ]
    )


def _vehicle_sections(schedule: DispatchSchedule) -> str:
    lines = ["\\section{车辆作业明细}"]
    routes = {route.vehicle_id: route for route in schedule.routes}
    for plan in schedule.vehicle_plans:
        route = routes.get(plan.vehicle_id)
        if route is not None:
            chain = " $\\rightarrow$ ".join(
                str(s) for s in (route.depot_station_id, *route.station_ids, route.depot_station_id)
            )
            lines.append(f"\\subsection{{车辆 {plan.vehicle_id}}}")
            lines.append(f"路线：{chain}\\\\")
        lines.append(f"起始载荷 {plan.starting_load} 辆，结束载荷 {plan.ending_load} 辆。")
        lines += [
            "\\begin{table}[H]\\centering",
            "\\begin{tabular}{cccccc}",
            "\\toprule",
            "序号 & 站点 & 取车 & 放车 & 调度前库存 & 调度后库存 \\\\",
            "\\midrule",
        ]
        for visit in plan.visits:
            lines.append(
                f"{visit.sequence} & {visit.station_id} & {visit.pickup} & {visit.dropoff}"
                f" & {visit.inventory_before} & {visit.inventory_after} \\\\"
            )
        lines += ["\\bottomrule", "\\end{tabular}", f"\\caption{{车辆 {plan.vehicle_id} 取放车明细}}", "\\end{table}"]
    return "\n".join(lines)


def _demand_section(schedule: DispatchSchedule) -> str:
    if not schedule.demand:
        return ""
    lines = [
        "\\section{需求估计}",
        "\\begin{table}[H]\\centering",
        "\\begin{tabular}{ccccc}",
        "\\toprule",
        "站点 & 日均净消耗 $\\mu$ & 标准差 $\\sigma$ & 观测数 & 活跃天数 \\\\",
        "\\midrule",
    ]
    for station_id in sorted(schedule.demand):
        d = schedule.demand[station_id]
        lines.append(
            f"{station_id} & {_fmt(d.mean)} & {_fmt(d.std)} & {d.observations} & {d.active_days} \\\\"
        )
    lines += ["\\bottomrule", "\\end{tabular}", "\\caption{基于历史事件的日需求统计}", "\\end{table}"]
    return "\n".join(lines)


def _diagnostics_section(schedule: DispatchSchedule) -> str:
    items = [(k, v) for k, v in schedule.diagnostics.items() if k != "lsans_trace"]
    if not items:
        return ""
    lines = [
        "\\section{算法诊断}",
        "\\begin{table}[H]\\centering",
        "\\begin{tabular}{ll}",
        "\\toprule",
        "指标 & 数值 \\\\",
        "\\midrule",
    ]
    for key, value in items:
        if isinstance(value, float):
            text = _fmt(value)
        elif isinstance(value, Mapping):
            text = "；".join(
                f"{_tex_escape(k)}={_fmt(v) if isinstance(v, float) else _tex_escape(v)}"
                for k, v in value.items()
            )
        else:
            text = _tex_escape(value)
        lines.append(f"\\texttt{{{_tex_escape(key)}}} & {text} \\\\")
    lines += ["\\bottomrule", "\\end{tabular}", "\\caption{LS-ANS 运行诊断}", "\\end{table}"]
    return "\n".join(lines)


def render_schedule_report(
    schedule: DispatchSchedule,
    stations: Iterable[Station],
    output_path: Path,
) -> Path:
    """Write a Chinese LaTeX report for ``schedule`` and return the ``.tex`` path."""

    stations = tuple(stations)
    end_inventory = _end_inventory(schedule, stations)
    sections = [
        "\\documentclass[11pt]{ctexart}",
        "\\usepackage[margin=2.5cm]{geometry}",
        "\\usepackage{booktabs}",
        "\\usepackage{float}",
        "\\usepackage{tikz}",
        "\\usepackage{pgfplots}",
        "\\pgfplotsset{compat=1.18}",
        "\\title{共享单车鲁棒再平衡调度报告}",
        "\\date{\\today}",
        "\\begin{document}",
        "\\maketitle",
        _objective_section(schedule),
        _route_figure(schedule, stations, end_inventory),
        _inventory_figure(schedule, stations, end_inventory),
        _vehicle_sections(schedule),
        _demand_section(schedule),
        _diagnostics_section(schedule),
        "\\end{document}",
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n\n".join(s for s in sections if s), encoding="utf-8")
    return output_path


def compile_tex(tex_path: Path, engine: str = "xelatex") -> Path | None:
    """Compile ``tex_path`` in place; return the PDF path, or None if unavailable/failed."""

    if shutil.which(engine) is None:
        return None
    result = subprocess.run(
        [engine, "-interaction=nonstopmode", tex_path.name],
        cwd=tex_path.parent,
        capture_output=True,
        text=True,
        timeout=300,
    )
    pdf_path = tex_path.with_suffix(".pdf")
    for suffix in (".aux", ".log", ".out"):
        try:
            tex_path.with_suffix(suffix).unlink(missing_ok=True)
        except OSError:
            pass
    if result.returncode != 0 or not pdf_path.exists():
        return None
    return pdf_path
