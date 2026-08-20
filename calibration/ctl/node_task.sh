#!/usr/bin/env bash
# 多节点作业里每个节点执行的东西 —— 一个节点 = 一个 MATLAB + 一个 parpool,
# 跑清单里属于自己的那个运行目录, 内容与单节点模式完全一致。
#
# 由 multi_node.sh через srun 拉起, 每节点一个 task。
# 入参: $1 = 清单文件 (每行一个运行目录的绝对路径)
#
# 节点之间零通信: 各自的 MATFDM_RUN 不同, 结果/断点/CMA 状态互不可见。
# 单个节点崩了不影响其他节点 (srun --kill-on-bad-exit=0, 且本脚本永远 exit 0)。

set -uo pipefail

MANIFEST=${1:?"用法: node_task.sh <manifest>"}
RANK=${SLURM_PROCID:-0}
LINE=$((RANK + 1))
RUN=$(sed -n "${LINE}p" "$MANIFEST")

if [[ -z "$RUN" ]]; then
  echo "[rank $RANK] 清单里没有第 $LINE 行, 本节点空转"
  exit 0
fi
if [[ ! -f "$RUN/config.json" ]]; then
  echo "[rank $RANK] $RUN 缺 config.json, 跳过"
  exit 0
fi

CODE=${MATFDM_CODE:?}
export MATFDM_RUN="$RUN"
export CALIB_REPO_DIR="$CODE"
mkdir -p "$RUN/calibration/logs"

ID=$("$CALIB_PYTHON" -c "import json,sys;print(json.load(open(sys.argv[1]))['run_id'])" "$RUN/config.json" 2>/dev/null || basename "$RUN")
LOG="$RUN/node-${SLURM_JOB_ID:-local}-r${RANK}.log"

{
  echo "=== rank $RANK  node $(hostname)  run=$ID"
  echo "=== dir=$RUN"
  echo "=== $(date)"

  if [[ -e "$RUN/calibration/STOP" ]]; then
    echo "STOP 存在, 本节点退出"; exit 0
  fi

  # ---- 运行参数: config.json 是唯一真相源 ----
  eval "$("$CALIB_PYTHON" - "$RUN/config.json" <<'PYEOF'
import json, sys
from pathlib import Path
c = json.loads(Path(sys.argv[1]).read_text())
g = c.get
print(f'export CALIB_POPULATION={g("population",40)}')
print(f'export CALIB_WORKERS={g("workers",120)}')
print(f'export CALIB_ENDPOINT_TOL={g("endpoint_tol",3)}')
print(f'export CALIB_MIDDLE_MAX={g("middle_max",70)}')
print(f'export CALIB_ENDPOINT_BAND={g("endpoint_band",5)}')
print(f'export CALIB_MAX_ATTEMPTS={g("max_attempts",3)}')
print(f'export CALIB_SEED={g("seed",20260804)}')
PYEOF
)"
  export CALIB_STATE_PATH="$RUN/calibration/state.json"
  export CALIB_OUT_DIR="$RUN/calibration/optimizer"
  export CALIB_ENABLE_PLOTS=0
  echo "=== pop=$CALIB_POPULATION workers=$CALIB_WORKERS middle_max=$CALIB_MIDDLE_MAX"

  # ---- DONE 复核: 判据收紧后旧命中自动作废 ----
  dv=$("$CALIB_PYTHON" "$CODE/calibration/ctl/gen_tool.py" validate-done \
         --tol "$CALIB_ENDPOINT_TOL" 2>&1) || true
  echo "$dv"
  if [[ "$dv" == DONE_VALID=* ]]; then
    echo "已命中且仍达标, 本节点退出"; exit 0
  fi

  cd "$CODE"
  matlab -nodisplay -nosplash -batch \
    "addpath('$CODE'); addpath('$CODE/calibration/ctl'); run_generation"
  rc=$?
  echo "=== rank $RANK matlab 退出码 $rc  $(date)"
} >> "$LOG" 2>&1

exit 0   # 永远成功: 单节点失败不拖垮整个作业
