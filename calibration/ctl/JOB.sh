#!/usr/bin/env bash
# ============================================================================
#  提交入口 —— 改下面的设置区, 然后:  bash calibration/ctl/JOB.sh
#  它会: 建运行目录 -> 写 config.json -> 生成清单 -> 提交多节点作业(带接力链)
# ============================================================================

# ------------------------------ 设置区 --------------------------------------
ACCOUNT=m5181                       # SLURM 账号
WALLTIME=12:00:00
NJOBS=20
QOS=regular                         # regular / debug / preempt

CODE=$SCRATCH/projects/matfdm       # 代码目录 (只读)
RUNS=$SCRATCH/matfdm_runs           # 数据根

# --- 扫描: 每个值一个运行, 一个运行占一个节点 ---
SWEEP_KEY=front_thick               # 要扫的字段 (overrides.xxx 可扫物理参数)
SWEEP_VALUES="0.0001 0.001 0.005 0.01 0.02 0.05 0.1 0.2 0.3 0.4 0.5 \
              0.6 0.7 0.8 0.9 1.0"
PREFIX=ft                           # 运行目录名前缀 -> ft1e-1, ft5e-1, ft1e0 ...

# --- 所有运行共用的标定设置 ---
POPULATION=40                       # 每代 case 数
WORKERS=120                         # parpool worker 数 (= POPULATION × 剂量数)
DOSES="[0, 0.5, 3]"                 # 剂量点
TARGETS="[40, 60, 100]"             # 对应靶深度 nm

# --- 成分标定: 实验测得的 GB 氧化物 at%, 与前沿位置共同作为标定指标 ---
# 靶值由 comp_targets.py 从 Composition_Dose.csv 现算, 改实验数据只改那个 csv。
# 口径 = Cr+Fe+Ni (模型不产 Ni, 所以成分残差有 0.9~3.9% 的地板, 详见该脚本说明)。
COMPOSITION_BASIS=crfeni            # crfeni / crfe
COMPOSITION_TOL=5                   # 命中容差 at% (每个剂量的 Cr 和 Fe 都要落在带内)
COMPOSITION_SCALE=3                 # 成分残差标尺 at%: 越小权重越高。前沿端点是 /3,
                                    # 所以 3 = 成分与前沿端点等权; 5 = 成分只有 0.6 倍。
# 成分取样位置: 取该剂量算出的前沿 x 这个比例。比例来自实验本身
# (23/40, 30/60, 44/100) —— 模型打中靶前沿时就等于实验的取样深度。
# 用相对而不是绝对深度: 模型前沿在几十纳米范围内浮动, 固定深度在浅前沿的样本上是
# 氧化层中段、在深前沿的样本上就成了表层, 取的不是同一个结构位置。
COMPOSITION_FRAC="[0.575, 0.5, 0.44]"
COMPOSITION_DEPTH="[23, 30, 44]"    # 绝对深度 nm, 仅在 FRAC 置空时启用
MIDDLE_MAX=70                       # 0.5 dpa 软带上限 nm
ENDPOINT_BAND=5                     # 端点硬约束 nm (超出判不可行)
ENDPOINT_TOL=3                      # 成功判据端点容差 nm
MAX_ATTEMPTS=3                      # 腿失败几次熔断该 case
LEG_TIMEOUT=25200                   # 单腿累计计算时限 s (0=不限)。超时即判这组乘子
                                    # 不收敛, 整个 case 丢弃 —— 腿慢本身就是走到了
                                    # 刚性区域的信号, 磨下去只会拖住整代。
                                    # 跨作业累加: 被墙钟打断后续算, 时间接着记。
                                    # 2026-09-02 实测 (dx=0.3, num_ckpt=200, 120 条满载):
                                    #   第 1 窗 182 s (含 MCR 启动+辐照段), 后续 63 s/窗,
                                    #   200 窗 = 3.53 h。取 2 倍余量 -> 7 h。
                                    # 改 dx / num_ckpt / 网格后必须重测: 时限设小了,
                                    # 整代好样本会被判成"不收敛"全部丢弃。
KEEP_TRAJ=false                     # 是否存 *_timeseries.mat (每腿 ~7 MB)
SEED=20260804                       # CMA 种子

# --- 物理参数覆盖 (盖在 build_p_decouple 之上, 不用改源码) ---
OVERRIDES='{"eff": 0.2}'            # 例: {"eff":0.2, "Dgb":1e-3, "rOM":0.2529}

