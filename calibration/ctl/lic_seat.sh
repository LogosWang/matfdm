#!/usr/bin/env bash
# MATLAB license 席位抢占 —— 被 node_task.sh source, 不单独执行。
#
# 为什么要这东西 (2026-08-23 的事故):
#   N 个节点在同一秒 matlab -batch, 一起冲 NERSC 全校共享的 license 服务器。
#   抢不到的节点当场 exit 1, 整个作业 2 分钟就"跑完"了, afterany 接力链于是
#   被瞬间烧光 —— 57318725..57318737 十三个作业 20 分钟全部空转结束。
#
# 做法, 两条:
#   1) 入闸令牌: 共享文件系统上最多 LIC_SEATS 个令牌, 同一时刻只允许这么多
#      节点处在"正在签出 license"的状态。令牌 = 一个目录, mkdir 是原子操作;
#      节点崩了令牌会在 LIC_HOLD 秒后被自动回收, 不会永久占死。
#   2) 签出成功立刻放闸: MATLAB 在 parcluster 成功后写 MATFDM_LIC_READY 标记,
#      node_task.sh 见到标记就交还令牌, 让下一个节点去抢。席位是"抢到就守住",
#      别人腾出席位的瞬间, 排队中的节点顶上 —— 这就是"动态抢席位"。
#
#   抢不到不退出: 指数退避 + 随机抖动重试, 一直试到作业墙钟快到为止。
#
# 环境变量 (都有默认值, multi_node.sh 会按作业情况传):
#   MATFDM_LIC_POOL         令牌池目录        默认 $MATFDM_RUNS/.lic_seats
#   MATFDM_LIC_SEATS        同时签出的节点数  默认 2
#   MATFDM_LIC_HOLD         令牌最长持有秒数  默认 420 —— 只管令牌, 不管重试:
#                           超时就认定持有者已死并回收令牌, 被收的那个节点的
#                           MATLAB 照常跑。放弃时刻是 GIVEUP (墙钟 - 5 min)。
#   MATFDM_LIC_WAIT         抢令牌的轮询基数  默认 20 s
#   MATFDM_LIC_BACKOFF      失败退避基数      默认 30 s
#   MATFDM_LIC_BACKOFF_MAX  失败退避上限      默认 600 s

LIC_POOL=${MATFDM_LIC_POOL:-${MATFDM_RUNS:-$SCRATCH/matfdm_runs}/.lic_seats}
LIC_SEATS=${MATFDM_LIC_SEATS:-2}
LIC_HOLD=${MATFDM_LIC_HOLD:-420}
LIC_WAIT=${MATFDM_LIC_WAIT:-20}
LIC_BACKOFF=${MATFDM_LIC_BACKOFF:-30}
LIC_BACKOFF_MAX=${MATFDM_LIC_BACKOFF_MAX:-600}
LIC_SEAT=""

# 令牌超时回收: 目录 mtime 即认领时刻, 超过 LIC_HOLD 说明持有者已经没了
lic_seat_reap() {
  local now d t
  now=$(date +%s)
  for d in "$LIC_POOL"/seat*; do
    [[ -d "$d" ]] || continue
    t=$(stat -c %Y "$d" 2>/dev/null) || continue
    if (( now - t > LIC_HOLD )); then
      rm -rf "$d" 2>/dev/null || true
    fi
  done
  return 0
}

# 阻塞抢一个入闸令牌; 成功把令牌路径放进 LIC_SEAT 并返回 0。
# $1 = 截止时刻 (epoch 秒), 到点还没抢到就返回 1。 $2 = 持有者描述 (进日志用)
lic_seat_acquire() {
  local deadline=$1 owner=${2:-$(hostname)} i
  (( LIC_SEATS <= 0 )) && { LIC_SEAT=""; return 0; }   # 0 = 关闭入闸, 直接放行
  mkdir -p "$LIC_POOL" 2>/dev/null || true
  while :; do
    lic_seat_reap
    for ((i = 0; i < LIC_SEATS; i++)); do
      if mkdir "$LIC_POOL/seat$i" 2>/dev/null; then
        printf '%s\n%s\n' "$owner" "$(date +%s)" > "$LIC_POOL/seat$i/owner" 2>/dev/null || true
        LIC_SEAT="$LIC_POOL/seat$i"
        return 0
      fi
    done
    (( $(date +%s) >= deadline )) && { LIC_SEAT=""; return 1; }
    sleep $(( LIC_WAIT + RANDOM % LIC_WAIT ))
  done
}

lic_seat_release() {
  [[ -n "$LIC_SEAT" ]] && rm -rf "$LIC_SEAT" 2>/dev/null
  LIC_SEAT=""
  return 0
}

# license 报错识别: 只要沾 license, 就当成"可以再试", 而不是当场判死
lic_is_license_failure() {
  grep -qEi 'License checkout failed|Licensing error|Maximum number of users|Unable to check out a license|License Manager Error' "$1" 2>/dev/null
}

