#!/bin/bash
#SBATCH -A          m0000            # <<< 改成你的项目号
#SBATCH -C          cpu
#SBATCH -q          regular
#SBATCH -N          1
#SBATCH -t          48:00:00
#SBATCH -J          matfdm_cal
#SBATCH --dependency=singleton       # 同名作业串行: 同一份脚本可以一次交多份, 自动排队
#SBATCH --output=%x-%j.out
#SBATCH --open-mode=append
#
# 一个作业 = 一个常驻 MATLAB + 一个 parpool, 能跑多远跑多远。
# 代码侧不设任何时限: 墙钟到点由 SLURM 直接杀, 最多损失当前那个 checkpoint 窗口
# (每腿 50 窗, 原子 tmp+rename 写盘)。脚本自己不排下一个作业。
#
# 提交模型: 同一份脚本可以反复提交, 甚至一次连交几份 ——
#   singleton 保证同时只有一个在跑, 后面的排队等前一个结束再自动接上。
#   每个作业启动时:
#     CMA-ES      从 optimizer/cma_state.pkl 续 (丢了也能从 metrics 重放全部历史)
#     未完成的腿  从各自 checkpoint 续
#     已完成的腿  幂等守卫直接跳过
#     命中/停止   见到 DONE 或 STOP 就空转退出, 队列里多余的作业自己退休
#
# 用法:
#   sbatch calibration/nersc/submit.sh                 # 交一个
#   for i in 1 2 3 4; do sbatch calibration/nersc/submit.sh; done   # 一次排四个
# 停止:
#   touch $CALIB_REPO_DIR/calibration/STOP             # 队列里没跑的都会空转退出

set -euo pipefail

export CALIB_REPO_DIR=${CALIB_REPO_DIR:-$SCRATCH/matfdmcali}
export CALIB_POPULATION=${CALIB_POPULATION:-30}     # 每代 case 数
export CALIB_WORKERS=${CALIB_WORKERS:-90}           # = POPULATION * 3
export CALIB_ENDPOINT_TOL=${CALIB_ENDPOINT_TOL:-3}  # 成功判据端点容差 nm
export CALIB_ENABLE_PLOTS=0                         # 不出图
export CALIB_KEEP_TRAJ=0                            # 不存 *_timeseries.mat (省 scratch)
export CALIB_MAX_ATTEMPTS=${CALIB_MAX_ATTEMPTS:-3}  # 腿连续失败几次后熔断该 case
# 故意不设 CALIB_WALL_BUDGET / CALIB_GEN_RESERVE => 驱动与腿都不自我限时

cd "$CALIB_REPO_DIR"
mkdir -p calibration/logs

# ---- 哨兵: 命中或人工停止 -> 本作业空转退出 (排队中的多余作业自动退休) ----
if [[ -e calibration/DONE ]]; then
  echo "标定已命中 ($(cat calibration/DONE)), 本作业退出"; exit 0
fi
if [[ -e calibration/STOP ]]; then
  echo "STOP 存在, 本作业退出"; exit 0
fi

module load matlab
echo "=== job ${SLURM_JOB_ID:-local} start $(date)  workers=$CALIB_WORKERS  (代码侧无时限)"
python3 calibration/nersc/gen_tool.py history 0 2>/dev/null || true   # 续跑摘要

srun -n 1 -c 128 --cpu-bind=none \
  matlab -nodisplay -nosplash -batch \
  "addpath('$CALIB_REPO_DIR/calibration/nersc'); run_generation"

echo "=== job ${SLURM_JOB_ID:-local} matlab exit $(date)"
if [[ -e calibration/DONE ]]; then
  echo "标定命中: $(cat calibration/DONE)"
else
  echo "未命中: 再 sbatch 同一份脚本即可接着优化 (或提前排好几个)"
fi
