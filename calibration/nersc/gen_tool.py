#!/usr/bin/env python3
"""In-job 驱动 (run_generation.m) 的代级助手。

子命令:
  propose <batch>              CMA-ES ask, 把 batchNN_cases 写进 state.json (幂等)
  success <batch> [--tol T]    判本代是否命中, 打印 WINNERS=<tag,tag> (无则空)
  report  <batch>              打印本代每个 case 的前沿/占比, 供人看
  penalize <batch> --tag TAG   给跑不出来的 case 写"最差且不可行"的指标, 让 CMA
                               把它排在末位并继续推进, 而不是整代卡死
  penalize-missing <batch>     把本代所有缺指标的 case 一次性惩罚 (propose 卡住时的解锁)
  history <batch>              打印续跑摘要: 已 tell 的代、sigma、历史最优及其乘子

MATLAB 侧只用 system() 调本脚本 + jsondecode 读 state.json, 不做优化逻辑。
"""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CTRL = HERE.parent
RUN = Path(os.environ.get("CALIB_REPO_DIR", CTRL.parent))
METRICS = RUN / "calibration" / "metrics"
STATE = CTRL / "state.json"
POPULATION = int(os.environ.get("CALIB_POPULATION", "30"))


NEEDED = ("dose", "front_nm", "Cr_atom_inventory",
          "Cr_atom_pct", "Fe_atom_pct", "Si_atom_pct")


def rows(tag: str):
    """读一个 case 的指标; 任何残缺/畸形都返回 None (视作没跑, 会被重跑或熔断)。"""
    path = METRICS / f"{tag}.csv"
    if not path.exists():
        return None
    try:
        with path.open(newline="") as stream:
            data = sorted(csv.DictReader(stream), key=lambda r: float(r["dose"]))
        if len(data) != 3 or not set(NEEDED).issubset(data[0]):
            return None
        for row in data:                      # 每个字段都必须是有限数
            for key in NEEDED:
                value = float(row[key])
                if value != value or value in (float("inf"), float("-inf")):
                    return None
        return data
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        return None


def case_tags(batch: int) -> list[str]:
    import json
    state = json.loads(STATE.read_text())
    key = f"batch{batch:02d}_cases"
    if key not in state:
        raise SystemExit(f"state.json 缺 {key}")
    return [c["case_tag"] for c in state[key]]


def is_success(tag: str, tol: float) -> bool:
    data = rows(tag)
    if data is None:
        return False
    front = [float(r["front_nm"]) for r in data]
    inv = [float(r["Cr_atom_inventory"]) for r in data]
    cr = [float(r["Cr_atom_pct"]) for r in data]
    fe = [float(r["Fe_atom_pct"]) for r in data]
    si = [float(r["Si_atom_pct"]) for r in data]
    return (abs(front[0] - 40.0) <= tol
            and 60.0 <= front[1] <= 75.0
            and abs(front[2] - 100.0) <= tol
            and all(c > max(f, s) for c, f, s in zip(cr, fe, si))
            and cr[2] - fe[2] <= 15.0
            and inv[0] > inv[1] > inv[2])


def cmd_propose(batch: int) -> int:
    env = os.environ.copy()
    env.update({"CALIB_REPO_DIR": str(RUN),
                "CALIB_BATCH_NO": str(batch),
                "CALIB_POPULATION": str(POPULATION)})
    proc = subprocess.run([sys.executable, str(CTRL / "optimizer" / "propose_cmaes.py")],
                          env=env, text=True, capture_output=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout[-4000:] + proc.stderr[-4000:])
        return proc.returncode
    kind = "ASKED"
    try:
        import json
        payload = json.loads(proc.stdout)
        if payload.get("adopted_existing"):
            kind = "ADOPTED_EXISTING(磁盘已有本代提案, 未重新 ask)"
        elif payload.get("idempotent"):
            kind = "REEMITTED_PENDING(原样重发, 未推进一代)"
    except Exception:
        pass
    print(f"PROPOSED batch={batch} pop={POPULATION} {kind}")
    return 0


def cmd_success(batch: int, tol: float) -> int:
    winners = [t for t in case_tags(batch) if is_success(t, tol)]
    print("WINNERS=" + ",".join(winners))
    return 0


def cmd_report(batch: int) -> int:
    for tag in case_tags(batch):
        data = rows(tag)
        if data is None:
            print(f"{tag}: no metrics")
            continue
        front = " ".join(f"{float(r['front_nm']):6.1f}" for r in data)
        cr = " ".join(f"{float(r['Cr_atom_pct']):5.1f}" for r in data)
        print(f"{tag}: front[{front}]  Cr%[{cr}]")
    return 0


