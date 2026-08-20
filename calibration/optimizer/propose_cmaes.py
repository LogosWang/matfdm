#!/usr/bin/env python3
"""Persistent constrained ask--tell CMA-ES for the ten calibration variables."""

from __future__ import annotations

import csv
import json
import math
import os
import pickle
import re
import sys
import warnings
from pathlib import Path

import numpy as np

CTRL = Path(__file__).resolve().parents[1]
VENDOR = CTRL / "vendor"
sys.path.insert(0, str(VENDOR))
warnings.filterwarnings("ignore", message="Could not import matplotlib")
try:
    import cma
except ImportError as exc:
    raise SystemExit(
        f"pycma is missing; install {CTRL / 'requirements-calibration.txt'} "
        f"into {VENDOR}") from exc

STATE = Path(os.environ.get("CALIB_STATE_PATH", CTRL / "state.json"))
RUN = Path(os.environ.get("CALIB_REPO_DIR", "/mnt/c/Users/vool/matfdm_calibration_20260731"))
METRICS = RUN / "calibration" / "metrics"
OUT = Path(os.environ.get("CALIB_OUT_DIR", Path(__file__).resolve().parent))
STATE_PICKLE = OUT / "cma_state.pkl"
NAMES = ["kCr", "kFe", "kSi", "kspin", "DCr2O3O", "DFe3O4",
         "DFeCr2O4", "DSiO2", "kRobin", "E_mag"]
LOWER = np.full(10, math.log(0.03))
UPPER = np.full(10, math.log(60.0))
DOMAIN_WIDTH = UPPER - LOWER
POPULATION = int(os.environ.get("CALIB_POPULATION", "10"))
# 多链并行: 每条链给不同 CALIB_SEED, 否则各链的 ask 序列完全相同, 等于白跑
SEED = int(os.environ.get("CALIB_SEED", "20260804"))
# 0.5 dpa 前沿软带上限 (nm): 带内 [60, MIDDLE_MAX] 视为达标
MIDDLE_MAX = float(os.environ.get("CALIB_MIDDLE_MAX", "70"))
# 端点(0 与 3 dpa)容差 (nm): 超出即判不可行 —— 端点是硬约束, 优先级高于一切,
# 任何端点超差的样本都排在全部端点达标样本之后, 中间腿再好也换不来名次。
ENDPOINT_BAND = float(os.environ.get("CALIB_ENDPOINT_BAND", "5"))
CONSTRAINT_PENALTY = 1.0e4
FORMAT_VERSION = 1


def atomic_json(path: Path, obj) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2) + "\n")
    os.replace(tmp, path)


def atomic_pickle(path: Path, obj) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("wb") as stream:
        pickle.dump(obj, stream, protocol=pickle.HIGHEST_PROTOCOL)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)


def batch_cases(state: dict, batch: int) -> list[dict]:
    cases = state.get(f"batch{batch:02d}_cases", [])
    if len(cases) != POPULATION:
        raise RuntimeError(f"batch {batch} has {len(cases)} cases, expected {POPULATION}")
    return cases


def completed_batches(state: dict, last: int) -> list[int]:
    batches = []
    for key, value in state.items():
        match = re.fullmatch(r"batch(\d+)_cases", key)
        if not match or not isinstance(value, list):
            continue
        batch = int(match.group(1))
        if batch <= last and len(value) == POPULATION and all(
                (METRICS / f"{case['case_tag']}.csv").exists() for case in value):
            batches.append(batch)
    return sorted(batches)


