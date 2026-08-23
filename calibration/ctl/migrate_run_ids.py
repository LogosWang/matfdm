#!/usr/bin/env python3
"""把老命名的运行目录改成统一科学计数法 (run_id.py 的规则), 一次性迁移。

老名字是"删掉小数点"来的 (ft01 = 0.1, ft10 = 1.0), 会撞名也会因写法不同而分裂;
新名字是科学计数法 (ft1e-1, ft1e0), 双射、永不撞名、位数随便加。

它改这些, 别的一概不碰:
  <老名>/                -> <新名>/            目录改名
  <新名>/config.json     run_id 字段跟着改
  <新名>/provenance.txt  里那份 config 快照的 run_id 跟着改
  runs_<前缀>.txt        清单重新生成 (每行是绝对路径)
  postprocess/<老名>.*   删掉, 让 mf export 用新名重出

结果/断点/CMA 状态里没有嵌运行名或运行路径, 所以改名不影响续算 —— 已经查过:
state.json、metrics、checkpoint、cma_state.pkl 里都不含 run_id 或运行目录路径。

默认只看不动 (dry-run), 加 --apply 才真改:
    python3 calibration/ctl/migrate_run_ids.py --pattern 'ft*'
    python3 calibration/ctl/migrate_run_ids.py --pattern 'ft*' --apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_id as R                                            # noqa: E402


def runs_root() -> Path:
    root = os.environ.get("MATFDM_RUNS")
    if root:
        return Path(root)
    return Path(os.environ.get("SCRATCH", str(Path.home()))) / "matfdm_runs"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pattern", default="ft*", help="要迁移的运行目录通配")
    ap.add_argument("--prefix", default="", help="新名前缀 (默认从 pattern 去掉 * 得到)")
    ap.add_argument("--key", default="", help="扫描字段; 不给就自动认")
    ap.add_argument("--runs", default="", help="数据根 (默认 $MATFDM_RUNS)")
    ap.add_argument("--apply", action="store_true", help="真的改; 不加只打印计划")
    args = ap.parse_args()

    root = Path(args.runs) if args.runs else runs_root()
    prefix = args.prefix or args.pattern.replace("*", "")

    pairs = []
    for d in sorted(root.glob(args.pattern)):
        cfg = d / "config.json"
        if d.is_dir() and cfg.is_file():
            try:
                pairs.append((d, json.loads(cfg.read_text())))
            except (OSError, ValueError) as err:
                print(f"跳过 {d.name}: config.json 读不了 ({err})", file=sys.stderr)
    if not pairs:
        print(f"{root} 下没有匹配 {args.pattern!r} 的运行")
        return 1

    key = args.key or R.sweep_key([c for _, c in pairs])
    if not key:
        print("认不出扫描字段 (没有恰好一个数值字段在变), 用 --key 指定", file=sys.stderr)
        return 1
    print(f"数据根 : {root}")
    print(f"扫描   : {key}      新名前缀: {prefix}")
    print(f"模式   : {'真改' if args.apply else 'dry-run (加 --apply 才动)'}\n")

    plan, done, bad = [], 0, 0
    for d, cfg in pairs:
        val = R.dig(cfg, key)
        if val is None:
            print(f"  {d.name:<12s} config 里没有 {key}, 跳过"); bad += 1; continue
        new = R.run_id(prefix, val)
        if new == d.name:
            print(f"  {d.name:<12s} 已是新名, 跳过"); done += 1; continue
        target = root / new
        if target.exists():
            print(f"  {d.name:<12s} -> {new}  目标已存在, 拒绝改名", file=sys.stderr)
            bad += 1; continue
        print(f"  {d.name:<12s} -> {new:<12s} ({key}={val})")
        plan.append((d, target, cfg))

    if bad:
        print(f"\n有 {bad} 个目录有问题, 一个都不改。先处理掉再来。", file=sys.stderr)
        return 1
    if not plan:
        print(f"\n没有要改的 ({done} 个已经是新名)")
        return 0
    if not args.apply:
        print(f"\n以上 {len(plan)} 个改名尚未执行。确认无误后加 --apply。")
        return 0

    for old, new, cfg in plan:
        old.rename(new)
        cfg["run_id"] = new.name
        (new / "config.json").write_text(
            json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
        prov = new / "provenance.txt"
        if prov.is_file():
            prov.write_text(prov.read_text().replace(
                f'"run_id": "{old.name}"', f'"run_id": "{new.name}"'))
        # 老名字的后处理产物作废, 让 mf export 用新名重出
        for stale in (root / "postprocess").glob(f"{old.name}.*"):
            stale.unlink()
    print(f"\n改了 {len(plan)} 个目录")

    manifest = root / f"runs_{prefix}.txt"
    if manifest.is_file():
        pairs2 = [(d, json.loads((d / "config.json").read_text()))
                  for d in root.glob(args.pattern)
                  if d.is_dir() and (d / "config.json").is_file()]
        ordered, _ = R.sort_runs(pairs2, key)
        manifest.write_text("".join(f"{d}\n" for d, _ in ordered))
        print(f"清单已重写: {manifest} ({len(ordered)} 行, 按 {key} 排序)")
    print("接着跑: mf export  重出后处理 txt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
