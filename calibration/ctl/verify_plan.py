#!/usr/bin/env python3
"""把"每个 ft 的前 N 名"展开成验证任务清单, 并规划节点分配。

任务 = (运行, case_tag, 剂量, 十个乘子)。总数 = 剂量数 x 运行数 x N,
默认 2 x 16 x 10 = 320。

节点规划: 每条腿单线程约 1.8 GB。一个 Perlmutter CPU 节点 128 物理核 / 503 GB,
所以按核算上限 128、按内存算上限约 270 —— 核是瓶颈。默认每节点 110 条留些余量,
节点数 = ceil(总数 / 每节点)。

用法:
    python3 verify_plan.py --runs $SCRATCH/matfdm_runs --top 10 --doses 0.5,1.5
    python3 verify_plan.py ... --out tasks.tsv --per-node 110
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path


def top_tags(txt: Path, top: int):
    """从 show_best 的输出里取前 N 名的 case_tag (行首形如 '#1  b04_c06_cma')。"""
    tags = []
    for line in txt.read_text(errors="replace").splitlines():
        m = re.match(r"^#(\d+)\s+(\S+)", line)
        if m:
            tags.append(m.group(2))
            if len(tags) >= top:
                break
    return tags


def mult_of(run: Path, tag: str):
    """从该运行的 state.json 里取这个 case 的十个乘子。"""
    st = run / "calibration" / "state.json"
    if not st.is_file():
        return None
    try:
        state = json.loads(st.read_text())
    except (OSError, ValueError):
        return None
    for key, cases in state.items():
        if not key.endswith("_cases") or not isinstance(cases, list):
            continue
        for c in cases:
            if c.get("case_tag") == tag:
                return [float(x) for x in c["mult"]]
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", required=True, help="标定数据根 ($SCRATCH/matfdm_runs)")
    ap.add_argument("--pattern", default="ft*")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--doses", default="0.5,1.5")
    ap.add_argument("--per-node", type=int, default=110)
    ap.add_argument("--out", default="", help="清单落盘路径 (不给只打印规划)")
    args = ap.parse_args()

    runs = Path(args.runs)
    doses = [float(x) for x in args.doses.split(",") if x.strip()]
    pp = runs / "postprocess"
    if not pp.is_dir():
        print(f"没有 {pp} —— 先在 NERSC 上跑 mf export", file=sys.stderr)
        return 1

    tasks, missing = [], []
    for txt in sorted(pp.glob(f"{args.pattern}.txt")):
        run = runs / txt.stem
        if not run.is_dir():
            continue
        tags = top_tags(txt, args.top)
        if not tags:
            print(f"  {txt.stem}: 排名表里没有名次行, 跳过", file=sys.stderr)
            continue
        for t in tags:
            m = mult_of(run, t)
            if m is None or len(m) != 10:
                missing.append(f"{txt.stem}/{t}")
                continue
            for d in doses:
                tasks.append((txt.stem, t, d, ",".join(repr(x) for x in m)))

    if missing:
        print(f"  ! {len(missing)} 个 case 在 state.json 里找不到乘子: "
              f"{', '.join(missing[:5])}{' ...' if len(missing) > 5 else ''}",
              file=sys.stderr)
    if not tasks:
        print("没有可跑的任务", file=sys.stderr)
        return 1

    n = len(tasks)
    nodes = max(1, math.ceil(n / args.per_node))
    per = math.ceil(n / nodes)
    print(f"任务   : {n} 条  ({len(doses)} 剂量 x "
          f"{len(set(t[0] for t in tasks))} 运行 x {args.top} 名)")
    print(f"规划   : {nodes} 节点 x 每节点 <= {per} 条 (上限 {args.per_node})")
    print(f"内存   : 每节点约 {per * 1.8:.0f} GB / 503 GB")
    print(f"核心   : 每节点 {per} 个单线程进程 / 128 物理核"
          + ("   <<< 超了, 会互相抢核" if per > 128 else ""))

    if args.out:
        with Path(args.out).open("w", newline="") as f:
            w = csv.writer(f, delimiter="\t")
            for r in tasks:
                w.writerow(r)
        print(f"清单   : {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