def residual_and_constraints(tag: str):
    with (METRICS / f"{tag}.csv").open(newline="") as stream:
        rows = sorted(csv.DictReader(stream), key=lambda row: float(row["dose"]))
    if len(rows) != 3:
        raise ValueError(f"{tag}: expected three metric rows")
    raw = np.array([float(row["residual_nm"]) for row in rows])
    middle = 60.0 + raw[1]
    # 0.5 dpa: 最小值在 60, 全程有梯度, 分段连续。
    #   带内 [60, MIDDLE_MAX] 斜率 1/6 —— 端点是 1/3, 取一半:
    #     既保证进带之后仍持续朝 60 推进 (旧的 1/30 只有端点的十分之一,
    #     CMA 会拿中间腿去换端点上的零点几纳米), 又不至于压倒两个端点。
    #   带外斜率 1/3 (与端点同量级), 在 MIDDLE_MAX 处连续。
    if middle < 60.0:
        middle_residual = (60.0 - middle) / 5.0
    elif middle <= MIDDLE_MAX:
        middle_residual = (middle - 60.0) / 6.0
    else:
        middle_residual = (MIDDLE_MAX - 60.0) / 6.0 + (middle - MIDDLE_MAX) / 4.0
    front = [raw[0] / 3.0, middle_residual, raw[2] / 3.0]

    cr = np.array([float(row["Cr_atom_pct"]) for row in rows])
    fe = np.array([float(row["Fe_atom_pct"]) for row in rows])
    si = np.array([float(row["Si_atom_pct"]) for row in rows])
    composition = []
    for cr_i, fe_i, si_i in zip(cr, fe, si):
        composition.extend((max(0.0, (fe_i - cr_i) / 10.0),
                            max(0.0, (si_i - cr_i) / 10.0)))
    shape = [max(0.0, (cr[1] - cr[0]) / 2.0),
             max(0.0, (cr[2] - cr[1]) / 2.0),
             max(0.0, (cr[2] - fe[2] - 15.0) / 5.0)]

    inventory = np.array([float(row["Cr_atom_inventory"]) for row in rows])
    if not np.all(np.isfinite(inventory)) or inventory[0] <= 0:
        raise ValueError(f"{tag}: invalid Cr inventory")
    monotonic = [max(0.0, (inventory[1] - inventory[0]) / inventory[0] * 50.0),
                 max(0.0, (inventory[2] - inventory[1]) / inventory[0] * 50.0)]
    residual = np.asarray(front + composition + shape + monotonic)

    eps = 1.0e-6
    constraints = [(inventory[1] - inventory[0]) / inventory[0] + eps,
                   (inventory[2] - inventory[1]) / inventory[0] + eps]
    for cr_i, fe_i, si_i in zip(cr, fe, si):
        constraints.extend(((fe_i - cr_i) / 100.0 + eps,
                            (si_i - cr_i) / 100.0 + eps))
    constraints.append((cr[2] - fe[2] - 15.0) / 100.0 + eps)
    # 端点硬约束: |front - target| <= ENDPOINT_BAND。放进 constraints 即进入
    # lexicographic 分层 —— 端点超差的样本永远排在端点达标的样本之后。
    constraints.append((abs(raw[0]) - ENDPOINT_BAND) / ENDPOINT_BAND)
    constraints.append((abs(raw[2]) - ENDPOINT_BAND) / ENDPOINT_BAND)
    constraints = np.asarray(constraints)
    feasible = bool(inventory[0] > inventory[1] > inventory[2]
                    and np.all(cr > fe) and np.all(cr > si)
                    and cr[2] - fe[2] <= 15.0
                    and abs(raw[0]) <= ENDPOINT_BAND
                    and abs(raw[2]) <= ENDPOINT_BAND)
    return residual, constraints, feasible


def evaluate_case(case: dict) -> dict:
    residual, constraints, feasible = residual_and_constraints(case["case_tag"])
    objective = float(residual @ residual)
    violation = float(CONSTRAINT_PENALTY * np.sum(np.maximum(constraints, 0.0) ** 2))
    # CMA-ES is rank based. A fixed feasibility tier makes every feasible
    # result rank ahead of every infeasible result, while infeasible samples
    # are ordered by normalized constraint violation and then target error.
    fitness = objective if feasible else 1.0e6 + 1000.0 * violation + objective
    x = np.log(np.asarray(case["mult"], dtype=float))
    return {"case_tag": case["case_tag"], "x": x, "objective": objective,
            "violation": violation, "feasible": feasible, "fitness": fitness,
            "constraints": constraints}


