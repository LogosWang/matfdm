#!/usr/bin/env python3
"""Recoverable controller for the isolated decoupled calibration."""

from __future__ import annotations

import argparse
import csv
import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

CTRL = Path(__file__).resolve().parent
STATE = CTRL / "state.json"
RUNTIME = CTRL / "controller-runtime.json"
LOCK = CTRL / "controller.lock"
OPT = CTRL / "optimizer"
RUN = Path(os.environ.get("CALIB_REPO_DIR", "/mnt/c/Users/vool/matfdm_calibration_20260731"))
MATLAB = Path("/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe")
DOSES = (("0", "d0"), ("0.5", "d05"), ("3", "d3"))
PHASES = ("Cr2O3", "Fe3O4", "FeCr2O4", "SiO2")
STALE_SECONDS = int(os.environ.get("CALIB_STALE_SECONDS", "1800"))
MISSING_GRACE_SECONDS = int(os.environ.get("CALIB_MISSING_GRACE_SECONDS", "30"))
CASES_PER_BATCH = int(os.environ.get("CALIB_CASES_PER_BATCH", "10"))
MAX_STARTS_PER_TICK = int(os.environ.get("CALIB_MAX_STARTS_PER_TICK", "30"))
LAUNCH_STAGGER_SECONDS = float(os.environ.get("CALIB_LAUNCH_STAGGER_SECONDS", "5"))


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def atomic_json(path: Path, obj) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2) + "\n")
    os.replace(tmp, path)


def run(cmd, *, env=None, check=True, capture=False):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(cmd, env=merged, check=check, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None)


