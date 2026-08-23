#!/usr/bin/env bash
# ============================================================================
#  提交入口 —— 改下面的设置区, 然后:  bash calibration/ctl/JOB.sh
#  它会: 建运行目录 -> 写 config.json -> 生成清单 -> 提交多节点作业(带接力链)
# ============================================================================

# ------------------------------ 设置区 --------------------------------------
ACCOUNT=m5181                       # SLURM 账号
WALLTIME=08:00:00
NJOBS=20
QOS=regular                         # regular / debug / preempt

CODE=$SCRATCH/projects/matfdm       # 代码目录 (只读)
RUNS=$SCRATCH/matfdm_runs           # 数据根

# --- 扫描: 每个值一个运行, 一个运行占一个节点 ---
SWEEP_KEY=front_thick               # 要扫的字段 (overrides.xxx 可扫物理参数)
SWEEP_VALUES="0.1 0.2 0.3 0.4 0.5 \
              0.6 0.7 0.8 0.9 1.0"
PREFIX=ft                           # 运行目录名前缀 -> ft1e-1, ft5e-1, ft1e0 ...

# --- 所有运行共用的标定设置 ---
POPULATION=40                       # 每代 case 数
WORKERS=120                         # parpool worker 数 (= POPULATION × 剂量数)
DOSES="[0, 0.5, 3]"                 # 剂量点
TARGETS="[40, 60, 100]"             # 对应靶深度 nm
MIDDLE_MAX=70                       # 0.5 dpa 软带上限 nm
ENDPOINT_BAND=5                     # 端点硬约束 nm (超出判不可行)
ENDPOINT_TOL=3                      # 成功判据端点容差 nm
MAX_ATTEMPTS=3                      # 腿失败几次熔断该 case
KEEP_TRAJ=false                     # 是否存 *_timeseries.mat (每腿 ~7 MB)
SEED=20260804                       # CMA 种子

# --- 物理参数覆盖 (盖在 build_p_decouple 之上, 不用改源码) ---
OVERRIDES='{"eff": 0.2}'            # 例: {"eff":0.2, "Dgb":1e-3, "rOM":0.2529}

# --- MATLAB license 席位 (NERSC 全校共享) ---
# 抢不到不会放弃, 一路退避重试到**墙钟前 5 分钟**为止 —— 什么时候收手只由
# WALLTIME 决定, 下面几个参数都不是放弃时限。
LIC_SEATS=2                         # 同时允许几个节点在"试签出" (0 = 不设闸)
LIC_BACKOFF=30                      # 抢不到的退避基数 s (指数增长 + 随机抖动)
LIC_BACKOFF_MAX=600                 # 退避上限 s (8h 作业里一个节点大约重试 50-90 次)
LIC_HOLD=420                        # 入闸令牌最长持有 s —— 不是放弃时限! 只用来回收
                                    # 被 SIGKILL 的节点遗留的令牌, 免得把闸堵死;
                                    # 到点强收令牌时, 该节点的 MATLAB 照常跑
# ----------------------------------------------------------------------------

set -euo pipefail
export MATFDM_CODE="$CODE" MATFDM_RUNS="$RUNS" MATFDM_ACCOUNT="$ACCOUNT" \
       MATFDM_WALLTIME="$WALLTIME"
export MATFDM_LIC_SEATS="$LIC_SEATS" MATFDM_LIC_BACKOFF="$LIC_BACKOFF" \
       MATFDM_LIC_BACKOFF_MAX="$LIC_BACKOFF_MAX" MATFDM_LIC_HOLD="$LIC_HOLD"
MF="bash $CODE/calibration/ctl/matfdm.sh"
MANIFEST="$RUNS/runs_${PREFIX}.txt"

echo "=========================================================="
echo " 扫描      : $SWEEP_KEY = $(echo $SWEEP_VALUES | tr -s ' ')"
echo " 运行前缀  : $PREFIX      数据根: $RUNS"
echo " 每代       : $POPULATION cases × $(echo "$DOSES" | tr -cd ',' | wc -c | awk '{print $1+1}') doses = $WORKERS legs"
echo " 作业       : $NJOBS 轮 × $WALLTIME, 账号 $ACCOUNT, QOS $QOS"
echo " 覆盖       : $OVERRIDES"
echo " license   : 入闸 $LIC_SEATS 席, 抢不到退避 ${LIC_BACKOFF}-${LIC_BACKOFF_MAX}s 重试到墙钟"
echo "=========================================================="

# 1) 算运行名 + 建目录 + 写 config.json
#    运行名统一走 run_id.py 的科学计数法: 0.1 -> ft1e-1, 1.0 -> ft1e0, 10 -> ft1e1。
#    双射且永不撞名, 小数位数随便加。顺带查已存在目录里记的值对不对得上。
#    (老做法直接 tr -d '.': 1.0 和 10 都得 ft10, 两条链混一个目录, 悄无声息全废)
IDS=$($MF runid "$PREFIX" --key "$SWEEP_KEY" $SWEEP_VALUES) || {
  echo "扫描值有问题, 没提交任何作业"; exit 1; }

while read -r id v; do
  [[ -n "$id" ]] || continue
  $MF new "$id" \
      "$SWEEP_KEY=$v" \
      "population=$POPULATION" "workers=$WORKERS" \
      "doses=$DOSES" "targets=$TARGETS" \
      "middle_max=$MIDDLE_MAX" "endpoint_band=$ENDPOINT_BAND" \
      "endpoint_tol=$ENDPOINT_TOL" "max_attempts=$MAX_ATTEMPTS" \
      "keep_traj=$KEEP_TRAJ" "seed=$SEED" \
      "overrides=$OVERRIDES" > /dev/null
  echo "  [run] $id  ($SWEEP_KEY=$v)"
done <<< "$IDS"

# 2) 清单: 每行一个运行目录, 第 k 行给第 k 个节点
$MF list "${PREFIX}*" > "$MANIFEST"
N=$(grep -c . "$MANIFEST")
echo "清单 $MANIFEST -> $N 个运行 = $N 个节点/作业"

# 3) 提交: 一个作业占 N 节点, NJOBS 轮 afterany 接力
dep=""
for ((i=0;i<NJOBS;i++)); do
  jid=$(sbatch --parsable -N "$N" -t "$WALLTIME" -A "$ACCOUNT" -q "$QOS" \
        -C cpu -J "mn_${PREFIX}" -o "$RUNS/mn_${PREFIX}-%j.out" \
        ${dep:+--dependency=afterany:$dep} \
        --export=ALL,MATFDM_CODE="$CODE",MATFDM_MANIFEST="$MANIFEST",\
MATFDM_RUNS="$RUNS",MATFDM_LIC_SEATS="$LIC_SEATS",MATFDM_LIC_BACKOFF="$LIC_BACKOFF",\
MATFDM_LIC_BACKOFF_MAX="$LIC_BACKOFF_MAX",MATFDM_LIC_HOLD="$LIC_HOLD" \
        "$CODE/calibration/ctl/multi_node.sh")
  echo "  作业 $jid  (${N} 节点, ${WALLTIME})${dep:+  等 $dep}"
  dep=$jid
done

echo
squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R"
echo
echo "看进度:  bash $CODE/calibration/ctl/matfdm.sh status"
echo "看某节点: tail -f $RUNS/${PREFIX}*/node-*.log"
echo "全停:     touch $RUNS/${PREFIX}*/calibration/STOP"
echo "导前十名: bash $CODE/calibration/ctl/matfdm.sh export '${PREFIX}*'"