def evaluate_batch(state: dict, batch: int) -> list[dict]:
    records = [evaluate_case(case) for case in batch_cases(state, batch)]
    if len(records) != POPULATION:
        raise RuntimeError(f"batch {batch}: incomplete CMA population")
    return records


def cma_options(seed: int) -> dict:
    return {
        "bounds": [LOWER.tolist(), UPPER.tolist()],
        "popsize": POPULATION,
        "seed": seed,
        "CMA_active": True,
        "CMA_mirrors": 2,
        "CMA_diagonal": 0,
        "tolx": 1.0e-9,
        "tolfun": 1.0e-10,
        "maxiter": 100000,
        "verbose": -9,
        "verb_disp": 0,
        "verb_log": 0,
    }


def new_es(mean: np.ndarray, sigma: float, seed: int):
    return cma.CMAEvolutionStrategy(np.clip(mean, LOWER, UPPER).tolist(), sigma,
                                    cma_options(seed))


def record_is_better(candidate: dict, current: dict | None) -> bool:
    if current is None:
        return True
    candidate_key = (0, candidate["objective"]) if candidate["feasible"] else (
        1, candidate["violation"], candidate["objective"])
    current_key = (0, current["objective"]) if current["feasible"] else (
        1, current["violation"], current["objective"])
    return candidate_key < current_key


def update_best(payload: dict, records: list[dict]) -> bool:
    improved = False
    current = payload.get("best")
    for record in records:
        if record_is_better(record, current):
            current = {key: (value.tolist() if isinstance(value, np.ndarray) else value)
                       for key, value in record.items()}
            improved = True
    payload["best"] = current
    payload["stagnation_generations"] = 0 if improved else int(
        payload.get("stagnation_generations", 0)) + 1
    return improved


def tell_batch(payload: dict, state: dict, batch: int) -> None:
    records = evaluate_batch(state, batch)
    es = payload["es"]
    # A warm-start population may predate CMA-ES, so create the internal ask
    # bookkeeping and then tell CMA the measured points rather than discarding
    # their expensive information.
    pending = payload.get("pending_batch")
    if pending is None:
        es.ask()
    elif pending != batch:
        raise RuntimeError(f"CMA pending batch is {pending}, cannot tell batch {batch}")
    es.tell([record["x"] for record in records],
            [record["fitness"] for record in records])
    payload.setdefault("told_batches", []).append(batch)
    payload["pending_batch"] = None
    payload["pending_x"] = None
    payload["pending_proposals"] = None
    update_best(payload, records)


def deterministic_global_center(restart: int) -> np.ndarray:
    # A low-discrepancy-like deterministic point keeps restarts reproducible.
    primes = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29)

    def radical(index: int, base: int) -> float:
        factor = 1.0
        value = 0.0
        while index:
            factor /= base
            value += factor * (index % base)
            index //= base
        return value

    u = np.array([radical(37 * restart + 17, base) for base in primes])
    span = min(3.2, 1.2 + 0.35 * restart)
    return np.clip((2.0 * u - 1.0) * span, LOWER, UPPER)


def maybe_restart(payload: dict) -> dict:
    es = payload["es"]
    covariance = np.asarray(es.C, dtype=float)
    condition = float(np.linalg.cond(covariance))
    stop = {str(key): str(value) for key, value in es.stop().items()}
    stagnation = int(payload.get("stagnation_generations", 0))
    reason = None
    if stagnation >= 8:
        reason = "eight_generations_without_historical_improvement"
    elif condition > 1.0e10:
        reason = "covariance_condition"
    elif es.countiter >= 4 and stop:
        reason = "pycma_stop:" + ",".join(stop)
    if reason is None:
        payload["last_stop_reasons"] = stop
        return payload

    restart = int(payload.get("restart_count", 0)) + 1
    best = payload.get("best")
    if restart % 2 == 1 and best is not None:
        mean = np.asarray(best["x"], dtype=float)
        center_kind = "historical_best"
    else:
        mean = deterministic_global_center(restart)
        center_kind = "global_deterministic"
    sigma = min(2.4, 0.75 * 1.45 ** restart)
    payload["es"] = new_es(mean, sigma, SEED + 1009 * restart)
    payload["restart_count"] = restart
    payload["last_restart"] = {"reason": reason, "center": center_kind,
                               "sigma": sigma}
    payload["stagnation_generations"] = 0
    return payload


