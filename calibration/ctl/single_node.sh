#!/bin/bash
#SBATCH -C          cpu
#SBATCH -q          regular
#SBATCH -N          1
#SBATCH -t          18:00:00
#SBATCH -J          matfdm_cal
#SBATCH --dependency=singleton
#SBATCH --mail-type=BEGIN,END,FAIL,TIME_LIMIT
#SBATCH --mail-user=wzmse2023f@g.ucla.edu
#SBATCH --open-mode=append
#
# 一个作业 = 一个常驻 MATLAB + 一个 parpool, 能跑多远跑多远, 代码侧不限时。
#
# 代码与数据分离:
#   MATFDM_CODE  代码目录 (只读, 一份)
#   MATFDM_RUN   本次运行的数据目录 (结果/断点/指标/CMA 状态/日志 都在这里)
#                其中的 config.json 是唯一配置源
#
# 不要直接 sbatch 本文件, 用管理器:
#   bash calibration/ctl/matfdm.sh new ft05 front_thick=0.5
#   bash calibration/ctl/matfdm.sh submit ft05 4
# (直接 sbatch 也能跑, 那时 MATFDM_RUN 缺省回退到代码目录, 等于旧行为)

set -euo pipefail

CODE=${MATFDM_CODE:-$SLURM_SUBMIT_DIR}
RUN=${MATFDM_RUN:-$CODE}
export MATFDM_CODE MATFDM_RUN
export CALIB_REPO_DIR="$CODE"          # 代码根 (MATLAB addpath 用)
cd "$CODE"
mkdir -p "$RUN/calibration/logs"

# ---- 哨兵 1: 人工停止 ----
if [[ -e "$RUN/calibration/STOP" ]]; then
  echo "STOP 存在, 本作业退出"; exit 0
fi

module load matlab
module load python                      # 计算节点默认 python3 是 3.6, 不支持 3.7+ 语法
export CALIB_PYTHON=${CALIB_PYTHON:-$(command -v python3)}

# ---- license 席位: 抢不到不当场退出, 退避重试到墙钟为止 (见 lic_seat.sh) ----
export MATFDM_RUNS=${MATFDM_RUNS:-$(dirname "$RUN")}
# shellcheck source=lic_seat.sh
source "$CODE/calibration/ctl/lic_seat.sh"
END=$(scontrol show job "${SLURM_JOB_ID:-0}" 2>/dev/null \
      | tr ' ' '\n' | sed -n 's/^EndTime=//p' | head -1)
if [[ -n "$END" && "$END" != "Unknown" ]]; then
  DEADLINE=$(date -d "$END" +%s 2>/dev/null || echo 0)
else
  DEADLINE=0
fi
(( DEADLINE <= 0 )) && DEADLINE=$(( $(date +%s) + 3600 * 24 * 30 ))
GIVEUP=$(( DEADLINE - ${MATFDM_LIC_GIVEUP:-300} ))

# ---- 从 config.json 读运行参数 (环境变量可临时覆盖) ----
eval "$("$CALIB_PYTHON" - "$RUN/config.json" <<'PYEOF'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
c = json.loads(p.read_text()) if p.exists() else {}
def g(k, d): return c.get(k, d)
print(f'export CALIB_POPULATION=${{CALIB_POPULATION:-{g("population",40)}}}')
print(f'export CALIB_WORKERS=${{CALIB_WORKERS:-{g("workers",120)}}}')
print(f'export CALIB_ENDPOINT_TOL=${{CALIB_ENDPOINT_TOL:-{g("endpoint_tol",3)}}}')
print(f'export CALIB_MIDDLE_MAX=${{CALIB_MIDDLE_MAX:-{g("middle_max",70)}}}')
print(f'export CALIB_ENDPOINT_BAND=${{CALIB_ENDPOINT_BAND:-{g("endpoint_band",5)}}}')
print(f'export CALIB_MAX_ATTEMPTS=${{CALIB_MAX_ATTEMPTS:-{g("max_attempts",3)}}}')
print(f'export CALIB_SEED=${{CALIB_SEED:-{g("seed",20260804)}}}')
print(f'export CALIB_RUN_ID={g("run_id","default")}')
PYEOF
)"
export CALIB_STATE_PATH="$RUN/calibration/state.json"
export CALIB_OUT_DIR="$RUN/calibration/optimizer"
export CALIB_ENABLE_PLOTS=0

echo "=== job ${SLURM_JOB_ID:-local} start $(date)"
echo "=== run=$CALIB_RUN_ID  dir=$RUN"
echo "=== code=$CODE"
echo "=== python: $CALIB_PYTHON ($("$CALIB_PYTHON" -c 'import sys;print(sys.version.split()[0])'))"
echo "=== pop=$CALIB_POPULATION workers=$CALIB_WORKERS middle_max=$CALIB_MIDDLE_MAX band=$CALIB_ENDPOINT_BAND"

# ---- 哨兵 2: DONE 复核 (判据收紧后旧命中自动作废, 不再永久挡住后续作业) ----
dv=$("$CALIB_PYTHON" "$CODE/calibration/ctl/gen_tool.py" validate-done \
       --tol "$CALIB_ENDPOINT_TOL" 2>&1) || true
echo "$dv"
if [[ "$dv" == DONE_VALID=* ]]; then
  echo "标定已命中且按当前判据仍达标, 本作业退出"; exit 0
fi

"$CALIB_PYTHON" "$CODE/calibration/ctl/gen_tool.py" history 0 2>/dev/null || true

trap 'lic_seat_release' EXIT
lic_run_matlab "$CODE" "$RUN" "$RUN/calibration/STOP" "$GIVEUP" "single" || true

echo "=== job ${SLURM_JOB_ID:-local} matlab exit $(date)"
if [[ -e "$RUN/calibration/DONE" ]]; then
  echo "标定命中: $(cat "$RUN/calibration/DONE")"
else
  echo "未命中: matfdm.sh submit $CALIB_RUN_ID 继续排作业"
fi
