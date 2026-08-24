#!/usr/bin/env python3
"""常驻标定驱动 —— run_generation.m 的编译版对应物。

和 .m 版的区别只有一处: 撒腿的方式。
    .m 版:  一个 MATLAB 持 parpool(120), parfeval 撒腿   -> 要 1 MATLAB + 1 PCT 席位
    本版:   fork 120 个 MCR standalone 进程, 各跑一条腿   -> 0 席位

其余语义逐条照搬, 不做"顺便改进":
  每代 = 读 state.json 的 batchNN_cases -> 撒 nCase*ndose 条腿 -> 全部回收
         -> 逐 case 抽指标 -> 判成功 -> CMA 出下一代 -> 继续
  已完成的腿跳过 (续算); 反复失败的 case 熔断; 墙钟耗尽干净退出等续投。

CMA/目标函数仍然全在 python (gen_tool.py / propose_cmaes.py), 编译不影响它们 ——
改目标函数不用重编。

环境变量 (与 .m 版同名同义):
  MATFDM_RUN         运行目录 (数据根)
  CALIB_PYTHON       python3
  CALIB_POPULATION / CALIB_WORKERS / CALIB_ENDPOINT_TOL / CALIB_MAX_ATTEMPTS
  CALIB_WALL_BUDGET  本作业可用秒数 (不设 = 不自我限时, 跑到 SLURM 杀)
  CALIB_GEN_RESERVE  开新一代所需的最少剩余秒数 (默认 5400)
  MATFDM_DEADLINE    作业截止 epoch 秒 (multi_node.sh 从 scontrol 算好传入)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
MCR = HERE / "matfdm_mcr.sh"
GEN_TOOL = HERE / "gen_tool.py"


def say(fmt, *a):
    print(f"[{datetime.now():%H:%M:%S}] " + (fmt % a if a else fmt), flush=True)


def envnum(name, default):
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


# ------------------------------------------------------------------ 状态
def read_cases(statef: Path, batch: int):
    s = json.loads(statef.read_text())
    key = f"batch{batch:02d}_cases"
    if key not in s:
        raise RuntimeError(f"state.json 缺 {key}")
    return s[key]


def next_batch(statef: Path, metrics: Path) -> int:
    """已有的最大 batch: 若其 cases 已全部抽完指标则 +1, 否则续跑它。"""
    if not statef.is_file():
        return 1
    s = json.loads(statef.read_text())
    nums = [int(k[5:7]) for k in s
            if k.startswith("batch") and k.endswith("_cases")]
    if not nums:
        return 1
    b = max(nums)
    for c in read_cases(statef, b):
        if not (metrics / f"{c['case_tag']}.csv").is_file():
            return b            # 本代还没做完, 续跑本代
    return b + 1


def leg_is_complete(run: Path, tag: str, dose) -> bool:
    """与 leg_is_complete.m 同一判据: _COMPLETE 标记 + 四个非空 final csv。"""
    root = run / "decouple" / tag / f"dose{dose:g}"
    if not (root / "_COMPLETE").is_file():
        return False
    for name in ("Cr2O3", "Fe3O4", "FeCr2O4", "SiO2"):
        f = root / f"{name}_final.csv"
        if not f.is_file() or f.stat().st_size == 0:
            return False
    return True


# ------------------------------------------------------------------ 外部调用
def gen_tool(run: Path, cfg: dict, *args) -> tuple[int, str]:
    """调 gen_tool.py; 环境与 .m 版的 sh() 一致。

    CALIB_POPULATION 必须显式传 —— propose_cmaes 拿它和磁盘上的 case 数对账,
    不传就用默认值, 一代 40 个 case 会被判成"与 POPULATION 不符"直接拒绝。
    判据类的几个 (MIDDLE_MAX/ENDPOINT_BAND/SEED) 正常由 node_task.sh 导出;
    这里在缺失时用 config.json 兜底, 好让脚本单独跑也对。
    """
    env = dict(os.environ)
    env.update(MATFDM_RUN=str(run), CALIB_REPO_DIR=str(run),
               CALIB_STATE_PATH=str(run / "calibration" / "state.json"),
               CALIB_OUT_DIR=str(run / "calibration" / "optimizer"),
               CALIB_POPULATION=str(int(envnum("CALIB_POPULATION",
                                               cfg.get("population", 40)))))
    for var, key, default in (("CALIB_MIDDLE_MAX", "middle_max", 70),
                              ("CALIB_ENDPOINT_BAND", "endpoint_band", 5),
                              ("CALIB_SEED", "seed", 20260804)):
        env.setdefault(var, str(cfg.get(key, default)))
    py = os.environ.get("CALIB_PYTHON", "python3")
    p = subprocess.run([py, str(GEN_TOOL), *map(str, args)],
                       env=env, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def spawn_leg(run: Path, tag: str, dose, mult, budget) -> subprocess.Popen:
    m = ",".join(repr(float(x)) for x in mult)
    cmd = [str(MCR), "leg", str(run), tag, f"{dose:g}", m]
    if budget is not None:
        cmd.append(str(int(budget)))
    log = run / "calibration" / "logs" / f"{tag}_dose{dose:g}.out"
    return subprocess.Popen(cmd, stdout=log.open("w"), stderr=subprocess.STDOUT)


def run_metrics(run: Path, tag: str) -> bool:
    p = subprocess.run([str(MCR), "metrics", str(run), tag],
                       capture_output=True, text=True)
    return p.returncode == 0


# ------------------------------------------------------------------ 熔断计数
def load_attempts(f: Path) -> dict:
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        return {}


def save_attempts(f: Path, a: dict):
    tmp = f.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(a))
    tmp.replace(f)


# ------------------------------------------------------------------ 主循环
def main() -> int:
    run = Path(os.environ.get("MATFDM_RUN", ""))
    if not run.is_dir():
        say("MATFDM_RUN 没设或不存在: %s", run)
        return 2
    calib = run / "calibration"
    statef = calib / "state.json"
    metrics = calib / "metrics"
    for d in (metrics, calib / "logs", calib / "optimizer"):
        d.mkdir(parents=True, exist_ok=True)

    cfg = json.loads((run / "config.json").read_text())
    pop = int(envnum("CALIB_POPULATION", cfg.get("population", 40)))
    nleg = int(envnum("CALIB_WORKERS", cfg.get("workers", 120)))
    tol = envnum("CALIB_ENDPOINT_TOL", cfg.get("endpoint_tol", 3))
    max_attempts = int(envnum("CALIB_MAX_ATTEMPTS", cfg.get("max_attempts", 3)))
    doses = list(cfg.get("doses", [0, 0.5, 3]))

    budget = envnum("CALIB_WALL_BUDGET", float("inf"))
    reserve = envnum("CALIB_GEN_RESERVE", 5400)
    deadline = envnum("MATFDM_DEADLINE", 0)
    t0 = time.time()

    say("[boot] run=%s legs<=%d pop=%d %s", run, nleg, pop,
        f"budget={budget:.0f}s" if budget != float("inf") else "无代码侧时限")
    say("[boot] 引擎=MCR standalone (0 个 MATLAB/PCT 席位), build=%s",
        os.environ.get("MATFDM_BUILD_COMMIT", "?"))

    attempts_f = calib / "attempts.json"

    while True:
        if (calib / "DONE").is_file() or (calib / "STOP").is_file():
            say("[sentinel] 见到 DONE/STOP, 退出")
            break
        if budget != float("inf") and time.time() - t0 > budget - reserve:
            say("[wall] 剩余不足一代, 干净退出")
            break

        batch = next_batch(statef, metrics)

        rc, hist = gen_tool(run, cfg, "history", batch)
        print(hist, end="", flush=True)

        rc, out = gen_tool(run, cfg, "propose", batch)
        if rc != 0:
            say("[propose] rc=%d, python 输出:", rc)
            print(out, flush=True)
            if batch > 1:
                say("[propose] 失败, 惩罚上一代缺指标的 case 后重试")
                gen_tool(run, cfg, "penalize-missing", batch - 1)
                rc, out = gen_tool(run, cfg, "propose", batch)
        if rc != 0:
            say("[propose] CMA-ES 提议失败, batch %d", batch)
            return 3

        cases = read_cases(statef, batch)
        say("[gen %02d] %d cases x %d dose = %d legs",
            batch, len(cases), len(doses), len(doses) * len(cases))

        # ---- 撒腿 (已完成的跳过, 这就是续算) ----
        if budget != float("inf"):
            leg_budget = max(600, budget - (time.time() - t0) - 300)
        elif deadline > 0:
            leg_budget = max(600, deadline - time.time() - 300)
        else:
            leg_budget = None

        pending = [(c["case_tag"], d, c["mult"])
                   for c in cases for d in doses
                   if not leg_is_complete(run, c["case_tag"], d)]
        say("[gen %02d] 待跑 %d 条 (已完成 %d 条直接跳过)",
            batch, len(pending), len(doses) * len(cases) - len(pending))

        procs, meta, queue = {}, {}, list(pending)
        done_n, t_gen = 0, time.time()
        attempts = load_attempts(attempts_f)

        while queue or procs:
            while queue and len(procs) < nleg:
                tag, d, mult = queue.pop(0)
                p = spawn_leg(run, tag, d, mult, leg_budget)
                procs[p.pid] = p
                meta[p.pid] = (tag, d)
            if not procs:
                break
            time.sleep(5)
            for pid in [q for q, p in procs.items() if p.poll() is not None]:
                p = procs.pop(pid)
                tag, d = meta.pop(pid)
                done_n += 1
                if p.returncode == 0:
                    st = "complete"
                elif p.returncode == 10:
                    st = "wallclock"
                else:
                    st = f"error(rc={p.returncode})"
                    k = f"{tag}/dose{d:g}".replace("/", "_").replace(".", "_")
                    attempts[k] = attempts.get(k, 0) + 1
                    save_attempts(attempts_f, attempts)
                say("[leg] %-24s %-10s (%d/%d, 本代 %.0f min)",
                    f"{tag}/dose{d:g}", st, done_n, len(pending),
                    (time.time() - t_gen) / 60)

        # ---- 熔断 ----
        dead = []
        for c in cases:
            tag = c["case_tag"]
            for d in doses:
                k = f"{tag}/dose{d:g}".replace("/", "_").replace(".", "_")
                if not leg_is_complete(run, tag, d) and attempts.get(k, 0) >= max_attempts:
                    dead.append(tag)
                    break
        for tag in dict.fromkeys(dead):
            gen_tool(run, cfg, "penalize", batch, "--tag", tag)
            say("[dead] %s 连续失败 >=%d 次, 已写惩罚指标", tag, max_attempts)

        # ---- 完整性: 有腿没跑完且未熔断 = 墙钟耗尽, 交给续投 ----
        incomplete = sum(1 for c in cases if c["case_tag"] not in dead
                         for d in doses if not leg_is_complete(run, c["case_tag"], d))
        if incomplete > 0:
            say("[gen %02d] %d 条腿未完成 (墙钟), 存盘退出等续投", batch, incomplete)
            break

        # ---- 抽指标 ----
        for c in cases:
            tag = c["case_tag"]
            if (metrics / f"{tag}.csv").is_file():
                continue
            if not run_metrics(run, tag):
                say("[metrics] %s 失败, 写惩罚指标", tag)
                gen_tool(run, cfg, "penalize", batch, "--tag", tag)

        # ---- 判成功 ----
        rc, out = gen_tool(run, cfg, "success", batch, "--tol", tol)
        say("[gen %02d] %s", batch, out.strip())
        winners = ""
        for line in out.splitlines():
            if line.startswith("WINNERS="):
                winners = line[len("WINNERS="):].strip()
        if rc == 0 and winners:
            (calib / "DONE").write_text(winners + "\n")
            say("[done] 命中: %s", winners)
            break
        rc, rep = gen_tool(run, cfg, "report", batch)
        print(rep, end="", flush=True)

    say("[exit] 总耗时 %.2f h", (time.time() - t0) / 3600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
