#!/usr/bin/env bash
# 从 NERSC 取回标定结果 —— 在你自己的 Mac 上跑。
#
#   1. 按当天日期新建目标目录  <dest>/YYYYMMDD/
#   2. scp 回 postprocess 的 ft*.txt 参数表
#   3. 读参数表里每个运行的前 N 名, 把这些 case 的结果目录也 scp 回来
#
# 用法:
#   bash fetch_results.sh
#   bash fetch_results.sh --top 20
#   bash fetch_results.sh --date 20260831
#   bash fetch_results.sh --dest "/Volumes/WZ_T9/RISconti/NERSC calibration"

set -euo pipefail

REMOTE=${MATFDM_REMOTE:-wzhuo001@perlmutter.nersc.gov}
RUNS=${MATFDM_REMOTE_RUNS:-/pscratch/sd/w/wzhuo001/matfdm_runs}
DEST="/Volumes/WZ_T9/RISconti/NERSC calibration"
DATE=$(date +%Y%m%d)
TOP=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)   DEST=$2; shift 2;;
    --date)   DATE=$2; shift 2;;
    --top)    TOP=$2;  shift 2;;
    --remote) REMOTE=$2; shift 2;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) echo "未知选项: $1" >&2; exit 2;;
  esac
done

OUT="$DEST/$DATE"
echo "远端: $REMOTE:$RUNS"
echo "本地: $OUT"
echo "取前 $TOP 名"
echo

mkdir -p "$OUT"

# ---- 1. 参数表 ----
echo "[1/2] 取参数表 postprocess/"
scp -r "$REMOTE:$RUNS/postprocess" "$OUT/"

# ---- 2. 前 N 名的结果 ----
echo
echo "[2/2] 取前 $TOP 名的结果文件"
for txt in "$OUT"/postprocess/*.txt; do
  [[ -e "$txt" ]] || continue
  run=$(basename "$txt" .txt)

  # 名次行形如:  "#1  b04_c06_cma   fitness=..."
  tags=$(grep -E '^#[0-9]+[[:space:]]' "$txt" | head -n "$TOP" | awk '{print $2}')
  n=$(echo "$tags" | grep -c . || true)
  if [[ "$n" == 0 ]]; then
    echo "  $run: 参数表里没有名次行, 跳过"
    continue
  fi
  echo "  $run: $n 个 case"

  mkdir -p "$OUT/$run/decouple" "$OUT/$run/calibration/metrics"

  # 运行的配置与出处
  scp "$REMOTE:$RUNS/$run/config.json" "$REMOTE:$RUNS/$run/provenance.txt" \
      "$OUT/$run/" 2>/dev/null || true

  # 花括号展开由远端 shell 做, 一个运行一次 scp
  list=$(echo "$tags" | paste -sd, -)
  scp -r "$REMOTE:$RUNS/$run/decouple/{$list}"              "$OUT/$run/decouple/"
  scp    "$REMOTE:$RUNS/$run/calibration/metrics/{$list}.csv" \
         "$OUT/$run/calibration/metrics/" 2>/dev/null || true
done

echo
echo "完成 -> $OUT"
du -sh "$OUT" 2>/dev/null | sed 's/^/  /'
