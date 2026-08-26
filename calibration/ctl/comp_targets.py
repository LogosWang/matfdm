#!/usr/bin/env python3
"""把实验测得的 GB 氧化物成分 (Composition_Dose.csv) 换算成标定靶值。

CSV 是唯一真相源, 换实验数据只要换这个文件, 不用改代码也不用重编。

口径 (--basis):
  crfeni  默认。分母 = Cr+Fe+Ni, 与 extract_calibration_metrics 一致。
          模型里 Ni 不进氧化物恒为 0, 所以模型的 Cr%+Fe% 永远是 100%, 而实验
          只有 99.1/97.6/96.1% —— 差额就是模型缺的那部分 Ni, 会如实留在残差里,
          成分残差有个 0.9/2.4/3.9% 的地板, 收敛不到零是预期的。
  crfe    分母 = Cr+Fe, 把 Ni 归一化掉。残差能到零, 但模型缺 Ni 这件事被抹平。

用法:
    python3 calibration/ctl/comp_targets.py                 # 打印靶值表
    python3 calibration/ctl/comp_targets.py --json          # 只出 JSON, 喂给 config
    python3 calibration/ctl/comp_targets.py --basis crfe
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CODE = HERE.parent.parent
DEFAULT_CSV = CODE / "Composition_Dose.csv"


def read_csv(path: Path) -> tuple[list, dict]:
    """-> (剂量列表, {元素: [每个剂量的 at%]})。csv 带 BOM, 用 utf-8-sig。"""
    rows = list(csv.reader(path.open(encoding="utf-8-sig")))
    header = [c.strip() for c in rows[0]]
    doses = [float(c.replace("dpa", "").strip()) for c in header[1:]]
    data = {}
    for row in rows[1:]:
        if not row or not row[0].strip():
            continue
        el = row[0].split()[0].strip()          # "Cr at%" -> "Cr"
        data[el] = [float(x) for x in row[1:len(doses) + 1]]
    return doses, data


def targets(data: dict, basis: str) -> list:
    """每个剂量一对 [Cr%, Fe%], 按所选分母归一。"""
    els = ("Cr", "Fe", "Ni") if basis == "crfeni" else ("Cr", "Fe")
    n = len(data["Cr"])
    out = []
    for i in range(n):
        denom = sum(data[e][i] for e in els if e in data)
        out.append([round(100 * data["Cr"][i] / denom, 4),
                    round(100 * data["Fe"][i] / denom, 4)])
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(DEFAULT_CSV))
    ap.add_argument("--basis", choices=("crfeni", "crfe"), default="crfeni")
    ap.add_argument("--json", action="store_true", help="只打印 JSON")
    args = ap.parse_args()

    path = Path(args.csv)
    if not path.is_file():
        raise SystemExit(f"找不到 {path}")
    doses, data = read_csv(path)
    tg = targets(data, args.basis)

    if args.json:
        print(json.dumps(tg, separators=(",", ":")))
        return 0

    print(f"来源 : {path}")
    print(f"口径 : 分母 = {'Cr+Fe+Ni' if args.basis == 'crfeni' else 'Cr+Fe'}\n")
    print(f"{'dpa':>6} {'Cr at%':>9} {'Fe at%':>9} {'模型可达 Cr+Fe':>16}")
    for i, d in enumerate(doses):
        cr, fe = tg[i]
        print(f"{d:>6g} {cr:9.3f} {fe:9.3f} {cr + fe:15.2f}%"
              + ("" if abs(cr + fe - 100) < 1e-9
                 else f"   <- 残差地板 {100 - cr - fe:.2f}%"))
    print("\nconfig 字段:")
    print(f'  "composition_targets": {json.dumps(tg, separators=(",", ":"))}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
