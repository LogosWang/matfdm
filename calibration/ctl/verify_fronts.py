#!/usr/bin/env python3
"""前沿-时间曲线与实验对照 —— 逻辑与 calibration/postprocess_GB_oxidation.ipynb 一致。

对每个 (运行, case, 剂量) 读 fields_timeseries.mat 的时间序列, 按同一个 front_depth
定义算出前沿随时间的曲线, 插值到实验时间点算 MAE/RMSE, 出图并存表。

前沿定义 (与 notebook 逐字一致):
  沿 GB 深度自开口 y=0 起, 总氧化物厚度剖面**首次**跌破阈值处, 线性插值到亚网格。
  不能用"全域最接近阈值的点" —— 剖面尾部受零通量边界影响会轻微回升, 那样会跳到
  GB 末端。开口处就低于阈值 (尚未成膜) 记 0; 全域都不低于 (已穿透) 记 L_GB。

用法:
    python3 verify_fronts.py --root <验证数据根> [--out <图表目录>]
    python3 verify_fronts.py --root ... --ox-target 0.001
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
CODE = HERE.parent.parent
OXIDES = ["Cr2O3", "Fe3O4", "FeCr2O4", "SiO2"]
SEC_PER_HOUR = 3600.0
EXP_FMT = "Oxidationfront_Time{dose:g}dpa.csv"


def front_depth(y, prof, target, L):
    """与 notebook 的 front_depth 同一实现。"""
    if prof[0] < target:
        return 0.0
    below = np.flatnonzero(prof < target)
    if below.size == 0:
        return L
    j = below[0]
    return y[j - 1] + (prof[j - 1] - target) / (prof[j - 1] - prof[j]) * (y[j] - y[j - 1])


def read_series(mat: Path):
    """读 -v7.3 (HDF5) 的 fields_timeseries.mat -> (t_h, y, total_t, L_GB)。"""
    import h5py
    with h5py.File(mat, "r") as h:
        ny = int(h["p"]["ny"][0, 0])
        dy = float(h["p"]["dy"][0, 0])
        t = np.array(h["t_out"]).ravel() / SEC_PER_HOUR
        total = np.sum([np.array(h[f"{ox}_t"]) for ox in OXIDES], axis=0)
    y = np.arange(ny) * dy
    return t, y, total, ny * dy


def load_exp(root: Path, dose: float):
    for base in (root, CODE / "calibration", CODE):
        f = base / EXP_FMT.format(dose=dose)
        if f.is_file():
            a = np.atleast_2d(np.loadtxt(f, delimiter=",", skiprows=1))
            return a[np.argsort(a[:, 0])]
    return None


def acta_style():
    import matplotlib as mpl
    mm = 1 / 25.4
    mpl.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
        "font.size": 8, "axes.labelsize": 9, "axes.titlesize": 9,
        "xtick.labelsize": 8, "ytick.labelsize": 8, "legend.fontsize": 7.5,
        "lines.linewidth": 1.2, "axes.linewidth": 0.8,
        "xtick.major.width": 0.8, "ytick.major.width": 0.8,
        "xtick.direction": "in", "ytick.direction": "in",
        "xtick.top": True, "ytick.right": True,
        "legend.frameon": False, "savefig.dpi": 600, "savefig.bbox": "tight",
        "pdf.fonttype": 42, "ps.fonttype": 42,
    })
    return 90 * mm, 190 * mm


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="验证数据根 (下面是 <run>/<tag>/decouple/...)")
    ap.add_argument("--out", default="", help="图表输出目录 (默认 <root>/figures)")
    ap.add_argument("--ox-target", type=float, default=0.001,
                    help="前沿阈值: 总氧化物厚度 nm (notebook 默认 0.001)")
    ap.add_argument("--no-plot", action="store_true")
    args = ap.parse_args()

    root = Path(args.root)
    out = Path(args.out) if args.out else root / "figures"
    out.mkdir(parents=True, exist_ok=True)

    if not args.no_plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        SINGLE, DOUBLE = acta_style()
        SIM_C, EXP_C = "#0072B2", "#D55E00"

    rows = []
    # 布局: <root>/<ftXXX>/decouple/<tag>/dose<d>/fields_timeseries.mat
    for rundir in sorted(p for p in root.iterdir() if p.is_dir() and p.name != "figures"):
        for tagdir in sorted((rundir / "decouple").glob("*")) if (rundir / "decouple").is_dir() else []:
            if not tagdir.is_dir():
                continue
            for dd in sorted(tagdir.glob("dose*")):
                m = re.match(r"dose([\d.]+)$", dd.name)
                if not m:
                    continue
                dose = float(m.group(1))
                mat = dd / "fields_timeseries.mat"
                if not mat.is_file():
                    continue
                try:
                    t, y, total_t, L = read_series(mat)
                except Exception as e:
                    print(f"  ! {rundir.name}/{tagdir.name}/{dd.name}: 读不了 ({e})", file=sys.stderr)
                    continue

                fr = np.array([front_depth(y, prof, args.ox_target, L) for prof in total_t])
                exp = load_exp(root, dose)
                mae = rmse = float("nan")
                if exp is not None:
                    sim_at = np.interp(exp[:, 0], t, fr)
                    err = sim_at - exp[:, 1]
                    mae = float(np.abs(err).mean())
                    rmse = float(np.sqrt((err ** 2).mean()))

                rows.append(dict(run=rundir.name, case=tagdir.name, dose=dose,
                                 t_end_h=float(t[-1]), front_end_nm=float(fr[-1]),
                                 L_GB=float(L), mae_nm=mae, rmse_nm=rmse))

                np.savetxt(dd / "front_vs_time.csv",
                           np.column_stack([t, fr]), delimiter=",",
                           header="time_h,front_nm", comments="", fmt="%.6g")

                if args.no_plot:
                    continue
                fig, ax = plt.subplots(figsize=(SINGLE, 68 / 25.4), constrained_layout=True)
                ax.plot(t, fr, "-", color=SIM_C, label="Simulation")
                if exp is not None:
                    ax.plot(exp[:, 0], exp[:, 1], ls="none", marker="o", ms=5,
                            mfc="white", mec=EXP_C, mew=1.1, label="Experiment",
                            clip_on=False)
                ax.axhline(L, color="0.5", lw=0.8, ls=":", zorder=0)
                ax.text(0.98, L, f"$L_{{GB}}$ = {L:g} nm",
                        transform=ax.get_yaxis_transform(), ha="right", va="top",
                        fontsize=7, color="0.35")
                ax.set_xlabel("Oxidation time (h)")
                ax.set_ylabel("Oxidation front depth (nm)")
                ax.set_xlim(0, max(t[-1], exp[-1, 0] if exp is not None else 0) * 1.02)
                ax.set_ylim(0, L * 1.05)
                ttl = f"{rundir.name} / {tagdir.name}   {dose:g} dpa"
                if np.isfinite(mae):
                    ttl += f"   MAE {mae:.1f} nm"
                ax.set_title(ttl, fontsize=8)
                ax.legend(loc="lower right")
                stem = f"{rundir.name}_{tagdir.name}_dose{dose:g}dpa"
                for ext in ("png", "pdf"):
                    fig.savefig(out / f"front_vs_time_{stem}.{ext}")
                plt.close(fig)

    if not rows:
        print("没有找到任何 fields_timeseries.mat", file=sys.stderr)
        return 1

    rows.sort(key=lambda r: (r["run"], r["dose"], r["rmse_nm"]
                             if np.isfinite(r["rmse_nm"]) else 1e9))
    hdr = ["run", "case", "dose", "t_end_h", "front_end_nm", "L_GB", "mae_nm", "rmse_nm"]
    with (out / "front_summary.csv").open("w") as f:
        f.write(",".join(hdr) + "\n")
        for r in rows:
            f.write(",".join(f"{r[k]:.6g}" if isinstance(r[k], float) else str(r[k])
                             for k in hdr) + "\n")

    print(f"{'run':10s}{'case':16s}{'dpa':>5}{'末前沿':>9}{'MAE':>8}{'RMSE':>8}")
    for r in rows:
        print(f"{r['run']:10s}{r['case']:16s}{r['dose']:5g}"
              f"{r['front_end_nm']:9.1f}{r['mae_nm']:8.2f}{r['rmse_nm']:8.2f}")
    print(f"\n{len(rows)} 条曲线 -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
