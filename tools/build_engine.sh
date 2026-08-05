#!/bin/bash
# 編譯 SCI-only ScummVM（docker，[HARD] 規則：編譯一律走 docker）
# 用法：build_engine.sh [--configure]
set -e
ROOT=/home/anr2/scummvm/police_quest3/workplace
SRC=$ROOT/scummvm-src
JOBS=$(( $(nproc) - 2 ))

run() { docker run --rm --name pq3-engine-build -v "$SRC":/src -w /src pq3-build:latest bash -c "$1"; }

if [ "$1" = "--configure" ] || [ ! -f "$SRC/config.mk" ]; then
  # [HARD] ⑤：不得帶 --disable-mt32emu，MT-32 一律編入
  run "./configure --disable-all-engines --enable-engine=sci \
        --disable-debug --enable-release \
        --disable-libcurl --disable-sonivox --disable-tinygl" 2>&1 | tail -25
  run "grep -E 'USE_MT32EMU' config.h" || { echo '!! MT-32 未編入，違反 ⑤ [HARD]'; exit 3; }
fi
run "make -j$JOBS" 2>&1 | tail -15
ls -la "$SRC/scummvm"
