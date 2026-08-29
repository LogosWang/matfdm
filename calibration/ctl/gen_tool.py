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
RUN = Path(os.environ.get("MATFDM_RUN",
                          os.environ.get("CALIB_REPO_DIR", CTRL.parent)))
RUNCAL = RUN / "calibration"          # 本次运行的数据根 (代码目录只读)
METRICS = RUNCAL / "metrics"
STATE = RUNCAL / "state.json"
POPULATION = int(os.environ.get("CALIB_POPULATION", "30"))
MIDDLE_MAX = float(os.environ.get("CALIB_MIDDLE_MAX", "70"))   # 0.5 dpa 达标上限 nm


def _cfg(key, default):
    """<run>/config.json 里的字段, 读不到就用默认值。"""
    try:
        import json
        return json.loads((RUN / "config.json").read_text()).get(key, default)
    except (OSError, ValueError):
        return default


# 实验成分靶值 [[Cr%, Fe%], ...] 与命中容差 (at%)。由 comp_targets.py 从
# Composition_Dose.csv 换算, 口径 = Cr+Fe+Ni, 详见 extract_calibration_metrics。
COMPOSITION_TARGETS = _cfg("composition_targets", None)
COMPOSITION_TOL = float(os.environ.get("CALIB_COMPOSITION_TOL",
                                       _cfg("composition_tol", 5)))


NEEDED = ("dose", "front_nm", "comp_depth_nm",
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
    cr = [float(r["Cr_atom_pct"]) for r in data]
    fe = [float(r["Fe_atom_pct"]) for r in data]
    depth = [float(r.get("comp_depth_nm", 0) or 0) for r in data]
    ok_front = (abs(front[0] - 40.0) <= tol
                and 60.0 <= front[1] <= MIDDLE_MAX
                and abs(front[2] - 100.0) <= tol
                and all(f >= d for f, d in zip(front, depth)))   # 必须够得着取样深度
    if not ok_front:
        return False
    # 成分: 与实测 at% 逐点比 (旧版是 Cr>Fe、Cr>Si、Cr-Fe<=15 这几条定性代理,
    # 有了实验值就不需要了)。没配靶值的旧运行目录只判前沿, 保持向后兼容。
    if not COMPOSITION_TARGETS:
        return True
    for i, (tcr, tfe) in enumerate(COMPOSITION_TARGETS[:len(cr)]):
        if abs(cr[i] - tcr) > COMPOSITION_TOL or abs(fe[i] - tfe) > COMPOSITION_TOL:
            return False
    return True


def cmd_propose(batch: int) -> int:
    # 冷启动: propose_cmaes.py 上来就 read_text(state.json), 文件不存在直接崩。
    # 这里替它建一个空的, 让"第一次跑不需要任何手工准备"成立。
    if not STATE.exists():
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text("{}\n")
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
        fe = " ".join(f"{float(r['Fe_atom_pct']):5.1f}" for r in data)
        print(f"{tag}: front[{front}]  Cr%[{cr}]  Fe%[{fe}]")
    return 0


HEADER = ("dose,front_nm,residual_nm,comp_depth_nm,"
          "Cr2O3_int,Fe3O4_int,FeCr2O4_int,SiO2_int,"
          "Cr_atom_inventory,Fe_atom_inventory,Si_atom_inventory,Ni_atom_inventory,"
          "Cr_atom_pct,Fe_atom_pct,Si_atom_pct,Ni_atom_pct,Cr_atom_major")
TARGETS = (40.0, 60.0, 100.0)
DEPTHS = tuple(_cfg("composition_depth", [23, 30, 44]))


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
            # 前沿全 0 (残差最大) + 库存递增 (违反唯一的硬约束) + 成分离靶极远,
            # 于是排在所有可行样本之后, CMA 正常 tell 后继续推进。
            stream.write(f"{dose},0,{-target},{DEPTHS[i]},0,0,0,0,"
                         f"{inventory},{inventory},{inventory},0,"
                         f"10,90,0,0,0\n")
    print(f"PENALIZED {tag}")
    return 0


def cmd_rank(top: int) -> int:
    """用当前目标函数给全部历史样本重新评分排名。

    不读 fitness_history.csv —— 那是上一次 propose 时的快照, 改了目标函数之后
    要等下一次 propose 才刷新。这里直接调 propose_cmaes 现算, 所见即当前标尺。
    """
    import importlib.util
    import math
    sys.path.insert(0, str(CTRL / "vendor"))
    spec = importlib.util.spec_from_file_location(
        "propose_cmaes", CTRL / "optimizer" / "propose_cmaes.py")
    pc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pc)

    import json
    state = json.loads(STATE.read_text())
    recs = []
    for key, cases in state.items():
        if not key.endswith("_cases") or not isinstance(cases, list):
            continue
        for case in cases:
            data = rows(case["case_tag"])
            if data is None:
                continue
            try:
                recs.append((pc.evaluate_case(case), data))
            except Exception:
                continue
    if not recs:
        print("没有可评分的样本")
        return 0
    recs.sort(key=lambda t: (0 if t[0]["feasible"] else 1, t[0]["fitness"]))

    tg = COMPOSITION_TARGETS or []
    print(f"{'#':>3s} {'case':18s}{'fitness':>11s} {'可行':>5s}   "
          f"front 0 / 0.5 / 3 dpa    Cr/Fe% @3dpa  ΔCr/ΔFe")
    tg3 = f"{tg[2][0]:4.1f}/{tg[2][1]:4.1f}" if len(tg) > 2 else "  -/-  "
    print(f"{'':3s} {'--- 实验靶值 ---':18s}{'':11s} {'':5s}    40.0  60.0  100.0"
          f"     {tg3}")
    for i, (r, data) in enumerate(recs[:top], 1):
        f = [float(x["front_nm"]) for x in data]
        last = data[2]
        c3, f3 = float(last["Cr_atom_pct"]), float(last["Fe_atom_pct"])
        d = (f"{c3 - tg[2][0]:+5.1f}/{f3 - tg[2][1]:+5.1f}" if len(tg) > 2 else "")
        print(f"{i:3d} {r['case_tag']:18s}{r['fitness']:11.3f} {str(r['feasible']):>5s}   "
              f"{f[0]:5.1f} {f[1]:5.1f} {f[2]:6.1f}     {c3:4.1f}/{f3:4.1f}  {d}")
    nfeas = sum(1 for r, _ in recs if r["feasible"])
    print(f"\n可行 {nfeas}/{len(recs)}   "
          f"(0.5dpa 上限 {MIDDLE_MAX:g} nm, 端点硬约束 ±{getattr(pc,'ENDPOINT_BAND',float('nan')):g} nm"
          + (f", 成分靶值已加载, 容差 ±{COMPOSITION_TOL:g} at%)" if tg else ", 无成分靶值)"))
    best = recs[0][0]
    names = ["kCr", "kFe", "kSi", "kspin", "DCr2O3O", "DFe3O4",
             "DFeCr2O4", "DSiO2", "kRobin", "E_mag"]
    print("最优乘子: " + "  ".join(f"{n}={math.exp(x):.4g}"
                                   for n, x in zip(names, best["x"])))
    return 0