def tmux_alive(session: str) -> bool:
    # tmux target names are prefix-matched unless prefixed with '='. Without
    # exact matching, a missing *_d0 leg is falsely reported alive when the
    # sibling *_d05 session exists.
    return subprocess.run(["tmux", "has-session", "-t", f"={session}"],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def leg_complete(tag: str, dose: str) -> bool:
    # 与 MATLAB 侧 leg_is_complete.m 同一判据: 必须有 _COMPLETE 标记。
    # 只看 csv 非空会把"被杀在最后一个 csv 写一半"误判为完成。
    folder = RUN / "decouple" / tag / f"dose{dose}"
    if not (folder / "_COMPLETE").exists():
        return False
    files = [folder / f"{phase}_final.csv" for phase in PHASES]
    return all(path.exists() and path.stat().st_size > 0 for path in files)


def metric_rows(tag: str):
    path = RUN / "calibration" / "metrics" / f"{tag}.csv"
    if not path.exists():
        return None
    try:
        with path.open(newline="") as f:
            rows = sorted(csv.DictReader(f), key=lambda row: float(row["dose"]))
        required = {"dose", "front_nm", "Cr_atom_inventory", "Cr_atom_pct",
                    "Fe_atom_pct", "Si_atom_pct"}
        if len(rows) != 3 or not required.issubset(rows[0]):
            return None
        if not all(float(row[key]) == float(row[key])
                   for row in rows for key in required - {"dose"}):
            return None
        return rows
    except (OSError, ValueError, IndexError):
        return None


def latest_batch(state: dict) -> int:
    batches = [int(match.group(1)) for key in state
               for match in [re.fullmatch(r"batch(\d+)_cases", key)] if match]
    if not batches:
        raise RuntimeError("state.json contains no batchNN_cases")
    return max(batches)


def cases_for(state: dict, batch: int) -> list[dict]:
    cases = state.get(f"batch{batch:02d}_cases", [])
    if len(cases) != CASES_PER_BATCH:
        raise RuntimeError(
            f"batch {batch} has {len(cases)} cases, expected {CASES_PER_BATCH}")
    tags = [str(case.get("case_tag")) for case in cases]
    if len(set(tags)) != CASES_PER_BATCH or any(not re.fullmatch(fr"b{batch:02d}_c\d{{2}}_(?:lm|cma)", tag)
                                  for tag in tags):
        raise RuntimeError(f"batch {batch} has duplicate or malformed tags")
    vectors = []
    for case in cases:
        mult = case.get("mult", [])
        if len(mult) != 10 or any(not isinstance(value, (int, float))
                                  or not 0.03 <= value <= 60.0 for value in mult):
            raise RuntimeError(f"invalid multiplier vector: {case.get('case_tag')}")
        vectors.append(tuple(mult))
    if len(set(vectors)) != CASES_PER_BATCH:
        raise RuntimeError(f"batch {batch} has duplicate parameter vectors")
    return cases


def log_since(tag: str, suffix: str, offset: int) -> str:
    path = RUN / "calibration" / "logs" / f"{tag}_{suffix}.log"
    if not path.exists():
        return ""
    with path.open("rb") as stream:
        stream.seek(min(max(offset, 0), path.stat().st_size))
        return stream.read().decode(errors="replace")


def failure_diagnosis(text: str) -> str:
    patterns = (
        (r"unable to read file|无法读取文件|run_ckpt_decouple[\s\S]{0,300}\bload\b",
         "checkpoint-load-failure"),
        (r"error 5001|错误 5001", "mathworks-servicehost-5001"),
        (r"access violation", "matlab-access-violation"),
        (r"out of memory", "out-of-memory"),
        (r"license checkout|license manager", "license-failure"),
        (r"i/o error", "io-error"),
        (r"segmentation|fatal error", "fatal-runtime-error"),
        (r"matlab error exit status", "matlab-nonzero-exit"),
    )
    for pattern, label in patterns:
        if re.search(pattern, text, re.I):
            return label
    return "incomplete-exit-no-recognized-signature"


def quarantine_checkpoint(tag: str, dose: str, item: dict, reason: str) -> bool:
    checkpoint = RUN / "checkpoint" / tag / f"decouple_dose{dose}" / "checkpoint.mat"
    if not checkpoint.exists():
        return False
    quarantine = (RUN / "calibration" / "quarantine" / "checkpoints" / tag /
                  f"decouple_dose{dose}")
    quarantine.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().astimezone().strftime("%Y%m%d_%H%M%S")
    destination = quarantine / f"checkpoint.{stamp}.{reason}.mat"
    shutil.move(str(checkpoint), str(destination))
    item["quarantined_checkpoint"] = {"at": now(), "reason": reason,
                                       "path": str(destination)}
    return True


def progress_marker(tag: str, dose: str, suffix: str) -> float:
    paths = [RUN / "checkpoint" / tag / f"decouple_dose{dose}" / "checkpoint.mat",
             RUN / "calibration" / "logs" / f"{tag}_{suffix}.log"]
    return max((path.stat().st_mtime for path in paths if path.exists()), default=0.0)


def reap_stale(cases: list[dict], runtime: dict) -> None:
    current = time.time()
    for case in cases:
        tag = case["case_tag"]
        for dose, suffix in DOSES:
            session = f"oxcal_{tag}_{suffix}"
            if leg_complete(tag, dose) or not tmux_alive(session):
                continue
            item = runtime.setdefault("legs", {}).setdefault(session, {})
            marker = progress_marker(tag, dose, suffix)
            if marker > float(item.get("progress_marker", -1)):
                item["progress_marker"] = marker
                item["progress_seen_at"] = current
                continue
            if current - float(item.get("progress_seen_at", current)) < STALE_SECONDS:
                continue
            listing = run(["ps", "-eo", "pid=,args="], capture=True, check=False).stdout
            needle = f"run_calibration_case('{tag}',{dose},"
            for line in listing.splitlines():
                if "matlab.exe" in line and needle in line:
                    try:
                        os.kill(int(line.strip().split(None, 1)[0]), signal.SIGTERM)
                    except (ProcessLookupError, ValueError):
                        pass
            run(["tmux", "kill-session", "-t", f"={session}"], check=False)
            item["stale_reaps"] = int(item.get("stale_reaps", 0)) + 1
            item["last_reason"] = "stale-no-checkpoint-or-log-progress"
            item["next_retry_at"] = current + 60


def launch_legs(cases: list[dict], runtime: dict) -> int:
    started = 0
    current = time.time()
    for case in cases:
        tag = case["case_tag"]
        mult_csv = ",".join(str(value) for value in case["mult"])
        for dose, suffix in DOSES:
            session = f"oxcal_{tag}_{suffix}"
            item = runtime.setdefault("legs", {}).setdefault(session, {})
            if leg_complete(tag, dose) or tmux_alive(session):
                item.pop("missing_seen_at", None)
                continue
            log = RUN / "calibration" / "logs" / f"{tag}_{suffix}.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            previous_offset = int(item.get("launch_log_offset", 0))
            if item.get("restarts", 0):
                reason = failure_diagnosis(log_since(tag, suffix, previous_offset))
                # A clean/unknown exit may be a normal completion whose files
                # are not yet visible through the Windows mount. Recheck on
                # the next controller tick before launching a duplicate.
                if reason == "incomplete-exit-no-recognized-signature":
                    missing_since = float(item.setdefault("missing_seen_at", current))
                    if current - missing_since < MISSING_GRACE_SECONDS:
                        continue
            else:
                reason = "initial-generation-launch"
            item.pop("missing_seen_at", None)
            checkpoint = (RUN / "checkpoint" / tag / f"decouple_dose{dose}" /
                          "checkpoint.mat")
            checkpoint_quarantined = False
            if checkpoint.exists() and checkpoint.stat().st_size == 0:
                checkpoint_quarantined = quarantine_checkpoint(
                    tag, dose, item, "zero-byte")
                reason = "checkpoint-zero-byte-quarantined"
            elif reason == "checkpoint-load-failure":
                checkpoint_quarantined = quarantine_checkpoint(
                    tag, dose, item, "load-failure")
            retry_at = float(item.get("next_retry_at", 0))
            if checkpoint_quarantined or reason in (
                    "checkpoint-load-failure", "checkpoint-zero-byte-quarantined"):
                retry_at = 0
            if item.get("last_diagnosis") == "mathworks-servicehost-5001":
                retry_at = min(retry_at, current)
            if current < retry_at:
                continue
            launch_offset = log.stat().st_size if log.exists() else 0
            run(["tmux", "new-session", "-d", "-s", session,
                 str(CTRL / "run_leg.sh"), str(RUN), tag, dose, mult_csv, str(log)])
            item["restarts"] = int(item.get("restarts", 0)) + 1
            item["last_restart_at"] = now()
            item["last_reason"] = reason
            item["last_diagnosis"] = reason
            item["launch_log_offset"] = launch_offset
            attempts = int(item["restarts"])
            # 5001 is a transient ServiceHost cold-start collision, so retry it
            # every controller minute. Other failures retain exponential
            # backoff to avoid a persistent crash storm.
            retry_delay = (60 if reason == "mathworks-servicehost-5001"
                           else min(900, 60 * 2 ** min(attempts - 1, 4)))
            item["next_retry_at"] = current + retry_delay
            item["progress_marker"] = progress_marker(tag, dose, suffix)
            item["progress_seen_at"] = current
            started += 1
            if started >= MAX_STARTS_PER_TICK:
                return started
            if LAUNCH_STAGGER_SECONDS > 0:
                time.sleep(LAUNCH_STAGGER_SECONDS)
    return started


def extract_metrics(tag: str) -> None:
    repo_win = run(["wslpath", "-w", str(RUN)], capture=True).stdout.strip()
    expression = f"cd('{repo_win}'); extract_calibration_metrics('{tag}')"
    log = RUN / "calibration" / "logs" / f"{tag}_extract.log"
    with log.open("a") as f:
        try:
            proc = subprocess.run([str(MATLAB), "-singleCompThread", "-batch", expression],
                                  stdout=f, stderr=subprocess.STDOUT, timeout=900)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"metric extraction timed out for {tag}; see {log}") from exc
    if proc.returncode or metric_rows(tag) is None:
        raise RuntimeError(f"metric extraction failed for {tag}; see {log}")
    (CTRL / "metrics").mkdir(parents=True, exist_ok=True)
    shutil.copy2(RUN / "calibration" / "metrics" / f"{tag}.csv",
                 CTRL / "metrics" / f"{tag}.csv")


