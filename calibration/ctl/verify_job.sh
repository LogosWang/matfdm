#!/bin/bash
#SBATCH -C          cpu
#SBATCH -q          regular
#SBATCH -J          verify_ft
#SBATCH --open-mode=append
#
# 验证作业: 用标定选出的前 N 名参数跑长时氧化曲线, 与实验前沿对照。
# 节点数由 verify_job.sh 提交时算好 (-N), 不写死。
#
# 必需环境变量 (VERIFY.sh 通过 --export 传入):
#   MATFDM_CODE / MATFDM_RUNS / MATFDM_VERIFY_ROOT / MATFDM_VERIFY_MANIFEST
#
# 不要直接 sbatch, 用 VERIFY.sh。

set -uo pipefail

CODE=${MATFDM_CODE:?}
MANIFEST=${MATFDM_VERIFY_MANIFEST:?}
VROOT=${MATFDM_VERIFY_ROOT:?}
NNODES=${SLURM_JOB_NUM_NODES:-1}

module load python
module load matlab-mcr 2>/dev/null || true
export CALIB_PYTHON=${CALIB_PYTHON:-$(command -v python3)}
export MCR_ROOT=${MCR_ROOT:-/global/common/software/nersc9/matlab/MCR/R2023b}
export MATFDM_BUILD_DIR=${MATFDM_BUILD_DIR:-${MATFDM_BUILD:-$SCRATCH/matfdm_build}/CURRENT}
export MATFDM_BUILD_COMMIT=$(cat "$MATFDM_BUILD_DIR/BUILD_COMMIT" 2>/dev/null || echo unknown)
export MCR_CACHE_ROOT=/tmp/$USER/mcr.${SLURM_JOB_ID:-local}

echo "================================================================"
echo "job     : ${SLURM_JOB_ID:-local}   nodes: $NNODES"
echo "清单    : $MANIFEST ($(grep -c . "$MANIFEST") 条任务)"
echo "输出    : $VROOT"
echo "build   : $MATFDM_BUILD_COMMIT"
echo "氧化    : ${MATFDM_VERIFY_HOURS:-1500} h / ${MATFDM_VERIFY_NCKPT:-150} 采样点"
echo "start   : $(date)"
echo "================================================================"

srun --nodes="$NNODES" --ntasks="$NNODES" --ntasks-per-node=1 \
     -c 128 --cpu-bind=none --kill-on-bad-exit=0 --wait=0 \
     bash "$CODE/calibration/ctl/verify_node.sh" "$MANIFEST"

echo "================================================================"
echo "job ${SLURM_JOB_ID:-local} 结束 $(date)"
n=$(ls "$VROOT"/*/decouple/*/dose*/fields_timeseries.mat 2>/dev/null | wc -l)
echo "已完成 $n / $(grep -c . "$MANIFEST") 条"
echo
echo "算前沿与实验的对照:"
echo "  python3 $CODE/calibration/ctl/verify_fronts.py --root $VROOT"
