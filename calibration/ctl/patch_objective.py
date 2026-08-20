#!/usr/bin/env python3
"""一次性把标定目标函数升级到"端点硬约束 + 中间腿全程有梯度"。

改三处, 全部幂等 (重复运行不会叠加):

1) propose_cmaes.py 顶部常量
   MIDDLE_MAX     0.5 dpa 软带上限, 默认 70 nm
   ENDPOINT_BAND  端点容差, 默认 5 nm

2) 0.5 dpa 残差: 最小值在 60, 分段连续, 全程有梯度
     < 60          (60-m)/5      深度不足也罚, 符号修正 (旧版给的是负残差)
     [60, 70]      (m-60)/6      端点是 1/3, 取一半: 进带后仍持续朝 60 推,
                                 又不至于压倒端点 (旧版 1/30 只有端点的十分之一)
     > 70          10/6+(m-70)/4 在 70 处连续; 斜率仍小于端点的 1/3
   同时消掉旧版在 75 处的反向台阶 (75 处 0.5 -> 75.001 处 0.3, 越界反而变便宜)

3) 端点变硬约束: |front0-40| 与 |front3-100| 超过 ENDPOINT_BAND 即判不可行。
   走已有的 lexicographic 分层 —— 端点超差的样本永远排在端点达标的样本之后,
   中间腿再好也换不来名次。这是"端点权重最大"唯一严格成立的实现方式:
   靠调权重做不到, 因为中间腿偏离 17 nm 时它的边际收益总能压过端点的 2 nm。

用法 (仓库根目录):
    module load python
    CALIB_REPO_DIR=$PWD CALIB_POPULATION=40 python3 calibration/ctl/patch_objective.py
脚本最后会自动调用 rescore_best.py 把历史最优换算到新标尺。
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PC = HERE.parent / "optimizer" / "propose_cmaes.py"
GT = HERE / "gen_tool.py"

CONSTS = '''MIDDLE_MAX = float(os.environ.get("CALIB_MIDDLE_MAX", "70"))
ENDPOINT_BAND = float(os.environ.get("CALIB_ENDPOINT_BAND", "5"))
'''

MIDDLE_NEW = '''    if middle < 60.0:
        middle_residual = (60.0 - middle) / 5.0
    elif middle <= MIDDLE_MAX:
        middle_residual = (middle - 60.0) / 6.0
    else:
        middle_residual = (MIDDLE_MAX - 60.0) / 6.0 + (middle - MIDDLE_MAX) / 4.0
'''


def patch_propose() -> list[str]:
    src = PC.read_text()
    done = []

    # --- 1) 常量 ---
    if "MIDDLE_MAX" not in src:
        src = src.replace("CONSTRAINT_PENALTY = 1.0e4", CONSTS + "CONSTRAINT_PENALTY = 1.0e4")
        done.append("加入 MIDDLE_MAX / ENDPOINT_BAND")
    elif "ENDPOINT_BAND" not in src:
        src = re.sub(r'(MIDDLE_MAX = float\(os\.environ\.get\("CALIB_MIDDLE_MAX", "\d+"\)\)\n)',
                     r'\1ENDPOINT_BAND = float(os.environ.get("CALIB_ENDPOINT_BAND", "5"))\n',
                     src, count=1)
        done.append("加入 ENDPOINT_BAND")

    # --- 2) 中间腿残差: 整段替换, 不管原来是哪一版 ---
    pattern = re.compile(
        r"[ \t]*if middle < 60\.0:\n(?:.*\n)*?[ \t]*front = \[raw\[0\] / 3\.0")
    if "(middle - 60.0) / 6.0" not in src:
        new_src, n = pattern.subn(MIDDLE_NEW + "    front = [raw[0] / 3.0", src)
        if n != 1:
            raise SystemExit("找不到 0.5 dpa 残差段落, 请人工检查 propose_cmaes.py")
        src = new_src
        done.append("中间腿残差 -> 连续且全程有梯度 (1/6 带内, 1/4 带外)")

    # --- 3) 端点硬约束 ---
    if "abs(raw[0]) - ENDPOINT_BAND" not in src:
        anchor = "    constraints = np.asarray(constraints)"
        src = src.replace(anchor,
                          "    constraints.append((abs(raw[0]) - ENDPOINT_BAND) / ENDPOINT_BAND)\n"
                          "    constraints.append((abs(raw[2]) - ENDPOINT_BAND) / ENDPOINT_BAND)\n"
                          + anchor, 1)
        old_feas = "                    and cr[2] - fe[2] <= 15.0)"
        new_feas = ("                    and cr[2] - fe[2] <= 15.0\n"
                    "                    and abs(raw[0]) <= ENDPOINT_BAND\n"
                    "                    and abs(raw[2]) <= ENDPOINT_BAND)")
        if old_feas not in src:
            raise SystemExit("找不到 feasible 判据, 请人工检查 propose_cmaes.py")
        src = src.replace(old_feas, new_feas, 1)
        done.append("端点 -> 硬约束 (进入 lexicographic 分层)")

    PC.write_text(src)
    return done


def patch_gen_tool() -> list[str]:
    src = GT.read_text()
    done = []
    if "MIDDLE_MAX" not in src:
        src = src.replace('POPULATION = int(os.environ.get("CALIB_POPULATION", "30"))',
                          'POPULATION = int(os.environ.get("CALIB_POPULATION", "30"))\n'
                          'MIDDLE_MAX = float(os.environ.get("CALIB_MIDDLE_MAX", "70"))')
        done.append("gen_tool: 加入 MIDDLE_MAX")
    if "60.0 <= front[1] <= 75.0" in src:
        src = src.replace("60.0 <= front[1] <= 75.0", "60.0 <= front[1] <= MIDDLE_MAX")
        done.append("gen_tool: 成功判据上限 75 -> MIDDLE_MAX")
    GT.write_text(src)
    return done


def main() -> int:
    for name, fn in (("propose_cmaes.py", patch_propose), ("gen_tool.py", patch_gen_tool)):
        changes = fn()
        print(f"[{name}] " + ("; ".join(changes) if changes else "已是最新, 未改动"))

    for path in (PC, GT):
        compile(path.read_text(), str(path), "exec")
    print("语法检查通过")

    rescore = HERE / "rescore_best.py"
    if rescore.exists():
        print("\n--- 用新标尺重算历史最优 ---")
        subprocess.run([sys.executable, str(rescore)], check=False)
    else:
        print("\n注意: 没找到 rescore_best.py, 历史最优仍是旧标尺, "
              "会让 stagnation 计数虚高并触发一次非数据驱动的 restart")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