# --- 引擎 ---
# mcr    默认。跑编译好的 standalone, 占用 0 个 MATLAB / 0 个 PCT 席位。
#        NERSC 全校只有 16 个 MATLAB / 4 个 PCT, 文档要求多节点作业用编译版。
#        改了 .m 源码要先在计算节点跑 build_standalone.sh。
# matlab 回退路线, 老的 parpool 版, 要抢 license, 只在调试时用。
ENGINE=mcr
BUILD_DIR=${MATFDM_BUILD:-$SCRATCH/matfdm_build}/CURRENT

# --- 以下几个只有 ENGINE=matlab 的回退路线才用得上 ---
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
export MATFDM_ENGINE="$ENGINE" MATFDM_BUILD_DIR="$BUILD_DIR"

# 编译产物必须先有 —— 排了 20 轮作业才发现没编, 白等一整天
if [[ "$ENGINE" == mcr ]]; then
  [[ -x "$BUILD_DIR/run_matfdm_run.sh" ]] || {
    echo "没有编译产物: $BUILD_DIR"
    echo "先在计算节点上编 (不要在 login 节点):"
    echo "  salloc -N 1 -q interactive -C cpu -t 00:30:00 -A $ACCOUNT"
    echo "  bash $CODE/calibration/ctl/build_standalone.sh"
    exit 1; }
  BUILD_COMMIT=$(cat "$BUILD_DIR/BUILD_COMMIT" 2>/dev/null || echo unknown)
  HEAD_COMMIT=$(git -C "$CODE" rev-parse --short HEAD 2>/dev/null || echo nogit)
  [[ "$BUILD_COMMIT" == "$HEAD_COMMIT"* ]] || \
    echo "注意: 编译产物是 $BUILD_COMMIT, 当前代码是 $HEAD_COMMIT —— 改过 .m 就要重编"
fi
MF="bash $CODE/calibration/ctl/matfdm.sh"
MANIFEST="$RUNS/runs_${PREFIX}.txt"

# 成分靶值: 从实验 csv 现算, 写进每个运行的 config.json (provenance 也就记下了)
COMPOSITION_TARGETS=$(module load python >/dev/null 2>&1; \
  python3 "$CODE/calibration/ctl/comp_targets.py" --basis "$COMPOSITION_BASIS" --json) || {
  echo "成分靶值算不出来 (Composition_Dose.csv 在吗?), 没提交任何作业"; exit 1; }

echo "=========================================================="
echo " 扫描      : $SWEEP_KEY = $(echo $SWEEP_VALUES | tr -s ' ')"
echo " 运行前缀  : $PREFIX      数据根: $RUNS"
echo " 每代       : $POPULATION cases × $(echo "$DOSES" | tr -cd ',' | wc -c | awk '{print $1+1}') doses = $WORKERS legs"
echo " 作业       : $NJOBS 轮 × $WALLTIME, 账号 $ACCOUNT, QOS $QOS"
echo " 覆盖       : $OVERRIDES"
echo " 成分靶值   : $COMPOSITION_TARGETS  (口径 $COMPOSITION_BASIS, 容差 ±$COMPOSITION_TOL at%)"
echo " 成分权重   : 标尺 /$COMPOSITION_SCALE at% (前沿端点是 /3, 相等即等权)"
echo " 取样位置   : 前沿 x $COMPOSITION_FRAC (相对口径, 来自实验 23/40,30/60,44/100)"
echo " 单腿时限   : $(( LEG_TIMEOUT / 60 )) min 累计 (超时判不收敛, 丢弃整个 case)"
if [[ "$ENGINE" == mcr ]]; then
  echo " 引擎       : MCR standalone (0 个 license 席位)  $BUILD_DIR"
else
  echo " 引擎       : matlab 回退路线, 入闸 $LIC_SEATS 席, 退避重试到墙钟"
fi
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
      "composition_targets=$COMPOSITION_TARGETS" \
      "composition_tol=$COMPOSITION_TOL" "composition_scale=$COMPOSITION_SCALE" \
      "composition_depth_frac=$COMPOSITION_FRAC" \
      "composition_depth=$COMPOSITION_DEPTH" \
      "leg_timeout=$LEG_TIMEOUT" \
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
MATFDM_RUNS="$RUNS",MATFDM_ENGINE="$ENGINE",MATFDM_BUILD_DIR="$BUILD_DIR",\
MATFDM_LIC_SEATS="$LIC_SEATS",MATFDM_LIC_BACKOFF="$LIC_BACKOFF",\
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