def is_success(tag: str, endpoint_tolerance: float) -> bool:
    rows = metric_rows(tag)
    if rows is None:
        return False
    fronts = [float(row["front_nm"]) for row in rows]
    inventory = [float(row["Cr_atom_inventory"]) for row in rows]
    cr = [float(row["Cr_atom_pct"]) for row in rows]
    fe = [float(row["Fe_atom_pct"]) for row in rows]
    si = [float(row["Si_atom_pct"]) for row in rows]
    return (abs(fronts[0] - 40.0) <= endpoint_tolerance
            and 60.0 <= fronts[1] <= 75.0
            and abs(fronts[2] - 100.0) <= endpoint_tolerance
            and all(c > max(f, s) for c, f, s in zip(cr, fe, si))
            and cr[2] - fe[2] <= 15.0
            and inventory[0] > inventory[1] > inventory[2])


def archive_optimizer(batch: int) -> None:
    for name in ("cma_state.pkl", "cma_generation.json", "covariance.csv",
                 "mean_log_multipliers.csv", "fitness_history.csv", "proposed_steps.json"):
        source = OPT / name
        if source.exists():
            shutil.copy2(source, OPT / f"b{batch:02d}_{name}")


def propose_next(batch: int) -> dict:
    next_batch = batch + 1
    proc = run([sys.executable, str(OPT / "propose_cmaes.py")], check=False,
               capture=True, env={"CALIB_REPO_DIR": str(RUN),
                                  "CALIB_BATCH_NO": str(next_batch)})
    if proc.returncode != 0:
        raise RuntimeError("CMA-ES proposal failed: " + proc.stdout[-4000:])
    archive_optimizer(next_batch)
    state = load_json(STATE, {})
    state["phase"] = f"batch{next_batch:02d}_running"
    state["updated_at"] = now()
    atomic_json(STATE, state)
    return state


