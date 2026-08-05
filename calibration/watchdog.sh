#!/usr/bin/env bash
set -euo pipefail
ctrl=$(cd "$(dirname "$0")" && pwd)
repo=${CALIB_REPO_DIR:-/mnt/c/Users/vool/matfdm_calibration_20260731}

if [[ -e "$ctrl/STOP" || -e "$repo/calibration/STOP" ]]; then
  echo "stopped-by-sentinel"
  exit 0
fi
phase=$(jq -r '.phase // "unknown"' "$ctrl/state.json" 2>/dev/null || echo unknown)
if [[ "$phase" == complete ]]; then
  echo "complete"
  exit 0
fi
if tmux has-session -t '=oxcal_controller' 2>/dev/null; then
  echo "controller-healthy phase=$phase"
  exit 0
fi
CALIB_REPO_DIR="$repo" "$ctrl/calibrate.sh" start
echo "controller-restarted phase=$phase"
