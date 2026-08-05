#!/usr/bin/env bash
set -euo pipefail
repo_dir=$1
case_tag=$2
dose=$3
mult_csv=$4
log=$5
repo_win=$(wslpath -w "$repo_dir")
matlab_exe='/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe'
export CALIB_ENABLE_PLOTS=${CALIB_ENABLE_PLOTS:-0}
cd /tmp
exec "$matlab_exe" -singleCompThread -batch \
  "cd('$repo_win'); run_calibration_case('$case_tag',$dose,[$mult_csv])" >>"$log" 2>&1