def write_status(state: dict, runtime: dict, batch: int) -> None:
    summary = {"at": now(), "batch": batch, "phase": state.get("phase"), "cases": []}
    for case in cases_for(state, batch):
        legs = {}
        for dose, suffix in DOSES:
            session = f"oxcal_{case['case_tag']}_{suffix}"
            legs[dose] = {"complete": leg_complete(case["case_tag"], dose),
                          "running": tmux_alive(session),
                          "restarts": runtime.get("legs", {}).get(session, {}).get("restarts", 0)}
        summary["cases"].append({"case_tag": case["case_tag"],
                                 "metrics": metric_rows(case["case_tag"]) is not None,
                                 "legs": legs})
    atomic_json(CTRL / "controller-status.json", summary)


def tick(endpoint_tolerance: float) -> str:
    if (CTRL / "STOP").exists() or (RUN / "calibration" / "STOP").exists():
        return "stopped"
    state = load_json(STATE, {})
    runtime = load_json(RUNTIME, {"created_at": now(), "legs": {}})
    # If no batchNN_cases exist yet, initialize by proposing batch 1.
    if not any(re.fullmatch(r"batch\d+_cases", key) for key in state):
        state = propose_next(0)
        runtime["last_completed_batch"] = 0
        runtime["last_completed_at"] = now()
        launch_legs(cases_for(state, 1), runtime)
        atomic_json(RUNTIME, runtime)
        return f"batch01_running"
    batch = latest_batch(state)
    cases = cases_for(state, batch)
    reap_stale(cases, runtime)
    launch_legs(cases, runtime)
    atomic_json(RUNTIME, runtime)
    write_status(state, runtime, batch)
    if not all(leg_complete(case["case_tag"], dose)
               for case in cases for dose, _ in DOSES):
        if state.get("phase") != f"batch{batch:02d}_running":
            state["phase"] = f"batch{batch:02d}_running"
            state["updated_at"] = now()
            atomic_json(STATE, state)
        return f"batch{batch:02d}_running"

    state["phase"] = f"batch{batch:02d}_extracting"
    state["updated_at"] = now()
    atomic_json(STATE, state)
    for case in cases:
        if metric_rows(case["case_tag"]) is None:
            extract_metrics(case["case_tag"])
    completed = set(state.get("completed_cases", []))
    completed.update(case["case_tag"] for case in cases)
    state["completed_cases"] = sorted(completed)
    winners = [case["case_tag"] for case in cases
               if is_success(case["case_tag"], endpoint_tolerance)]
    if winners:
        state["phase"] = "complete"
        state["completed_at"] = now()
        state["successful_cases"] = winners
        atomic_json(STATE, state)
        write_status(state, runtime, batch)
        return "complete"
    atomic_json(STATE, state)
    state = propose_next(batch)
    runtime["last_completed_batch"] = batch
    runtime["last_completed_at"] = now()
    launch_legs(cases_for(state, batch + 1), runtime)
    atomic_json(RUNTIME, runtime)
    return f"batch{batch + 1:02d}_running"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("once", "run", "status"), nargs="?", default="once")
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--endpoint-tol", type=float, default=0.0)
    args = parser.parse_args()
    if not MATLAB.exists():
        raise SystemExit(f"required MATLAB not found: {MATLAB}")
    if args.command == "status":
        state = load_json(STATE, {})
        runtime = load_json(RUNTIME, {"legs": {}})
        write_status(state, runtime, latest_batch(state))
        print((CTRL / "controller-status.json").read_text(), end="")
        return 0
    with LOCK.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("controller already active")
            return 0
        while True:
            result = "error"
            try:
                result = tick(args.endpoint_tol)
                print(f"[{now()}] {result}", flush=True)
            except Exception as exc:
                runtime = load_json(RUNTIME, {"legs": {}})
                runtime["last_controller_error"] = {"at": now(), "message": str(exc)}
                atomic_json(RUNTIME, runtime)
                print(f"[{now()}] controller error: {exc}", file=sys.stderr, flush=True)
                if args.command == "once":
                    raise
            if args.command == "once" or result in ("complete", "stopped"):
                return 0
            time.sleep(max(30, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())
