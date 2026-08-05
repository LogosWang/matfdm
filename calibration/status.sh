#!/usr/bin/env bash
set -euo pipefail
ctrl=$(cd "$(dirname "$0")" && pwd)
CALIB_REPO_DIR=${CALIB_REPO_DIR:-/mnt/c/Users/vool/matfdm_calibration_20260731} \
  "$ctrl/controller.py" status
