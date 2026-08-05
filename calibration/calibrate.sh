#!/usr/bin/env bash
set -euo pipefail
ctrl=$(cd "$(dirname "$0")" && pwd)
repo=${CALIB_REPO_DIR:-/mnt/c/Users/vool/matfdm_calibration_20260731}
session=oxcal_controller
command=${1:-start}

case "$command" in
  start)
    if [[ -e "$ctrl/STOP" || -e "$repo/calibration/STOP" ]]; then
      echo "STOP file present; refusing to start" >&2
      exit 3
    fi
    if [[ $(jq -r '.phase // "unknown"' "$ctrl/state.json" 2>/dev/null) == complete ]]; then
      echo "calibration already complete"
      exit 0
    fi
    if tmux has-session -t "=$session" 2>/dev/null; then
      echo "controller already running: $session"
      exit 0
    fi
    mkdir -p "$repo/calibration/logs"
    tmux new-session -d -s "$session" \
      "CALIB_REPO_DIR='$repo' '$ctrl/controller_supervisor.sh' >>'$repo/calibration/logs/controller.log' 2>&1"
    echo "started $session"
    ;;
  once)
    CALIB_REPO_DIR="$repo" "$ctrl/controller.py" once
    ;;
  status)
    CALIB_REPO_DIR="$repo" "$ctrl/controller.py" status
    ;;
  stop)
    touch "$ctrl/STOP"
    tmux kill-session -t "$session" 2>/dev/null || true
    echo "controller stopped; active MATLAB legs left untouched"
    ;;
  resume)
    rm -f "$ctrl/STOP"
    exec "$0" start
    ;;
  *)
    echo "usage: $0 {start|once|status|stop|resume}" >&2
    exit 2
    ;;
esac
