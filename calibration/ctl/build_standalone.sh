#!/usr/bin/env bash
# 把物理内核编译成 MATLAB Runtime standalone —— 编译一次, 之后调参不用再编。
#
# 为什么要编译: NERSC 全校只有 16 个 MATLAB / 4 个 PCT 席位, 文档明确要求
# 多节点作业跑编译版 (docs.nersc.gov/applications/matlab)。MCR 不连 license
# server, 编译之后整套流程占用 0 席位。
#
# 编译本身要签一个 MATLAB + 一个 Compiler 席位, 几分钟, 一次性。
# **必须在计算节点上编**, 不要在 login 节点 (NERSC 文档: 无图形环境下 mcc
# 在命令行直接跑可能 segfault; 而且 login 节点不该干重活)。
#
# 用法 (先 salloc 一个交互节点):
#   bash calibration/ctl/build_standalone.sh              # 编到 $SCRATCH/matfdm_build/<commit>
#   bash calibration/ctl/build_standalone.sh /path/to/out # 指定输出目录
#
# 产物:
#   <out>/matfdm_run          standalone 可执行
#   <out>/run_matfdm_run.sh   MathWorks 生成的启动脚本 (设好 LD_LIBRARY_PATH)
#   <out>/BUILD_COMMIT        编译时的 git commit
#   <out>/baseline.json       十个基线值快照 (后处理用它, 不再正则读源码)
#   <out>/CURRENT             软链, 指向最近一次成功的构建

set -euo pipefail

CODE=${MATFDM_CODE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
COMMIT=$(git -C "$CODE" rev-parse --short HEAD 2>/dev/null || echo nogit)
DIRTY=$(git -C "$CODE" status --porcelain 2>/dev/null | head -1)
[[ -n "$DIRTY" ]] && COMMIT="${COMMIT}-dirty"
OUT=${1:-${MATFDM_BUILD:-$SCRATCH/matfdm_build}/$COMMIT}

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  echo "!! 不在计算节点上。先 salloc, 或者用:" >&2
  echo "   srun --jobid=<交互作业号> -N1 -n1 --overlap bash $0 $*" >&2
  exit 1
fi

module load matlab

echo "=========================================================="
echo " 代码   : $CODE"
echo " commit : $COMMIT"
echo " 输出   : $OUT"
echo " 节点   : $(hostname)"
echo "=========================================================="
[[ -n "$DIRTY" ]] && echo "注意: 工作区有未提交改动, commit 打了 -dirty 后缀"

mkdir -p "$OUT"
# mcc 不会覆盖已存在的可执行, 重编前先把上一次的产物清掉
rm -f "$OUT"/matfdm_run "$OUT"/run_matfdm_run.sh "$OUT"/*.ctf \
      "$OUT"/readme.txt "$OUT"/mccExcludedFiles.log \
      "$OUT"/requiredMCRProducts.txt "$OUT"/unresolvedSymbols.txt 2>/dev/null || true
echo "$COMMIT" > "$OUT/BUILD_COMMIT"

# mcc 从 matlab -batch 里调, 不在 shell 直接跑 —— NERSC 文档提到无图形时
# 命令行 mcc 可能 segfault。
#   -m                独立可执行
#   -R -nodisplay     运行时不开图形
#   -R -singleCompThread  每个进程单线程 (一个节点上要并排跑 120 个)
cd "$CODE"
MCC_CMD="mcc('-m','calibration/ctl/matfdm_run.m','-o','matfdm_run','-d','$OUT'"
MCC_CMD="$MCC_CMD,'-R','-nodisplay','-R','-singleCompThread'"
MCC_CMD="$MCC_CMD,'-v'); disp('MCC_DONE');"
matlab -nodisplay -nosplash -batch "$MCC_CMD"

[[ -x "$OUT/matfdm_run" ]] || { echo "!! 没生成 $OUT/matfdm_run" >&2; exit 1; }

# 基线快照: 用刚编出来的二进制自己导, 保证和它跑的是同一份基线
module load matlab-mcr 2>/dev/null || true
MCR=${MCR_ROOT:-/global/common/software/nersc9/matlab/MCR/R2023b}
export MCR_CACHE_ROOT=${MCR_CACHE_ROOT:-/tmp/$USER/mcr_build.$$}
mkdir -p "$MCR_CACHE_ROOT"
MATFDM_BUILD_COMMIT="$COMMIT" MATFDM_BUILD_DIR="$OUT" \
  "$OUT/run_matfdm_run.sh" "$MCR" baseline "$OUT/baseline.json" || {
  echo "!! 基线导出失败 (二进制本身可能有问题)" >&2; exit 1; }

ln -sfn "$OUT" "$(dirname "$OUT")/CURRENT"

echo
echo "=========================================================="
echo " 编译完成"
echo "   $OUT/matfdm_run"
echo "   $(dirname "$OUT")/CURRENT -> $COMMIT"
echo " 基线快照:"; sed -n '1,14p' "$OUT/baseline.json"
echo "=========================================================="
