#!/usr/bin/env bash
# matfdm 标定控制器 —— 代码只有一份, 数据按运行目录隔离, 支持多节点批量拉起。
#
#   new    <id> [key=val ...]           建运行目录并写 config.json
#   sweep  <key> "<v1 v2 ...>" [前缀]   批量建一组运行 (每个值一个)
#   runid  <前缀> [--key <字段>] <值...>  只算运行名并查重, 不建目录
#   migrate [模式] [--apply]            老命名的目录改成科学计数法 (一次性)
#   launch <清单> [作业数] [墙钟]        一个作业占 N 节点, 每节点跑清单里的一个运行
#   submit <id> [作业数]                单节点模式: 只跑一个运行
#   list   [模式]                       列出运行目录 / 生成清单
#   status [id]                         进度总览
#   best   <id> [n]                     前 n 名及参数绝对值
#   export [模式] [n] [输出目录]         每个运行的前 n 名各导一个 txt (后处理)
#   stop / resume / clean <id>
#
# 例 —— 30 个前沿阈值, 30 节点一个作业, 排 4 轮接力:
#   bash matfdm.sh sweep front_thick "0.2 0.4 0.6 ... 8.0" ft
#   bash matfdm.sh list 'ft*' > runs_ft.txt
#   bash matfdm.sh launch runs_ft.txt 4

set -euo pipefail

CODE=${MATFDM_CODE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
RUNS=${MATFDM_RUNS:-${SCRATCH:-$HOME}/matfdm_runs}
ACCOUNT=${MATFDM_ACCOUNT:-m5181}
WALLTIME=${MATFDM_WALLTIME:-18:00:00}
mkdir -p "$RUNS"
py() { module load python >/dev/null 2>&1 || true; python3 "$@"; }

# ------------------------------------------------------------------ new
cmd_new() {
  local id=${1:?"用法: new <id> [key=val ...]"}; shift || true
  local dir="$RUNS/$id"
  mkdir -p "$dir"/{decouple,checkpoint,calibration/metrics,calibration/optimizer,calibration/logs}
  MF_ID="$id" MF_DIR="$dir" MF_CODE="$CODE" py - "$@" <<'PYEOF'
import json, os, subprocess, sys, datetime
from pathlib import Path
d, code = Path(os.environ['MF_DIR']), Path(os.environ['MF_CODE'])
f = d / 'config.json'
cfg = json.loads(f.read_text()) if f.exists() else {}
for k, v in dict(run_id=os.environ['MF_ID'], doses=[0, 0.5, 3], targets=[40, 60, 100],
                 front_thick=1.0, population=40, workers=120, middle_max=70,
                 endpoint_band=5, endpoint_tol=3, max_attempts=3,
                 composition_targets=[], composition_tol=5, composition_scale=3,
                 leg_timeout=0,
                 keep_traj=False, seed=20260804, overrides={}).items():
    cfg.setdefault(k, v)
for kv in sys.argv[1:]:
    if '=' not in kv: raise SystemExit(f"参数要写成 key=val: {kv}")
    key, val = kv.split('=', 1)
    node, keys = cfg, key.split('.')
    for k in keys[:-1]: node = node.setdefault(k, {})
    try: node[keys[-1]] = json.loads(val)
    except json.JSONDecodeError: node[keys[-1]] = val
f.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + '\n')
try:
    commit = subprocess.run(['git','-C',str(code),'rev-parse','HEAD'],
                            capture_output=True, text=True).stdout.strip() or '(no git)'
    dirty = bool(subprocess.run(['git','-C',str(code),'status','--porcelain'],
                                capture_output=True, text=True).stdout.strip())
except Exception:
    commit, dirty = '(no git)', False
(d/'provenance.txt').write_text(
    f"created : {datetime.datetime.now().isoformat(timespec='seconds')}\n"
    f"code    : {code}\ncommit  : {commit}\ndirty   : {'yes' if dirty else 'no'}\n"
    f"config  :\n{json.dumps(cfg, indent=2, ensure_ascii=False)}\n")
core = {k: v for k, v in cfg.items() if k != 'overrides'}
print(f"[new] {d}\n      {json.dumps(core, ensure_ascii=False)}")
if cfg['overrides']: print(f"      overrides: {json.dumps(cfg['overrides'], ensure_ascii=False)}")
PYEOF
}