def normalized_distance(x: np.ndarray, points: list[np.ndarray]) -> float:
    if not points:
        return math.inf
    matrix = np.vstack(points)
    return float(np.linalg.norm((matrix - x) / DOMAIN_WIDTH, axis=1).min())


def ask_population(payload: dict, state: dict, batch: int) -> list[dict]:
    es = payload["es"]
    historical = [np.log(np.asarray(case["mult"], dtype=float))
                  for old_batch in payload.get("told_batches", [])
                  for case in batch_cases(state, old_batch)]
    asked = []
    attempts = 0
    while len(asked) < POPULATION:
        candidates = es.ask(POPULATION - len(asked))
        for candidate in candidates:
            x = np.clip(np.asarray(candidate, dtype=float), LOWER, UPPER)
            if normalized_distance(x, historical + asked) < 1.0e-7:
                continue
            asked.append(x)
        attempts += 1
        if attempts > 20:
            raise RuntimeError("CMA-ES repeatedly emitted duplicate candidates")

    covariance = np.asarray(es.C, dtype=float)
    condition = float(np.linalg.cond(covariance))
    generation = int(es.countiter) + 1
    proposals = []
    actual_x = []
    for index, x in enumerate(asked, 1):
        mult = [round(float(value), 10) for value in np.exp(x)]
        stored_x = np.log(np.asarray(mult))
        actual_x.append(stored_x)
        proposals.append({
            "case_tag": f"b{batch:02d}_c{index:02d}_cma",
            "mult": mult,
            "proposal_type": "cmaes_ask",
            "cma_generation": generation,
            "cma_restart": int(payload.get("restart_count", 0)),
            "cma_sigma": float(es.sigma),
            "cma_covariance_condition": condition,
            "coupling_model": "full_covariance_10d",
            "ask_index": index,
        })
    payload["pending_batch"] = batch
    payload["pending_x"] = [x.tolist() for x in actual_x]
    payload["pending_proposals"] = proposals
    return proposals


def write_fitness_history(state: dict, batches: list[int]) -> None:
    path = OUT / "fitness_history.csv"
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("batch", "case_tag", "objective", "violation", "feasible", "fitness"))
        for batch in batches:
            for record in evaluate_batch(state, batch):
                writer.writerow((batch, record["case_tag"], record["objective"],
                                 record["violation"], int(record["feasible"]),
                                 record["fitness"]))


def diagnostics(payload: dict) -> dict:
    es = payload["es"]
    covariance = np.asarray(es.C, dtype=float)
    return {
        "strategy": "constrained_active_cmaes_ask_tell",
        "library": f"pycma {cma.__version__}",
        "population": POPULATION,
        "dimension": 10,
        "generation_told": int(es.countiter),
        "pending_batch": payload.get("pending_batch"),
        "restart_count": int(payload.get("restart_count", 0)),
        "sigma": float(es.sigma),
        "mean_log_multipliers": [float(value) for value in es.mean],
        "covariance_condition": float(np.linalg.cond(covariance)),
        "stagnation_generations": int(payload.get("stagnation_generations", 0)),
        "best": payload.get("best"),
        "last_restart": payload.get("last_restart"),
        "last_stop_reasons": payload.get("last_stop_reasons", {}),
        "constraint_handling": "feasibility_first_rank_then_violation_then_objective",
        "coupling_model": "learned_full_10x10_covariance",
    }


