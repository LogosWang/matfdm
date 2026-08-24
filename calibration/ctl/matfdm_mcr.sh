#!/usr/bin/env bash
# 调编译版 standalone 的统一入口 —— 所有地方 (编排器/手工调试) 都走这个,
# 免得 MCR 路径、cache 目录、构建戳散落在各处。
#
#   bash matfdm_mcr.sh selftest <rundir>
#   bash matfdm_mcr.sh leg <rundir> <tag> <dose> <mult> [budget]
#   bash matfdm_mcr.sh metrics <rundir> <tag>
#
# MCR_CACHE_ROOT 必须放节点本地 (/tmp 是 353 GB tmpfs)。放 Lustre 的话每个
# 进程都去解压 CTF, 一个节点 120 个进程能把文件系统打死。

set -uo pipefail

BUILD=${MATFDM_BUILD_DIR:-${MATFDM_BUILD:-$SCRATCH/matfdm_build}/CURRENT}
MCR=${MCR_ROOT:-/global/common/software/nersc9/matlab/MCR/R2023b}

[[ -x "$BUILD/run_matfdm_run.sh" ]] || {
  echo "没有编译产物: $BUILD —— 先跑 build_standalone.sh" >&2; exit 1; }

export MATFDM_BUILD_DIR="$BUILD"
export MATFDM_BUILD_COMMIT=${MATFDM_BUILD_COMMIT:-$(cat "$BUILD/BUILD_COMMIT" 2>/dev/null || echo unknown)}
# 每节点一个 cache 目录; 同节点的进程共用, CTF 只解压一次
export MCR_CACHE_ROOT=${MCR_CACHE_ROOT:-/tmp/$USER/mcr.${SLURM_JOB_ID:-local}}
mkdir -p "$MCR_CACHE_ROOT" 2>/dev/null || true

exec "$BUILD/run_matfdm_run.sh" "$MCR" "$@"