# ---------------------------------------------------------------- sweep
# 运行名由 run_id.py 统一生成: 科学计数法, 0.1 -> ft1e-1, 1.0 -> ft1e0, 10 -> ft1e1。
# 不能直接 tr -d '.' —— 那样 1.0 和 10 都得 ft10, 两条链写进同一个目录全废;
# 0.1 写成 0.10 又会另开一个 ft010, 把已算的 ft01 孤立掉。
cmd_sweep() {
  local key=${1:?"用法: sweep <key> \"v1 v2 ...\" [前缀]"}
  local values=${2:?}; local prefix=${3:-$(echo "$key" | tr '.' '_')}
  local ids
  ids=$(py "$CODE/calibration/ctl/run_id.py" --prefix "$prefix" \
           --runs "$RUNS" --key "$key" $values) || exit 1
  while read -r id v; do
    [[ -n "$id" ]] && cmd_new "$id" "$key=$v"
  done <<< "$ids"
}

# 只算运行名, 不建目录 (JOB.sh 用; 顺带做撞名与历史数据一致性检查)
cmd_runid() {
  local prefix=${1:?"用法: runid <前缀> [--key <扫描字段>] <值...>"}; shift
  local key=""
  if [[ "${1:-}" == "--key" ]]; then key=$2; shift 2; fi
  py "$CODE/calibration/ctl/run_id.py" --prefix "$prefix" \
     ${key:+--runs "$RUNS" --key "$key"} "$@"
}

# ----------------------------------------------------------------- list
cmd_list() {
  local pat=${1:-'*'}
  for d in "$RUNS"/$pat/; do
    [[ -f "$d/config.json" ]] && echo "${d%/}"
  done
}

# --------------------------------------------------------------- launch
# 一个作业 = N 个节点, 第 k 个节点跑清单第 k 行的运行目录
cmd_launch() {
  local manifest=${1:?"用法: launch <清单文件> [作业数] [墙钟]"}
  local njobs=${2:-1}; local wall=${3:-$WALLTIME}
  [[ -f "$manifest" ]] || { echo "清单不存在: $manifest"; exit 1; }
  manifest=$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")
  local n; n=$(grep -c . "$manifest")
  local name; name="mn_$(basename "${manifest%.*}")"
  echo "清单 $manifest -> $n 个运行, 每作业 $n 节点, 排 $njobs 个 (墙钟 $wall)"
  local dep=""
  for ((i=0;i<njobs;i++)); do
    local jid
    jid=$(sbatch --parsable -N "$n" -t "$wall" -A "$ACCOUNT" -J "$name" \
          -o "$RUNS/${name}-%j.out" ${dep:+--dependency=afterany:$dep} \
          --export=ALL,MATFDM_CODE="$CODE",MATFDM_MANIFEST="$manifest",MATFDM_RUNS="$RUNS",\
MATFDM_LIC_SEATS="${MATFDM_LIC_SEATS:-2}",MATFDM_LIC_BACKOFF="${MATFDM_LIC_BACKOFF:-30}",\
MATFDM_LIC_BACKOFF_MAX="${MATFDM_LIC_BACKOFF_MAX:-600}",MATFDM_LIC_HOLD="${MATFDM_LIC_HOLD:-420}" \
          "$CODE/calibration/ctl/multi_node.sh")
    echo "  作业 $jid${dep:+ (等 $dep)}"
    dep=$jid          # 链式: 前一个结束后再跑, 断点续算
  done
  squeue --me -o "%.10i %.12j %.6D %.8T %.9M %.20R" | head -20
}

# --------------------------------------------------------------- submit
# 单节点模式: 只跑一个运行 (调试/单变体用)
cmd_submit() {
  local id=${1:?"用法: submit <id> [作业数]"}; local njobs=${2:-1}
  local dir="$RUNS/$id"
  [[ -f "$dir/config.json" ]] || { echo "没有 $dir/config.json, 先 new"; exit 1; }
  for ((i=0;i<njobs;i++)); do
    sbatch -J "mf_$id" -A "$ACCOUNT" -t "$WALLTIME" -N 1 \
           -o "$dir/slurm-%j.out" \
           --export=ALL,MATFDM_RUN="$dir",MATFDM_CODE="$CODE" \
           "$CODE/calibration/ctl/single_node.sh"
  done
  squeue --me -o "%.10i %.12j %.8T %.9M %.20R" | head
}