HEADER = ("dose,front_nm,residual_nm,Cr2O3_int,Fe3O4_int,FeCr2O4_int,SiO2_int,"
          "Cr_atom_inventory,Fe_atom_inventory,Si_atom_inventory,"
          "Cr_atom_pct,Fe_atom_pct,Si_atom_pct,Cr_atom_major")
TARGETS = (40.0, 60.0, 100.0)


def cmd_penalize(tag: str) -> int:
    """跑不出结果的 case: 前沿全 0(残差最大) + 库存递增 + Fe>Cr (硬约束全违反),
    于是 lexicographic 排序把它放在所有可行样本之后, CMA 正常 tell 后前进。"""
    METRICS.mkdir(parents=True, exist_ok=True)
    path = METRICS / f"{tag}.csv"
    if path.exists():
        print(f"PENALIZE skipped (metrics exist): {tag}")
        return 0
    with path.open("w", newline="") as stream:
        stream.write(HEADER + "\n")
        for i, (dose, target) in enumerate(zip((0, 0.5, 3), TARGETS)):
            inventory = 1.0 + i          # 递增 => 违反 Cr 库存单调下降
            stream.write(f"{dose},0,{-target},0,0,0,0,"
                         f"{inventory},{inventory},{inventory},"
                         f"10,80,10,0\n")   # Fe% > Cr% => 违反成分约束
    print(f"PENALIZED {tag}")
    return 0


def cmd_penalize_missing(batch: int) -> int:
    n = 0
    for tag in case_tags(batch):
        if rows(tag) is None:
            cmd_penalize(tag)
            n += 1
    print(f"PENALIZED_MISSING batch={batch} n={n}")
    return 0


def cmd_history(batch: int) -> int:
    """续跑摘要: CMA 的持久状态 + 全历史 fitness, 让人一眼看出从哪捡起来的。"""
    import json
    names = ["kCr", "kFe", "kSi", "kspin", "DCr2O3O", "DFe3O4",
             "DFeCr2O4", "DSiO2", "kRobin", "E_mag"]
    diag_path = CTRL / "optimizer" / "cma_generation.json"
    pickle_path = CTRL / "optimizer" / "cma_state.pkl"
    print(f"RESUME batch={batch} "
          f"cma_state={'present' if pickle_path.exists() else 'ABSENT(将由历史指标重建)'}")
    if diag_path.exists():
        d = json.loads(diag_path.read_text())
        print(f"  generations_told={d.get('generation_told')} "
              f"pending={d.get('pending_batch')} restarts={d.get('restart_count')} "
              f"sigma={d.get('sigma'):.4g} cond={d.get('covariance_condition'):.3g} "
              f"stagnation={d.get('stagnation_generations')}")
        best = d.get("best") or {}
        if best:
            mult = [f"{n}={v:.3g}" for n, v in zip(names, np_exp(best.get("x", [])))]
            print(f"  best: tag={best.get('case_tag')} feasible={best.get('feasible')} "
                  f"objective={best.get('objective'):.4g}")
            print("  best multipliers: " + "  ".join(mult))
    hist = CTRL / "optimizer" / "fitness_history.csv"
    if hist.exists():
        with hist.open(newline="") as stream:
            data = list(csv.DictReader(stream))
        by_batch: dict[str, list[float]] = {}
        for row in data:
            by_batch.setdefault(row["batch"], []).append(float(row["fitness"]))
        print(f"  fitness_history: {len(data)} 条评估, 覆盖 {len(by_batch)} 代")
        for key in sorted(by_batch, key=int):
            values = by_batch[key]
            feas = sum(1 for row in data
                       if row["batch"] == key and row["feasible"] == "1")
            print(f"    gen {int(key):02d}: best={min(values):12.4g} "
                  f"median={sorted(values)[len(values)//2]:12.4g} feasible={feas}/{len(values)}")
    n_metrics = len(list(METRICS.glob("*.csv"))) if METRICS.exists() else 0
    print(f"  metrics on disk: {n_metrics} cases")
    return 0


def np_exp(x):
    import math
    return [math.exp(v) for v in x]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=("propose", "success", "report",
                                        "penalize", "penalize-missing", "history"))
    ap.add_argument("batch", type=int)
    ap.add_argument("--tol", type=float, default=3.0)
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    if args.command == "propose":
        return cmd_propose(args.batch)
    if args.command == "success":
        return cmd_success(args.batch, args.tol)
    if args.command == "penalize":
        if not args.tag:
            raise SystemExit("penalize 需要 --tag")
        return cmd_penalize(args.tag)
    if args.command == "penalize-missing":
        return cmd_penalize_missing(args.batch)
    if args.command == "history":
        return cmd_history(args.batch)
    return cmd_report(args.batch)


if __name__ == "__main__":
    raise SystemExit(main())
