#!/usr/bin/env bash
# 多节点作业里每个节点执行的东西 —— 一个节点 = 一个 MATLAB + 一个 parpool,
# 跑清单里属于自己的那个运行目录, 内容与单节点模式完全一致。
#
# 由 multi_node.sh 通过 srun 拉起, 每节点一个 task。
# 入参: $1 = 清单文件 (每行一个运行目录的绝对路径)
#
# 节点之间零通信: 各自的 MATFDM_RUN 不同, 结果/断点/CMA 状态互不可见。
# 单个节点崩了不影响其他节点 (srun --kill-on-bad-exit=0, 且本脚本永远 exit 0)。
#
# 引擎 (MATFDM_ENGINE):
#   mcr    默认。跑编译好的 standalone, 编排交给 run_generation.py。
#          NERSC 全校只有 16 个 MATLAB / 4 个 PCT 席位, 文档要求多节点作业用编译版;
#          MCR 不连 license server, 这条路占用 0 席位, 也就不需要抢席位。
#   matlab 回退路线。老的 matlab -batch run_generation + parpool, 要抢 license,
#          抢不到就退避重试 (lic_seat.sh), 绝不秒退 —— 秒退会把 afterany 接力链
#          瞬间烧光 (2026-08-23 事故: 13 个作业 20 分钟全烧完)。

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

ENGINE=${MATFDM_ENGINE:-mcr}
# 席位库只有回退路线才用得上; source 它没有副作用
# shellcheck source=lic_seat.sh
source "$CODE/calibration/ctl/lic_seat.sh"

ID=$("$CALIB_PYTHON" -c "import json,sys;print(json.load(open(sys.argv[1]))['run_id'])" "$RUN/config.json" 2>/dev/null || basename "$RUN")
LOG="$RUN/node-${SLURM_JOB_ID:-local}-r${RANK}.log"
STOPF="$RUN/calibration/STOP"

# 作业截止时刻: multi_node.sh 从 scontrol 算好传进来; 没有就当作不限时
DEADLINE=${MATFDM_DEADLINE:-0}
if (( DEADLINE <= 0 )); then DEADLINE=$(( $(date +%s) + 3600 * 24 * 30 )); fi
GIVEUP=$(( DEADLINE - ${MATFDM_LIC_GIVEUP:-300} ))   # 留点余量收尾, 不要被 SIGKILL 撞上

{
  echo "=== rank $RANK  node $(hostname)  run=$ID"
  echo "=== dir=$RUN"
  echo "=== $(date)"
  if [[ "$ENGINE" == mcr ]]; then
    echo "=== 引擎: MCR standalone (0 个 license 席位)  build=${MATFDM_BUILD_COMMIT:-?}"
  else
    echo "=== 引擎: matlab (回退路线)  入闸 $LIC_SEATS 席, 抢到 $(date -d "@$GIVEUP" '+%F %T') 为止"
  fi

  if [[ -e "$STOPF" ]]; then
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

  # ================= 跑一代一代的标定 =================
  if [[ "$ENGINE" == mcr ]]; then
    # 编译版: 0 个 license 席位, 直接开跑, 没有可抢的东西
    export MATFDM_DEADLINE
    "$CALIB_PYTHON" "$CODE/calibration/ctl/run_generation.py"
    rc=$?
    echo "=== rank $RANK run_generation.py 退出码 $rc  $(date)"
  else
    # 回退路线: 抢 MATLAB license 席位 (共用 lic_seat.sh 的循环)
    trap 'lic_seat_release' EXIT
    lic_run_matlab "$CODE" "$RUN" "$STOPF" "$GIVEUP" "r$RANK"
  fi

} >> "$LOG" 2>&1

exit 0   # 永远成功: 单节点失败不拖垮整个作业
