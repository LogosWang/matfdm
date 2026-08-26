#!/bin/bash
#SBATCH -C          cpu
#SBATCH -q          regular
#SBATCH -J          matfdm_mn
#SBATCH --open-mode=append
#SBATCH --mail-type=BEGIN,END,FAIL,TIME_LIMIT
#SBATCH --mail-user=wzmse2023f@g.ucla.edu
#
# 多节点标定作业: 一个作业占 N 个节点, 每节点起一个 MATLAB + 一个 parpool,
# 各跑清单里属于自己的那个运行目录 —— 与单节点模式完全一致, 只是并了 N 份。
#
# 节点数 (-N)、墙钟 (-t)、账号 (-A) 由 matfdm.sh launch 在提交时给出, 不写死。
# 必需环境变量 (matfdm.sh 通过 --export 传入):
#   MATFDM_CODE      代码目录 (只读)
#   MATFDM_MANIFEST  清单文件, 每行一个运行目录绝对路径, 第 k 行给第 k 个节点
#
# 不要直接 sbatch 本文件, 用:
#   bash calibration/ctl/matfdm.sh launch <manifest名> [作业数]

set -uo pipefail

CODE=${MATFDM_CODE:?"缺 MATFDM_CODE"}
MANIFEST=${MATFDM_MANIFEST:?"缺 MATFDM_MANIFEST"}
NNODES=${SLURM_JOB_NUM_NODES:-1}

ENGINE=${MATFDM_ENGINE:-mcr}
module load python
if [[ "$ENGINE" == mcr ]]; then
  # 编译版: 只要 Runtime, 不加载 matlab, 不签任何 license
  module load matlab-mcr 2>/dev/null || true
  export MCR_ROOT=${MCR_ROOT:-/global/common/software/nersc9/matlab/MCR/R2023b}
  export MATFDM_BUILD_DIR=${MATFDM_BUILD_DIR:-${MATFDM_BUILD:-$SCRATCH/matfdm_build}/CURRENT}
  export MATFDM_BUILD_COMMIT=$(cat "$MATFDM_BUILD_DIR/BUILD_COMMIT" 2>/dev/null || echo unknown)
  [[ -x "$MATFDM_BUILD_DIR/run_matfdm_run.sh" ]] || {
    echo "!! 没有编译产物 $MATFDM_BUILD_DIR, 先跑 build_standalone.sh" >&2; exit 1; }
  # CTF 解压缓存必须放节点本地 (/tmp 是 tmpfs); 放 Lustre 会被 120 进程打死
  export MCR_CACHE_ROOT=/tmp/$USER/mcr.${SLURM_JOB_ID:-local}
else
  module load matlab
fi
export CALIB_PYTHON=${CALIB_PYTHON:-$(command -v python3)}
export MATFDM_CODE MATFDM_ENGINE="$ENGINE"

# ---- 作业截止时刻: 节点侧据此决定腿的墙钟预算 (回退路线还用它决定重试多久) ----
END=$(scontrol show job "${SLURM_JOB_ID:-0}" 2>/dev/null \
      | tr ' ' '\n' | sed -n 's/^EndTime=//p' | head -1)
if [[ -n "$END" && "$END" != "Unknown" ]]; then
  MATFDM_DEADLINE=$(date -d "$END" +%s 2>/dev/null || echo 0)
else
  MATFDM_DEADLINE=0
fi
export MATFDM_DEADLINE
export MATFDM_RUNS=${MATFDM_RUNS:-$(dirname "$MANIFEST")}
export MATFDM_LIC_POOL=${MATFDM_LIC_POOL:-$MATFDM_RUNS/.lic_seats}
export MATFDM_LIC_SEATS=${MATFDM_LIC_SEATS:-2}
export MATFDM_LIC_HOLD=${MATFDM_LIC_HOLD:-420}
export MATFDM_LIC_BACKOFF=${MATFDM_LIC_BACKOFF:-30}
export MATFDM_LIC_BACKOFF_MAX=${MATFDM_LIC_BACKOFF_MAX:-600}
export MATFDM_HARD_RETRIES=${MATFDM_HARD_RETRIES:-2}
# 上一个作业被 SIGKILL 时可能留下没释放的令牌, 开工前清一遍
mkdir -p "$MATFDM_LIC_POOL"
find "$MATFDM_LIC_POOL" -maxdepth 1 -name 'seat*' -type d \
     -mmin +$(( MATFDM_LIC_HOLD / 60 + 1 )) -exec rm -rf {} + 2>/dev/null || true

echo "================================================================"
echo "job     : ${SLURM_JOB_ID:-local}"
echo "nodes   : $NNODES"
echo "manifest: $MANIFEST ($(wc -l < "$MANIFEST") 个运行)"
echo "code    : $CODE"
echo "python  : $CALIB_PYTHON ($("$CALIB_PYTHON" -c 'import sys;print(sys.version.split()[0])'))"
echo "start   : $(date)"
if (( MATFDM_DEADLINE > 0 )); then
  if [[ "$ENGINE" == mcr ]]; then
    echo "deadline: $(date -d "@$MATFDM_DEADLINE" '+%F %T')  (腿据此定墙钟预算, 到点存断点)"
  else
    echo "deadline: $(date -d "@$MATFDM_DEADLINE" '+%F %T')  (节点抢 license 抢到这个点)"
  fi
else
  echo "deadline: 未知 (scontrol 没给 EndTime), 腿按不限时跑到被 SLURM 杀"
fi
if [[ "$ENGINE" == mcr ]]; then
  echo "engine  : MCR standalone  build=$MATFDM_BUILD_COMMIT  ($MATFDM_BUILD_DIR)"
  echo "license : 0 个席位 (MCR 不连 license server)"
else
  echo "engine  : matlab (回退路线)"
  echo "license : 入闸 $MATFDM_LIC_SEATS 席, 退避 ${MATFDM_LIC_BACKOFF}-${MATFDM_LIC_BACKOFF_MAX}s, 池 $MATFDM_LIC_POOL"
fi
echo "================================================================"
sed -n "1,${NNODES}p" "$MANIFEST" | nl -w3 -s'  节点 -> '

# 每节点一个 task, 独占整节点的 CPU; 单个 task 失败不终止整个 step
srun --nodes="$NNODES" --ntasks="$NNODES" --ntasks-per-node=1 \
     -c 128 --cpu-bind=none --kill-on-bad-exit=0 --wait=0 \
     bash "$CODE/calibration/ctl/node_task.sh" "$MANIFEST"

echo "================================================================"
echo "job ${SLURM_JOB_ID:-local} 结束 $(date)"
# 各运行的收尾状态
while read -r d; do
  [[ -n "$d" ]] || continue
  id=$(basename "$d")
  if [[ -e "$d/calibration/DONE" ]]; then
    echo "  $id : 命中 $(cat "$d/calibration/DONE")"
  else
    n=$(ls "$d"/calibration/metrics/*.csv 2>/dev/null | wc -l)
    lg="$d/node-${SLURM_JOB_ID:-local}-r"*.log
    if [[ "$ENGINE" == mcr ]]; then
      echo "  $id : 未命中, 已完成 $n 次评估"
    else
      tries=$(grep -hc '^--- 第 ' $lg 2>/dev/null | head -1)
      echo "  $id : 未命中, 已完成 $n 次评估, license 尝试 ${tries:-0} 次"
    fi
  fi
done < <(sed -n "1,${NNODES}p" "$MANIFEST")

# 本作业自己留下的令牌一律清掉, 不留给下一轮 (下一轮开工前也会再清一次)
rm -rf "$MATFDM_LIC_POOL"/seat* 2>/dev/null || true
