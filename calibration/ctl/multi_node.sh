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

module load matlab
module load python
export CALIB_PYTHON=${CALIB_PYTHON:-$(command -v python3)}
export MATFDM_CODE

echo "================================================================"
echo "job     : ${SLURM_JOB_ID:-local}"
echo "nodes   : $NNODES"
echo "manifest: $MANIFEST ($(wc -l < "$MANIFEST") 个运行)"
echo "code    : $CODE"
echo "python  : $CALIB_PYTHON ($("$CALIB_PYTHON" -c 'import sys;print(sys.version.split()[0])'))"
echo "start   : $(date)"
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
    echo "  $id : 未命中, 已完成 $n 次评估"
  fi
done < <(sed -n "1,${NNODES}p" "$MANIFEST")
