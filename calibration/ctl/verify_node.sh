#!/usr/bin/env bash
# 验证作业里每个节点干的事: 从清单里领属于自己的那一段, 并发跑 matfdm_run verify。
#
# 由 verify_job.sh 通过 srun 拉起, 每节点一个 task。
# 入参: $1 = 清单 (TSV: run \t case_tag \t dose \t mult逗号分隔)
#
# 分派: 第 k 个节点取清单里 (行号-1) % NNODES == k 的行 —— 轮转分配, 让不同
# 运行/剂量的任务摊到各节点, 而不是整块连续切 (那样慢的剂量会全压在一个节点上)。

set -uo pipefail

MANIFEST=${1:?"用法: verify_node.sh <清单>"}
RANK=${SLURM_PROCID:-0}
NNODES=${SLURM_NNODES:-${SLURM_JOB_NUM_NODES:-1}}
CODE=${MATFDM_CODE:?}
VROOT=${MATFDM_VERIFY_ROOT:?}
HOURS=${MATFDM_VERIFY_HOURS:-1500}
NCKPT=${MATFDM_VERIFY_NCKPT:-150}
CONC=${MATFDM_VERIFY_CONC:-110}          # 本节点同时跑几条

LOG="$VROOT/node-${SLURM_JOB_ID:-local}-r${RANK}.log"
mkdir -p "$VROOT"

{
echo "=== rank $RANK / $NNODES  node $(hostname)  $(date)"
echo "=== 清单 $MANIFEST   氧化 ${HOURS} h / ${NCKPT} 点   并发上限 $CONC"

mine=$(awk -v r="$RANK" -v n="$NNODES" 'NR % n == r % n' "$MANIFEST")
total=$(echo "$mine" | grep -c . || echo 0)
echo "=== 本节点领到 $total 条"
[[ "$total" == 0 ]] && exit 0

done_n=0
declare -A PIDS
while IFS=$'\t' read -r run tag dose mult; do
  [[ -n "$run" ]] || continue
  # 每个 (运行, case) 一个独立数据根, 免得不同 ft 的同名 case 撞目录
  rd="$VROOT/$run"
  mkdir -p "$rd/calibration"
  [[ -f "$rd/config.json" ]] || cp "${MATFDM_RUNS:?}/$run/config.json" "$rd/" 2>/dev/null

  while (( ${#PIDS[@]} >= CONC )); do
    for p in "${!PIDS[@]}"; do
      kill -0 "$p" 2>/dev/null || { unset 'PIDS[$p]'; done_n=$((done_n+1)); }
    done
    sleep 5
  done

  bash "$CODE/calibration/ctl/matfdm_mcr.sh" verify "$rd" "$tag" "$dose" "$mult" \
       "$HOURS" "$NCKPT" > "$rd/verify_${tag}_dose${dose}.out" 2>&1 &
  PIDS[$!]="$run/$tag/$dose"
done <<< "$mine"

echo "=== 全部撒出, 等回收"
wait
echo "=== rank $RANK 结束 $(date)"
} >> "$LOG" 2>&1

exit 0
