#!/usr/bin/env python3
"""打印当前目标函数下最好的 N 个 case, 含每个参数的乘子与绝对值。

绝对值 = build_p_decouple.m 里的基线 × CMA 给的乘子, 与 run_calibration_case.m
里实际代入模型的值一致 (包括 DCr2O3 跟随 DCr2O3O、DO0 跟随 DSiO2 这两处绑定)。

用法 (仓库根目录):
    module load python
    CALIB_REPO_DIR=$PWD CALIB_POPULATION=40 python3 calibration/ctl/show_best.py
    ... show_best.py --top 3            只看前三
    ... show_best.py --csv best.csv     另存一份 csv
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CTRL = HERE.parent
RUN = Path(os.environ.get("MATFDM_RUN",
                          os.environ.get("CALIB_REPO_DIR", CTRL.parent)))
RUNCAL = RUN / "calibration"          # 本次运行的数据根 (代码目录只读)
STATE = RUNCAL / "state.json"
METRICS = RUNCAL / "metrics"
BUILD_P = CTRL.parent / "build_p_decouple.m"

# propose_cmaes 从 CALIB_REPO_DIR 定位 metrics/。多运行模式下它必须指向本次
# 运行的数据目录, 否则 evaluate_case 全部抛异常, 结果就是一句"没有可评分的样本"。
os.environ["CALIB_REPO_DIR"] = str(RUN)

NAMES = ["kCr", "kFe", "kSi", "kspin", "DCr2O3O", "DFe3O4",
         "DFeCr2O4", "DSiO2", "kRobin", "E_mag"]


def load_base() -> dict[str, float]:
    """从 build_p_decouple.m 里抓十个基线值 (取最后一次数值赋值)。"""
    if not BUILD_P.exists():
        return {}
    text = BUILD_P.read_text(errors="replace")
    base = {}
    for name in NAMES:
        hits = re.findall(rf"p\.{name}\s*=\s*([0-9.eE+-]+)\s*;", text)
        if hits:
            base[name] = float(hits[-1])
    return base


def load_pc():
    sys.path.insert(0, str(CTRL / "vendor"))
    spec = importlib.util.spec_from_file_location(
        "propose_cmaes", CTRL / "optimizer" / "propose_cmaes.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def metric_rows(tag: str):
    path = METRICS / f"{tag}.csv"
    if not path.exists():
        return None
    try:
        with path.open(newline="") as stream:
            data = sorted(csv.DictReader(stream), key=lambda r: float(r["dose"]))
        return data if len(data) == 3 else None
    except (OSError, ValueError):
        return None


def load_cfg() -> dict:
    f = RUN / "config.json"
    if not f.is_file():
        return {}
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--csv", default="")
    args = ap.parse_args()

    pc = load_pc()
    base = load_base()
    cfg = load_cfg()
    tg = cfg.get("composition_targets") or None       # 实验成分靶值 [[Cr%,Fe%],...]
    ctol = float(cfg.get("composition_tol", 5))
    ftg = cfg.get("targets") or [40, 60, 100]         # 前沿靶深度, 别写死
    doses = cfg.get("doses") or [0, 0.5, 3]
    if not STATE.is_file():           # 一代都没跑完的运行 (比如全程没抢到 license)
        print(f"还没有 state.json ({STATE}), 这个运行一代都没跑完")
        return 1
    state = json.loads(STATE.read_text())

    recs = []
    for key, cases in state.items():
        if not key.endswith("_cases") or not isinstance(cases, list):
            continue
        for case in cases:
            data = metric_rows(case["case_tag"])
            if data is None:
                continue
            try:
                recs.append((pc.evaluate_case(case), case, data))
            except Exception:
                continue
    if not recs:
        print("没有可评分的样本")
        return 1
    recs.sort(key=lambda t: (0 if t[0]["feasible"] else 1, t[0]["fitness"]))
    top = recs[:args.top]

    print(f"前沿判据: 靶 {'/'.join(f'{t:g}' for t in ftg)} nm, "
          f"0.5dpa 软带 [60, {pc.MIDDLE_MAX:g}] nm, "
          f"端点硬约束 ±{pc.ENDPOINT_BAND:g} nm")
    if tg:
        print("成分判据: 实验 at% (口径 Cr+Fe+Ni, SiO2 溶解不计), 命中容差 "
              f"±{ctol:g} at%, 权重标尺 /{pc.COMPOSITION_SCALE:g} (前沿端点 /3)")
        print("          靶值 " + "  ".join(
            f"{d:g}dpa Cr {c:.1f}/Fe {f:.1f}" for (c, f), d in zip(tg, doses)))
        # 模型不产 Ni, Cr%+Fe% 恒为 100, 而实验靶值之和小于 100 —— 差额就是地板
        floor = [100.0 - c - f for c, f in tg]
        if max(floor) > 0.05:
            print("          注: 模型 Ni≡0, 成分残差有地板 "
                  + "/".join(f"{x:.2f}" for x in floor) + " at% (缺的是 Ni)")
    else:
        print("成分判据: 未配置 composition_targets, 本次只标前沿")
    print(f"可行 {sum(1 for r, _, _ in recs if r['feasible'])}/{len(recs)}\n")

    for rank, (r, case, data) in enumerate(top, 1):
        front = [float(x["front_nm"]) for x in data]
        pct = [(float(x["Cr_atom_pct"]), float(x["Fe_atom_pct"]),
                float(x["Si_atom_pct"])) for x in data]
        inv = [float(x["Cr_atom_inventory"]) for x in data]
        print(f"#{rank}  {case['case_tag']}   fitness={r['fitness']:.4f}  "
              f"feasible={r['feasible']}")
        print(f"    前沿 nm   : {front[0]:7.2f} {front[1]:7.2f} {front[2]:7.2f}"
              f"    (靶 {' / '.join(f'{t:g}' for t in ftg)})")
        print("    残差 nm   : "
              + " ".join(f"{front[i]-ftg[i]:+7.2f}" for i in range(len(front))))
        for i, dose in enumerate((0, 0.5, 3)):
            line = (f"    {dose:>4} dpa  : Cr {pct[i][0]:5.1f}%  Fe {pct[i][1]:5.1f}%  "
                    f"Si {pct[i][2]:5.1f}%   Cr库存 {inv[i]:.4g}")
            if tg and i < len(tg):
                line += (f"   靶 {tg[i][0]:.1f}/{tg[i][1]:.1f}"
                         f"  Δ {pct[i][0]-tg[i][0]:+.1f}/{pct[i][1]-tg[i][1]:+.1f}")
            print(line)
        if tg:
            dcr = [pct[i][0] - tg[i][0] for i in range(min(len(pct), len(tg)))]
            dfe = [pct[i][1] - tg[i][1] for i in range(min(len(pct), len(tg)))]
            worst = max(max(abs(x) for x in dcr), max(abs(x) for x in dfe))
            print(f"    成分残差  : ΔCr {' '.join(f'{x:+6.2f}' for x in dcr)}"
                  f"   ΔFe {' '.join(f'{x:+6.2f}' for x in dfe)}"
                  f"   最大 |Δ| {worst:.2f} at%"
                  f"  {'命中' if worst <= ctol else '超差'}(±{ctol:g})")
        print(f"    {'参数':<10s}{'乘子':>10s}{'基线':>12s}{'绝对值':>14s}")
        mult = case["mult"]
        vals = {}
        for name, m in zip(NAMES, mult):
            b = base.get(name)
            v = b * m if b is not None else float("nan")
            vals[name] = v
            bs = f"{b:.4g}" if b is not None else "?"
            print(f"    {name:<10s}{m:10.4g}{bs:>12s}{v:14.6g}")
        if "DCr2O3O" in vals:
            print(f"    {'DCr2O3':<10s}{'(=DCr2O3O)':>10s}{'':>12s}{vals['DCr2O3O']:14.6g}")
        if "DSiO2" in vals:
            print(f"    {'DO0':<10s}{'(=DSiO2)':>10s}{'':>12s}{vals['DSiO2']:14.6g}")
        print()

    if args.csv:
        with open(args.csv, "w", newline="") as stream:
            w = csv.writer(stream)
            dl = [f"{d:g}" for d in doses]
            w.writerow(["rank", "case_tag", "fitness", "feasible",
                        "front0", "front05", "front3"]
                       + [f"Cr_pct_{d}" for d in dl]
                       + [f"Fe_pct_{d}" for d in dl]
                       + ([f"dCr_{d}" for d in dl] + [f"dFe_{d}" for d in dl]
                          + ["comp_max_abs_dev"] if tg else [])
                       + [f"mult_{n}" for n in NAMES]
                       + [f"val_{n}" for n in NAMES])
            for rank, (r, case, data) in enumerate(top, 1):
                front = [float(x["front_nm"]) for x in data]
                cr = [float(x["Cr_atom_pct"]) for x in data]
                fe = [float(x["Fe_atom_pct"]) for x in data]
                comp = []
                if tg:
                    dcr = [cr[i] - tg[i][0] for i in range(min(len(cr), len(tg)))]
                    dfe = [fe[i] - tg[i][1] for i in range(min(len(fe), len(tg)))]
                    comp = dcr + dfe + [max(max(map(abs, dcr)), max(map(abs, dfe)))]
                w.writerow([rank, case["case_tag"], r["fitness"], int(r["feasible"])]
                           + front + cr + fe + comp + list(case["mult"])
                           + [base.get(n, float('nan')) * m
                              for n, m in zip(NAMES, case["mult"])])
        print(f"已另存 {args.csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
