#!/usr/bin/env bash
# ============================================================================
#  验证提交入口 —— 改下面的设置区, 然后:  bash calibration/ctl/VERIFY.sh
#  它会: 从每个 ft 的排名表取前 N 名 -> 展开成任务清单 -> 规划节点 -> 提交
# ============================================================================

# ------------------------------ 设置区 --------------------------------------
ACCOUNT=m5181
WALLTIME=12:00:00                   # 1500 h 氧化比标定的 500 h 长约 3 倍
NJOBS=4                             # 接力轮数 (断点续算)
QOS=regular

CODE=$SCRATCH/projects/matfdm
RUNS=$SCRATCH/matfdm_runs           # 标定数据根 (排名表和乘子从这里读)
VROOT=$SCRATCH/matfdm_verify        # 验证数据根

TOP=10                              # 每个 ft 取前几名
DOSES=0.5,1.5                       # 要跑的剂量 (要有对应的实验 csv)
OXI_HOURS=1500                      # 氧化时长 h
NUM_CKPT=150                        # 采样点数 (= 前沿-时间曲线的点数)
PER_NODE=110                        # 每节点并发几条 (128 物理核, 留余量)
# ----------------------------------------------------------------------------

set -euo pipefail
export MATFDM_CODE="$CODE" MATFDM_RUNS="$RUNS"
PY() { module load python >/dev/null 2>&1 || true; python3 "$@"; }

BUILD=${MATFDM_BUILD:-$SCRATCH/matfdm_build}/CURRENT
[[ -x "$BUILD/run_matfdm_run.sh" ]] || {
  echo "没有编译产物 $BUILD —— 先在计算节点跑 build_standalone.sh"; exit 1; }

mkdir -p "$VROOT"
MANIFEST="$VROOT/tasks.tsv"

echo "=========================================================="
echo " 标定数据 : $RUNS"
echo " 验证输出 : $VROOT"
echo " 取前     : $TOP 名 x 剂量 $DOSES"
echo " 氧化     : $OXI_HOURS h / $NUM_CKPT 采样点"
echo " 产物     : $(cat "$BUILD/BUILD_COMMIT" 2>/dev/null || echo ?)"
echo "=========================================================="

# 1) 展开任务 + 规划节点
PLAN=$(PY "$CODE/calibration/ctl/verify_plan.py" --runs "$RUNS" --top "$TOP" \
          --doses "$DOSES" --per-node "$PER_NODE" --out "$MANIFEST")
echo "$PLAN"
N=$(grep -c . "$MANIFEST")
NODES=$(( (N + PER_NODE - 1) / PER_NODE ))
CONC=$(( (N + NODES - 1) / NODES ))
echo

# 2) 提交接力链
dep=""
for ((i=0;i<NJOBS;i++)); do
  jid=$(sbatch --parsable -N "$NODES" -t "$WALLTIME" -A "$ACCOUNT" -q "$QOS" \
        -C cpu -J verify_ft -o "$VROOT/verify-%j.out" \
        ${dep:+--dependency=afterany:$dep} \
        --export=ALL,MATFDM_CODE="$CODE",MATFDM_RUNS="$RUNS",\
MATFDM_VERIFY_ROOT="$VROOT",MATFDM_VERIFY_MANIFEST="$MANIFEST",\
MATFDM_VERIFY_HOURS="$OXI_HOURS",MATFDM_VERIFY_NCKPT="$NUM_CKPT",\
MATFDM_VERIFY_CONC="$CONC",MATFDM_BUILD_DIR="$BUILD" \
        "$CODE/calibration/ctl/verify_job.sh")
  echo "  作业 $jid  ($NODES 节点, $WALLTIME)${dep:+  等 $dep}"
  dep=$jid
done

echo
squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R" | head -8
echo
echo "看进度: tail -f $VROOT/node-*.log"
echo "出图表: python3 $CODE/calibration/ctl/verify_fronts.py --root $VROOT"
