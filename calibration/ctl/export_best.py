#!/usr/bin/env python3
"""把每个运行的前 N 名导成 txt, 一个运行一个文件 (ft1e-1.txt, ft2e-1.txt, ...)。

格式与 show_best.py 完全一致 —— 本脚本就是逐个运行去调它, 而不是把排版逻辑
再抄一遍, 所以将来改 show_best.py 的输出, 这里自动跟着变。

每个运行的判据 (population / middle_max / endpoint_band / seed) 从该运行自己的
config.json 读, 而不是用全局默认值 —— 扫 middle_max 这类字段时, 各运行的标尺
本来就不一样, 用错标尺排出来的名次是假的。

用法:
    module load python
    python3 calibration/ctl/export_best.py                 # 全部 ft*, 前十名
    python3 calibration/ctl/export_best.py --pattern 'eff*' --top 20
    python3 calibration/ctl/export_best.py --out /path/to/dir
    python3 calibration/ctl/export_best.py --csv           # 顺带每个运行一份 csv

默认输出目录: $MATFDM_RUNS/postprocess  (即 $SCRATCH/matfdm_runs/postprocess)
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CODE = HERE.parent.parent                       # 仓库根 (代码, 只读)
SHOW_BEST = HERE / "show_best.py"

sys.path.insert(0, str(HERE))
import run_id as R                              # noqa: E402  命名/排序的唯一权威


def runs_root() -> Path:
    root = os.environ.get("MATFDM_RUNS")
    if root:
        return Path(root)
    scratch = os.environ.get("SCRATCH", str(Path.home()))
    return Path(scratch) / "matfdm_runs"


def run_dirs(root: Path, pattern: str) -> list:
    """(目录, config) 列表, 按扫描值数值排序 —— 排序与命名规则都走 run_id.py。

    不能按目录名字典序: 位数一混就乱, ft1e0 (=1) 在字典序里排在 ft2e-1 (=0.2) 前面,
    和 front_thick 的大小顺序完全对不上。
    """
    pairs = []
    for d in root.glob(pattern):
        if not (d.is_dir() and (d / "config.json").is_file()):
            continue
        try:
            pairs.append((d, json.loads((d / "config.json").read_text())))
        except (OSError, ValueError):
            continue
    return R.sort_runs(pairs)[0]


def child_env(run: Path, cfg: dict) -> dict:
    """show_best.py 的运行环境: 数据根 + 该运行自己的判据。"""
    env = dict(os.environ)
    env["MATFDM_RUN"] = str(run)
    env["CALIB_REPO_DIR"] = str(run)            # propose_cmaes 从这里找 metrics/
    env["CALIB_POPULATION"] = str(cfg.get("population", 40))
    env["CALIB_MIDDLE_MAX"] = str(cfg.get("middle_max", 70))
    env["CALIB_ENDPOINT_BAND"] = str(cfg.get("endpoint_band", 5))
    env["CALIB_SEED"] = str(cfg.get("seed", 20260804))
    env["CALIB_OUT_DIR"] = str(run / "calibration" / "optimizer")
    env["CALIB_STATE_PATH"] = str(run / "calibration" / "state.json")
    return env


def header(run: Path, cfg: dict, n_eval: int) -> str:
    keys = ("run_id", "front_thick", "population", "workers", "doses", "targets",
            "middle_max", "endpoint_band", "endpoint_tol", "seed")
    lines = [
        "=" * 72,
        f"运行     : {run.name}      目录 {run}",
        f"导出时间 : {datetime.datetime.now().isoformat(timespec='seconds')}",
        f"已评估   : {n_eval} 个 case",
        "配置     : " + "  ".join(f"{k}={json.dumps(cfg[k], ensure_ascii=False)}"
                                  for k in keys if k in cfg),
    ]
    if cfg.get("overrides"):
        lines.append("覆盖     : " + json.dumps(cfg["overrides"], ensure_ascii=False))
    done = run / "calibration" / "DONE"
    if done.is_file():
        lines.append(f"命中     : {done.read_text().strip()}")
    lines += ["=" * 72, ""]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="逐运行导出前 N 名到 txt")
    ap.add_argument("--pattern", default="ft*", help="运行目录通配 (默认 ft*)")
    ap.add_argument("--top", type=int, default=10, help="每个运行取前几名 (默认 10)")
    ap.add_argument("--out", default="", help="输出目录 (默认 <数据根>/postprocess)")
    ap.add_argument("--csv", action="store_true", help="顺带导一份同名 csv")
    args = ap.parse_args()

    root = runs_root()
    pairs = run_dirs(root, args.pattern)
    swept = R.sweep_key([c for _, c in pairs])
    if not pairs:
        print(f"{root} 下没有匹配 {args.pattern!r} 且带 config.json 的运行", file=sys.stderr)
        return 1

    out = Path(args.out) if args.out else root / "postprocess"
    out.mkdir(parents=True, exist_ok=True)

    print(f"数据根 : {root}")
    print(f"输出到 : {out}")
    print(f"运行   : {len(pairs)} 个 ({args.pattern}), 每个取前 {args.top} 名")
    print(f"扫描   : {swept or '(认不出单一扫描字段, 按名字自然排序)'}\n")
    col = swept.split('.')[-1] if swept else '值'
    print(f"{'运行':<10s}{col:>10s}{'评估':>7s}{'可行':>7s}  {'最佳 fitness':>14s}  文件")

    ok = 0
    for run, cfg in pairs:
        n_eval = len(list((run / "calibration" / "metrics").glob("*.csv")))
        _sv = R.flatten(cfg).get(swept) if swept else None
        sval = f"{_sv:g}" if _sv is not None else "-"
        txt = out / f"{run.name}.txt"

        cmd = [sys.executable, str(SHOW_BEST), "--top", str(args.top)]
        if args.csv:
            cmd += ["--csv", str(out / f"{run.name}.csv")]
        proc = subprocess.run(cmd, env=child_env(run, cfg),
                              capture_output=True, text=True)
        body = proc.stdout
        if proc.returncode != 0 and not body.strip():
            body = "没有可评分的样本\n"
        if proc.stderr.strip():
            body += "\n--- show_best.py stderr ---\n" + proc.stderr

        txt.write_text(header(run, cfg, n_eval) + body, encoding="utf-8")

        # 摘要行: 从 show_best 的输出里抠出可行数与第一名的 fitness
        feasible = best = "-"
        for line in body.splitlines():
            if line.startswith("当前判据") and "可行" in line:
                feasible = line.split("可行")[-1].strip().rstrip(",")
            if line.startswith("#1 ") and "fitness=" in line:
                best = line.split("fitness=")[1].split()[0]
                break
        if proc.returncode == 0:
            ok += 1
        print(f"{run.name:<10s}{sval:>10s}{n_eval:>7d}{feasible:>7s}  "
              f"{best:>14s}  {txt.name}")

    print(f"\n{ok}/{len(pairs)} 个运行导出成功 -> {out}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
