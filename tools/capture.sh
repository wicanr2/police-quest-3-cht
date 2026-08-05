#!/bin/bash
# headless 擷取：跑 PQ3（中文或英文）並定時截圖
#
# 用法：capture.sh <輸出目錄> [秒數] [額外 scummvm 參數...]
# 環境變數：
#   LANG_TW=0          跑英文版對照（判別「是不是我造成的迴歸」，⑨ 的必備手段）
#   SCI_CHT_NOHIRES=1  關掉強制 640x400（判別「hi-res 撞狀態列」，④-S5）
#   SKIP=1             全程連續送 Esc + 點擊跳過片頭
#
# ⑨ [HARD] 的坑都已內建：Xvfb 起來後暖機 10 秒、root 用 1024x768、
# 收尾用 pkill -x（不是 pkill -f，那會殺掉這行 shell 自己）；
# xdotool 不帶 --window（SDL2 忽略 XSendEvent），type 帶 --delay 120。
set -u
OUT=${1:?需要輸出目錄}; SECS=${2:-30}; shift 2 || true

export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
XVFB_PID=$!
sleep 3

mkdir -p "$OUT"

ARGS=(--path=/w/game --extrapath=/w/dist-cht --auto-detect)
[ "${LANG_TW:-1}" = "1" ] && ARGS+=(--language=tw)

/w/scummvm-src/scummvm "${ARGS[@]}" "$@" > "$OUT/run.log" 2>&1 &
SCUMM_PID=$!

# [HARD] Xvfb + SDL 起來要暖機，太早送事件全部落空
sleep 10

# 把滑鼠移進遊戲視窗（XTEST 事件要落在視窗上）
xdotool mousemove 512 384 2>/dev/null

i=0
while [ $i -lt "$SECS" ]; do
  import -window root "$OUT/$(printf '%03d' $i).png" 2>/dev/null
  if [ "${SKIP:-0}" = "1" ]; then
    xdotool key Escape 2>/dev/null
    xdotool click 1 2>/dev/null
  fi
  sleep 1
  i=$((i+1))
done

# [HARD] pkill -x，不是 -f
pkill -x scummvm 2>/dev/null
kill $XVFB_PID 2>/dev/null
wait $SCUMM_PID 2>/dev/null
echo "=== run.log 尾段 ==="
grep -iE 'CHT:|big5|warning|error' "$OUT/run.log" | head -20