def persist_outputs(payload: dict, state: dict, proposals: list[dict]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    covariance = np.asarray(payload["es"].C, dtype=float)
    np.savetxt(OUT / "covariance.csv", covariance, delimiter=",",
               header=",".join(NAMES), comments="")
    np.savetxt(OUT / "mean_log_multipliers.csv",
               np.asarray(payload["es"].mean)[None, :], delimiter=",",
               header=",".join(NAMES), comments="")
    atomic_json(OUT / "cma_generation.json", diagnostics(payload))
    atomic_json(OUT / "proposed_steps.json", proposals)
    write_fitness_history(state, payload.get("told_batches", []))
    atomic_pickle(STATE_PICKLE, payload)


def main() -> None:
    state = json.loads(STATE.read_text())
    requested_batch = int(os.environ.get("CALIB_BATCH_NO", "1"))
    completed = requested_batch - 1
    if STATE_PICKLE.exists():
        with STATE_PICKLE.open("rb") as stream:
            payload = pickle.load(stream)
        if payload.get("format_version") != FORMAT_VERSION:
            raise RuntimeError("unsupported CMA state format")
        if payload.get("pending_batch") == requested_batch:
            proposals = payload["pending_proposals"]
            state[f"batch{requested_batch:02d}_cases"] = proposals
            state["phase"] = f"batch{requested_batch:02d}_ready"
            state.setdefault("optimizer", {})["latest"] = diagnostics(payload)
            atomic_json(STATE, state)
            persist_outputs(payload, state, proposals)
            print(json.dumps({"idempotent": True, "cases": proposals}, indent=2))
            return
    else:
        payload = {
            "format_version": FORMAT_VERSION,
            "es": new_es(np.zeros(10), 0.65, SEED),
            "told_batches": [],
            "pending_batch": None,
            "pending_x": None,
            "pending_proposals": None,
            "restart_count": 0,
            "stagnation_generations": 0,
            "best": None,
        }

    if requested_batch > 1:
        available = completed_batches(state, completed)
        for batch in available:
            if batch not in payload["told_batches"]:
                tell_batch(payload, state, batch)
        if completed not in payload["told_batches"]:
            raise RuntimeError(f"completed batch {completed} has no complete metrics")
    elif payload.get("told_batches"):
        raise RuntimeError("cannot initialize generation 1 after CMA history was told")
    # ---- 采纳磁盘上已有的本代提案, 而不是重新 ask ----
    # 触发场景: 上次运行 ask 过(state.json 已有 batchNN_cases)但 cma_state.pkl
    # 丢失/损坏。若此时重新 ask, 同名 case (b0N_c01_cma ...) 会拿到不同乘子,
    # 与已算完的结果、半路的 checkpoint 错配 —— fitness 直接污染。
    # 采纳后 case 与参数保持原样, 已完成的腿仍然有效。
    existing = state.get(f"batch{requested_batch:02d}_cases")
    if (existing and os.environ.get("CALIB_ADOPT_EXISTING", "1") == "1"
            and payload.get("pending_batch") != requested_batch):
        if len(existing) != POPULATION:
            raise RuntimeError(
                f"batch {requested_batch} 磁盘上有 {len(existing)} 个 case, "
                f"与 POPULATION={POPULATION} 不符; 人工确认后再跑")
        payload["pending_batch"] = requested_batch
        payload["pending_proposals"] = existing
        payload["pending_x"] = [np.log(np.asarray(case["mult"], dtype=float)).tolist()
                                for case in existing]
        state["phase"] = f"batch{requested_batch:02d}_ready"
        optimizer = state.setdefault("optimizer", {})
        optimizer["latest"] = diagnostics(payload)
        persist_outputs(payload, state, existing)
        atomic_json(STATE, state)
        print(json.dumps({"adopted_existing": True, "batch": requested_batch,
                          "cases": len(existing)}, indent=2))
        return

    payload = maybe_restart(payload)
    proposals = ask_population(payload, state, requested_batch)
    state[f"batch{requested_batch:02d}_cases"] = proposals
    state["phase"] = f"batch{requested_batch:02d}_ready"
    # 赋值语句先求右侧: 原写法在 state 无 optimizer 键时(冷启动)会 KeyError。
    optimizer = state.setdefault("optimizer", {})
    optimizer["previous"] = optimizer.get("latest", {})
    optimizer["latest"] = diagnostics(payload)
    persist_outputs(payload, state, proposals)
    atomic_json(STATE, state)
    print(json.dumps({"cma": diagnostics(payload), "cases": proposals}, indent=2))


if __name__ == "__main__":
    main()