def cmd_validate_done(tol: float) -> int:
    """作业启动时复核 DONE 标记。

    命中判据会被收紧 (比如 0.5 dpa 上限 75 -> 70)。旧的 DONE 不复核的话会
    永久挡住后面每一个作业, 而且退出码是 0, 不看日志发现不了。
    这里按当前判据重判: 仍达标则保留并让作业退出; 已不达标则改名归档、继续跑。
    """
    done = RUNCAL / "DONE"
    if not done.exists():
        print("NO_DONE")
        return 0
    tags = [t.strip() for t in done.read_text().replace("\n", ",").split(",") if t.strip()]
    still = [t for t in tags if is_success(t, tol)]
    if still:
        print("DONE_VALID=" + ",".join(still))
        return 0
    from datetime import datetime
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archived = RUNCAL / f"DONE.stale.{stamp}"
    done.rename(archived)
    print(f"DONE_STALE_CLEARED tags={','.join(tags)} "
          f"(按当前判据已不达标, 归档为 {archived.name}, 继续优化)")
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
    diag_path = RUNCAL / "optimizer" / "cma_generation.json"
    pickle_path = RUNCAL / "optimizer" / "cma_state.pkl"
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
    hist = RUNCAL / "optimizer" / "fitness_history.csv"
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
    ap.add_argument("command", choices=("propose", "success", "report", "penalize",
                                        "penalize-missing", "history", "validate-done", "rank"))
    ap.add_argument("batch", type=int, nargs="?", default=0)
    ap.add_argument("--tol", type=float, default=3.0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--top", type=int, default=15)
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
    if args.command == "validate-done":
        return cmd_validate_done(args.tol)
    if args.command == "rank":
        return cmd_rank(args.top)
    if args.command == "history":
        return cmd_history(args.batch)
    return cmd_report(args.batch)


if __name__ == "__main__":
    raise SystemExit(main())
