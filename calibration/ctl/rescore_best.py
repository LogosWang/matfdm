#!/usr/bin/env python3
"""改了目标函数之后, 用新公式重算 CMA 持久状态里的历史最优。

为什么需要:
  fitness_history.csv 每次 propose 都整表重算, 自动跟着新公式走;
  但 cma_state.pkl 里的 payload["best"] 是旧公式记下的一个快照。
  新旧标尺不一致时, 旧 best 会永远"赢", 于是 record_is_better 一直为假,
  stagnation_generations 一路累加, 满 8 代触发一次并非数据驱动的 restart。

做什么:
  用当前公式把所有已 tell 的代重新评一遍, 取真正的最优写回 payload["best"],
  并把 stagnation_generations 归零。不碰 ES 的均值/协方差/sigma —— 那些是
  按代内排序更新的, 单调变换不影响, 无需重建。

用法 (在仓库根目录, 且当前没有 propose 在跑的时候):
  CALIB_REPO_DIR=$PWD CALIB_POPULATION=40 python3 calibration/ctl/rescore_best.py
"""

from __future__ import annotations

import importlib.util
import json
import os
import pickle
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CTRL = HERE.parent
RUN = Path(os.environ.get("MATFDM_RUN",
                          os.environ.get("CALIB_REPO_DIR", CTRL.parent)))
RUNCAL = RUN / "calibration"          # 本次运行的数据根 (代码目录只读)
STATE = RUNCAL / "state.json"
PICKLE = RUNCAL / "optimizer" / "cma_state.pkl"

os.environ.setdefault("CALIB_REPO_DIR", str(RUN))
sys.path.insert(0, str(CTRL / "vendor"))

spec = importlib.util.spec_from_file_location(
    "propose_cmaes", CTRL / "optimizer" / "propose_cmaes.py")
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)


def main() -> int:
    if not PICKLE.exists():
        print("cma_state.pkl 不存在, 无需重算")
        return 0
    payload = pickle.loads(PICKLE.read_bytes())
    state = json.loads(STATE.read_text())
    told = payload.get("told_batches", [])
    if not told:
        print("还没有 tell 过任何一代, 无需重算")
        return 0

    old = payload.get("best") or {}
    best = None
    n = 0
    for batch in told:
        for record in pc.evaluate_batch(state, batch):
            n += 1
            if pc.record_is_better(record, best):
                best = {k: (v.tolist() if hasattr(v, "tolist") else v)
                        for k, v in record.items()}
    payload["best"] = best
    payload["stagnation_generations"] = 0
    pc.atomic_pickle(PICKLE, payload)

    print(f"重算 {n} 个样本 (覆盖 {len(told)} 代)")
    print(f"  旧 best: tag={old.get('case_tag')} objective={old.get('objective')}")
    print(f"  新 best: tag={best['case_tag']} objective={best['objective']:.4f} "
          f"feasible={best['feasible']}")
    print("  stagnation_generations 已归零")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
