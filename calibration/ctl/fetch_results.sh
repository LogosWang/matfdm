#!/usr/bin/env bash
# 从 NERSC 取回标定结果 —— 在你自己的 Mac 上跑。
#
#   1. 按当天日期新建目标目录  <dest>/YYYYMMDD/
#   2. 取回 postprocess 的 ft*.txt 参数表
#   3. 读参数表里每个运行的前 N 名, 把这些 case 的结果目录也取回来
#
# 只认证一次: 开一个 SSH 主连接 (ControlMaster), 后面所有 scp 复用它。
# 不这样的话每个 scp 都要重输一遍 Password+OTP, 十几个运行就是几十遍。
#
# 用法:
#   ~/fetch_results.sh
#   ~/fetch_results.sh --top 20
#   ~/fetch_results.sh --date 20260831
#   ~/fetch_results.sh --dest "/Volumes/WZ_T9/RISconti/NERSC calibration"

set -uo pipefail

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
    -h|--help) sed -n '2,17p' "$0"; exit 0;;
    *) echo "未知选项: $1" >&2; exit 2;;
  esac
done

OUT="$DEST/$DATE"
echo "远端: $REMOTE:$RUNS"
echo "本地: $OUT"
echo "取前 $TOP 名"
echo

mkdir -p "$OUT" || exit 1

# ---- SSH 主连接: 只认证这一次 ----
CTL=/tmp/.matfdm-ssh-$$
cleanup() { ssh -S "$CTL" -O exit "$REMOTE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
echo "建立 SSH 主连接 (只需认证一次)..."
if ! ssh -M -S "$CTL" -o ControlPersist=30m -o ConnectTimeout=30 -fN "$REMOTE"; then
  echo "主连接建立失败" >&2; exit 1
fi
SSHOPT=(-o ControlPath="$CTL")
echo "已连上。"
echo

# ---- 1. 参数表 ----
echo "[1/2] 取参数表 postprocess/"
scp "${SSHOPT[@]}" -r "$REMOTE:$RUNS/postprocess" "$OUT/" || {
  echo "取参数表失败 —— 远端 $RUNS/postprocess 存在吗?" >&2; exit 1; }

# ---- 2. 前 N 名的结果 ----
echo
echo "[2/2] 取前 $TOP 名的结果"
total=0
for txt in "$OUT"/postprocess/*.txt; do
  [[ -e "$txt" ]] || continue
  run=$(basename "$txt" .txt)

  # 名次行形如:  "#1  b04_c06_cma   fitness=..."
  tags=$(grep -E '^#[0-9]+[[:space:]]' "$txt" | head -n "$TOP" | awk '{print $2}')
  [[ -n "$tags" ]] || { echo "  $run: 参数表里没有名次行, 跳过"; continue; }

  # 远端逐个确认目录在不在 —— 被惩罚判死的 case 有指标但没有结果目录,
  # 直接 scp 会整条命令报错退出。一次 ssh 问清楚, 只取真实存在的。
  have=$(ssh "${SSHOPT[@]}" "$REMOTE" "cd '$RUNS/$run/decouple' 2>/dev/null && ls -d $tags 2>/dev/null")
  n=$(echo "$have" | grep -c . || true)
  if [[ "$n" == 0 ]]; then
    echo "  $run: 前 $TOP 名在远端都没有结果目录 (可能都是被判死的), 跳过"
    continue
  fi

  mkdir -p "$OUT/$run/decouple" "$OUT/$run/calibration/metrics"

  # 每个 tag 一个独立参数 —— 不能用 {a,b,c}: 新版 scp 走 SFTP 协议,
  # 远端 shell 不会展开花括号, 会去找一个名叫 "{a,b,c}" 的目录。
  srcs=(); metrics=()
  while read -r t; do
    [[ -n "$t" ]] || continue
    srcs+=("$REMOTE:$RUNS/$run/decouple/$t")
    metrics+=("$REMOTE:$RUNS/$run/calibration/metrics/$t.csv")
  done <<< "$have"

  echo "  $run: $n 个 case"
  scp "${SSHOPT[@]}" -r "${srcs[@]}" "$OUT/$run/decouple/" \
    || echo "    !! decouple 传输有错" >&2
  scp "${SSHOPT[@]}" "${metrics[@]}" "$OUT/$run/calibration/metrics/" 2>/dev/null \
    || echo "    (部分 metrics 缺失, 跳过)"
  scp "${SSHOPT[@]}" "$REMOTE:$RUNS/$run/config.json" \
      "$REMOTE:$RUNS/$run/provenance.txt" "$OUT/$run/" 2>/dev/null || true
  total=$((total + n))
done

echo
echo "完成: $total 个 case -> $OUT"
du -sh "$OUT" 2>/dev/null | sed 's/^/  /'