# --------------------------------------------------------------- status
cmd_status() {
  local id=${1:-}
  if [[ -n "$id" ]]; then
    MATFDM_RUN="$RUNS/$id" py "$CODE/calibration/ctl/gen_tool.py" history 0
    return
  fi
  printf "%-16s %-10s %7s %6s  %s\n" 运行 状态 评估 代数 最优前沿
  for d in "$RUNS"/*/; do
    [[ -f "$d/config.json" ]] || continue
    local id; id=$(basename "$d")
    local pop; pop=$(py -c "import json;print(json.load(open('$d/config.json'))['population'])" 2>/dev/null || echo 40)
    local n;   n=$(ls "$d"/calibration/metrics/*.csv 2>/dev/null | wc -l)
    local st;  st=$(squeue --me -h -o "%T" -n "mf_$id" 2>/dev/null | head -1)
    [[ -z "$st" ]] && st=$(squeue --me -h -o "%T" 2>/dev/null | head -1 || true)
    [[ -z "$st" ]] && st=idle
    [[ -f "$d/calibration/DONE" ]] && st=DONE
    local best; best=$(MATFDM_RUN="$d" CALIB_POPULATION="$pop" \
        py "$CODE/calibration/ctl/show_best.py" --top 1 2>/dev/null \
        | grep -oP '前沿 nm\s+:\s+\K.*' | head -1 || true)
    printf "%-16s %-10s %7d %6d  %s\n" "$id" "$st" "$n" "$((n / pop))" "${best:-'-'}"
  done
}

# 判据必须取该运行自己的 config.json —— 扫 middle_max/endpoint_band 时各运行
# 标尺不同, 用全局默认值排出来的名次是假的。
cmd_best() { local id=${1:?}; local n=${2:-10}; local d="$RUNS/$id"
  eval "$(py - "$d/config.json" <<'PYEOF'
import json, sys
from pathlib import Path
c = json.loads(Path(sys.argv[1]).read_text()); g = c.get
print(f'export CALIB_POPULATION={g("population",40)}')
print(f'export CALIB_MIDDLE_MAX={g("middle_max",70)}')
print(f'export CALIB_ENDPOINT_BAND={g("endpoint_band",5)}')
print(f'export CALIB_SEED={g("seed",20260804)}')
PYEOF
)"
  MATFDM_RUN="$d" CALIB_REPO_DIR="$d" py "$CODE/calibration/ctl/show_best.py" --top "$n"; }

# 后处理: 每个运行的前 n 名各导一个 <id>.txt, 默认 $RUNS/postprocess/
cmd_export() { local pat=${1:-'ft*'}; local n=${2:-10}; local out=${3:-}
  MATFDM_RUNS="$RUNS" py "$CODE/calibration/ctl/export_best.py" \
      --pattern "$pat" --top "$n" ${out:+--out "$out"}; }
# 老命名 (ft01/ft10) 的目录一次性改成科学计数法 (ft1e-1/ft1e0); 默认只看不动
cmd_migrate() { local pat=${1:-'ft*'}; shift || true
  MATFDM_RUNS="$RUNS" py "$CODE/calibration/ctl/migrate_run_ids.py" \
      --pattern "$pat" "$@"; }
cmd_stop()   { touch "$RUNS/${1:?}/calibration/STOP"; echo "已停 $1"; }
cmd_resume() { rm -f "$RUNS/${1:?}/calibration/STOP"; echo "已解除 $1"; }
# 清数据, 只留 config.json/provenance.txt。
# leg_runtime.json 必须一起删: 它按 <tag>/dose<d> 记腿的累计耗时, 而全清重来后
# case_tag 会从 b01_c01 重新开始, 正好撞上旧记录 —— 新腿一启动累计就已经超过
# leg_timeout, 会被当场判成"算太久不收敛"。
cmd_clean()  { local d="$RUNS/${1:?}"
  rm -rf "$d"/decouple "$d"/checkpoint \
         "$d"/calibration/{metrics,logs,optimizer,state.json,DONE,DONE.stale.*,STOP} \
         "$d"/calibration/{attempts.json,leg_runtime.json}
  mkdir -p "$d"/{decouple,checkpoint,calibration/metrics,calibration/optimizer,calibration/logs}
  echo "已清空 $1 的数据 (config.json 保留)"; }

case "${1:-}" in
  new)    shift; cmd_new    "$@" ;;
  sweep)  shift; cmd_sweep  "$@" ;;
  runid)  shift; cmd_runid  "$@" ;;
  migrate) shift; cmd_migrate "$@" ;;
  list)   shift; cmd_list   "$@" ;;
  launch) shift; cmd_launch "$@" ;;
  submit) shift; cmd_submit "$@" ;;
  status) shift; cmd_status "$@" ;;
  best)   shift; cmd_best   "$@" ;;
  export) shift; cmd_export "$@" ;;
  stop)   shift; cmd_stop   "$@" ;;
  resume) shift; cmd_resume "$@" ;;
  clean)  shift; cmd_clean  "$@" ;;
  *) sed -n '2,27p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
