#!/usr/bin/env bash
set -uo pipefail
ctrl=$(cd "$(dirname "$0")" && pwd)
repo=${CALIB_REPO_DIR:-/mnt/c/Users/vool/matfdm_calibration_20260731}

while [[ ! -e "$ctrl/STOP" && ! -e "$repo/calibration/STOP" ]]; do
  phase=$(jq -r '.phase // "unknown"' "$ctrl/state.json" 2>/dev/null || echo unknown)
  [[ "$phase" == complete ]] && exit 0
  CALIB_REPO_DIR="$repo" "$ctrl/controller.py" run --interval 60
  rc=$?
  [[ $rc -eq 0 ]] && exit 0
  printf '[%s] controller exited rc=%s; restarting in 15s\n' "$(date --iso-8601=seconds)" "$rc" >&2
  sleep 15
done
