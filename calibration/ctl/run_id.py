#!/usr/bin/env python3
"""扫描值 <-> 运行目录名。全项目唯一的命名权威, 所有地方都从这里取。

命名规则: **统一科学计数法**, 前缀 + 规范尾数 + e + 指数
    尾数归一到 [1,10) 并去掉尾随零, 指数是带符号整数 (正数不写 +)。

        0.1     -> 1e-1     -> ft1e-1
        0.2     -> 2e-1     -> ft2e-1
        0.05    -> 5e-2     -> ft5e-2
        0.125   -> 1.25e-1  -> ft1.25e-1
        1.0     -> 1e0      -> ft1e0
        1.5     -> 1.5e0    -> ft1.5e0
        10      -> 1e1      -> ft1e1
        15      -> 1.5e1    -> ft1.5e1
        1e-4    -> 1e-4     -> ft1e-4

为什么必须这样:
  老做法是把小数点删掉 (`tr -d '.'`), 三个毛病 ——
    1.0 和 10 都得 ft10, 1.5 和 15 都得 ft15: 两条链写进同一个目录, CMA 状态和
      metrics 混在一起, 两条都废, 而且全程没有任何报错;
    0.1 写成 0.10 会另开一个 ft010, 把已经算了几百次评估的 ft01 孤立掉;
    位数一混, 目录名的字典序和数值大小完全对不上 (ft100=10 会排在 ft125=1.25 前面)。

  科学计数法是**双射**: 值 -> 名字唯一, 名字 -> 值也唯一 (名字去掉前缀就是一个
  合法的十进制字面量, Decimal 直接读得回来)。位数想加多少加多少, 永远不会撞名。

用法:
    python3 run_id.py --prefix ft 0.1 0.2 0.125     # 每行 "<id> <规范值>"
    python3 run_id.py --prefix ft --one 0.15        # 只要 id
    python3 run_id.py --prefix ft --decode ft1.25e-1        # 反解出 0.125
    python3 run_id.py --prefix ft --runs $RUNS --key front_thick 0.1 0.2
                                                    # 顺带查已存在目录对不对得上
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path


# ------------------------------------------------------------------ 命名
def canon(value) -> str:
    """值的唯一科学计数写法。非数值原样返回 (seed=abc 这种)。"""
    text = str(value).strip()
    try:
        d = Decimal(text)
    except (InvalidOperation, ValueError):
        return text
    if not d.is_finite():
        return text
    if d == 0:
        return "0e0"
    sign = "-" if d < 0 else ""
    d = abs(d)
    exp = d.adjusted()                     # = floor(log10(d)), 精确, 不走浮点
    mant = d.scaleb(-exp).normalize()      # 尾数归一到 [1,10) 并去尾随零
    return f"{sign}{format(mant, 'f')}e{exp}"


def run_id(prefix: str, value) -> str:
    return f"{prefix}{canon(value)}"


def value_of(name: str, prefix: str = ""):
    """运行名反解回值; 解不出来返回 None。canon 是合法十进制字面量, 直读即可。"""
    s = name[len(prefix):] if prefix and name.startswith(prefix) else name
    try:
        return Decimal(s)
    except (InvalidOperation, ValueError):
        return None


# ------------------------------------------- config.json 内省 (排序/推断扫描字段)
def flatten(cfg: dict, prefix: str = "") -> dict:
    """{"overrides": {"eff": 0.2}} -> {"overrides.eff": 0.2}, 只保留数值字段。"""
    out = {}
    for k, v in cfg.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(flatten(v, key + "."))
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            out[key] = float(v)
    return out


def dig(cfg: dict, key: str):
    """按点路径取值: "front_thick" 或 "overrides.eff"。"""
    node = cfg
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def sweep_key(cfgs: list) -> str:
    """猜这组运行扫的是哪个字段: 取值不全相同的那个数值字段。

    扫描的定义就是"只有一个字段在变", 所以恰好有一个候选时才算数; 有多个字段
    同时在变就认不出来, 调用方自己退回按名字排序。
    """
    if len(cfgs) < 2:
        return ""
    flat = [flatten(c) for c in cfgs]
    keys = set(flat[0])
    for f in flat[1:]:
        keys &= set(f)
    varying = [k for k in keys if len({f[k] for f in flat}) > 1]
    return varying[0] if len(varying) == 1 else ""


def natural(name: str):
    """名字排序兜底: 数字段按数值比, 不按字典序。"""
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", name)]


def sort_runs(pairs: list, key: str = ""):
    """(目录, config) 列表按扫描值数值排序; 认不出扫描字段就按名字自然排序。"""
    key = key or sweep_key([c for _, c in pairs])
    if key:
        return sorted(pairs, key=lambda t: (flatten(t[1]).get(key, float("inf")),
                                            t[0].name)), key
    return sorted(pairs, key=lambda t: natural(t[0].name)), ""


def same_number(a, b) -> bool:
    try:
        return Decimal(str(a)) == Decimal(str(b))
    except (InvalidOperation, ValueError):
        return str(a).strip() == str(b).strip()


# ------------------------------------------------------------------ CLI
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", default="")
    ap.add_argument("--one", action="store_true", help="只打印 id, 不打印规范值")
    ap.add_argument("--decode", action="store_true", help="把运行名反解成值")
    ap.add_argument("--runs", default="", help="数据根; 给了就顺带查已存在目录对不对得上")
    ap.add_argument("--key", default="", help="扫描字段 (支持 overrides.eff 这种点路径)")
    ap.add_argument("values", nargs="+")
    args = ap.parse_args()

    if args.decode:
        for name in args.values:
            v = value_of(name, args.prefix)
            if v is None:
                print(f"{name} 不是合法运行名 (前缀 {args.prefix!r})", file=sys.stderr)
                return 1
            print(f"{name} {v}")
        return 0

    seen: dict = {}
    rows = []
    for v in args.values:
        c, i = canon(v), run_id(args.prefix, v)
        if i in seen and seen[i] != c:      # 科学计数法下不可能发生, 留作断言
            print(f"运行名撞了: {seen[i]} 和 {c} 都会写进 {i}/", file=sys.stderr)
            return 1
        seen[i] = c
        rows.append((i, c))

    # 目标目录已存在, 但里面记的扫描值和这次要写的不是一个值 —— 多半是手改过
    # config.json 或换了扫描字段, 直接写进去会把两次扫描搅在一起。
    if args.runs and args.key:
        for i, c in rows:
            cfg = Path(args.runs) / i / "config.json"
            if not cfg.is_file():
                continue
            try:
                cur = dig(json.loads(cfg.read_text()), args.key)
            except (OSError, ValueError):
                continue
            if cur is None or same_number(cur, c):
                continue
            print(f"{i}/ 里记的 {args.key}={cur}, 这次却要写 {c} —— 这个目录已经有"
                  f"历史数据了, 覆盖会把两次扫描混在一起。换前缀, 或先 mf clean {i}。",
                  file=sys.stderr)
            return 1

    for i, c in rows:
        print(i if args.one else f"{i} {c}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