# 第 n 次失败该睡多久: 指数退避 + equal jitter (半确定半随机)。
# 抖动是关键: 没有它, N 个节点会永远在同一秒一起重试, 等于没退避。
lic_backoff_seconds() {
  local n=$1 w=$LIC_BACKOFF i half
  for ((i = 1; i < n; i++)); do
    w=$(( w * 2 ))
    (( w >= LIC_BACKOFF_MAX )) && { w=$LIC_BACKOFF_MAX; break; }
  done
  half=$(( w / 2 ))
  echo $(( half + RANDOM % (half + 1) ))
}

# 可被 STOP 打断的睡眠: $1 = 秒数, $2 = STOP 文件路径
lic_sleep_until() {
  local left=$1 stop=${2:-} step
  while (( left > 0 )); do
    [[ -n "$stop" && -e "$stop" ]] && return 1
    step=$(( left > 30 ? 30 : left ))
    sleep "$step"
    left=$(( left - step ))
  done
  return 0
}

# ---------------------------------------------------------------------------
# 抢席位 + 跑 MATLAB 的完整循环 —— node_task.sh 与 single_node.sh 共用。
#   $1 代码目录  $2 运行目录  $3 STOP 文件  $4 放弃时刻(epoch)  $5 标签(进日志)
# 返回 MATLAB 的退出码 (从未跑成功则为最后一次的码)。
# 约定: MATLAB 侧 run_generation 在 parcluster 成功后写 $MATFDM_LIC_READY,
#       本函数见到该标记立刻放闸, 席位交给下一个排队的节点去抢。
# ---------------------------------------------------------------------------
lic_run_matlab() {
  local code=$1 run=$2 stopf=$3 giveup=$4 tag=${5:-r0}
  local hard_max=${MATFDM_HARD_RETRIES:-2}
  local ready="$run/calibration/.lic_ready.${SLURM_JOB_ID:-local}.${tag}"
  local try="$run/calibration/.matlab_try.${SLURM_JOB_ID:-local}.${tag}"
  local attempt=0 hard=0 rc=99 mlpid t0 w left

  export MATFDM_LIC_READY="$ready"
  rm -f "$ready" "$try" "$try.rc"

  while :; do
    if (( $(date +%s) >= giveup )); then
      echo "=== [$tag] 墙钟到点仍未抢到 license, 放弃 (共试 $attempt 次)  $(date)"; break
    fi
    [[ -e "$stopf" ]] && { echo "=== [$tag] STOP 出现, 停止抢席位"; break; }

    attempt=$((attempt + 1))

    # 入闸: 拿到令牌才允许去签出, 避免 N 个节点同时冲 license 服务器
    if ! lic_seat_acquire "$giveup" "$(hostname) $tag"; then
      echo "=== [$tag] 等入闸令牌等到墙钟到点, 放弃"; break
    fi
    echo "--- 第 $attempt 次尝试 $(date '+%F %T')  令牌=${LIC_SEAT:-<无闸>}"

    rm -f "$ready" "$try" "$try.rc"
    # tee: 留一份本次尝试的输出供 license 判定, 同时照旧实时流进节点日志
    # (tail -f node-*.log 不能因为加了重试就失效)
    { set +e                      # 管道里是子 shell; 关掉 -e 才拿得到 matlab 的真退出码
      matlab -nodisplay -nosplash -batch \
        "addpath('$code'); addpath('$code/calibration/ctl'); run_generation"
      echo $? > "$try.rc"; } 2>&1 | tee "$try" &
    mlpid=$!

    # 放闸: license 一到手 (READY 出现) 就交还令牌, 让下一个节点去抢
    t0=$(date +%s)
    while kill -0 "$mlpid" 2>/dev/null; do
      [[ -e "$ready" ]] && break
      (( $(date +%s) - t0 > LIC_HOLD - 60 )) && break
      sleep 5
    done
    [[ -e "$ready" ]] && echo "--- license 到手 (用时 $(( $(date +%s) - t0 )) s), 交还令牌"
    lic_seat_release

    wait "$mlpid" || true              # $! 是管道末端的 tee, matlab 退出它就退出
    rc=$(cat "$try.rc" 2>/dev/null || echo 99)

    if (( rc == 0 )); then
      echo "=== [$tag] matlab 正常结束  $(date)"; break
    fi

    if lic_is_license_failure "$try"; then
      w=$(lic_backoff_seconds "$attempt")
      left=$(( giveup - $(date +%s) ))
      (( w > left )) && w=$left
      if (( w <= 0 )); then
        echo "=== [$tag] license 仍未抢到且墙钟到点, 放弃 (共试 $attempt 次)"; break
      fi
      echo "--- license 没抢到 (第 $attempt 次), 退避 ${w}s 后重试, 距墙钟还剩 $(( left / 60 )) min"
      lic_sleep_until "$w" "$stopf" || { echo "=== [$tag] STOP 出现, 停止重试"; break; }
      continue
    fi

    hard=$((hard + 1))
    if (( hard > hard_max )); then
      echo "=== [$tag] matlab 非 license 故障退出码 $rc, 已重试 $hard_max 次, 放弃  $(date)"; break
    fi
    echo "--- matlab 退出码 $rc (非 license), 60s 后重试 ($hard/$hard_max)"
    lic_sleep_until 60 "$stopf" || break
  done

  rm -f "$ready" "$try" "$try.rc"
  echo "=== [$tag] 结束 退出码 $rc  尝试 $attempt 次  $(date)"
  return "$rc"
}
