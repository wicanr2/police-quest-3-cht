#!/bin/bash
# headless 驅動：跳過片頭進遊戲後，依 CLICKS 送點擊序列並逐步截圖。
#
# 用法：drive.sh <輸出目錄> <跳片頭秒數> <收尾秒數>
# 環境變數：
#   CLICKS="x,y x,y ..."  進遊戲後依序點擊（螢幕絕對座標），每次點完截一張
#   LANG_TW=0             跑英文版對照
#   SCI_CHT_NOHIRES=1     關掉強制 640x400
set -u
OUT=${1:?需要輸出目錄}; BOOT=${2:-40}; TAIL=${3:-6}

export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
XVFB_PID=$!
sleep 3
mkdir -p "$OUT"

ARGS=(--path=/w/game --extrapath=/w/dist-cht --auto-detect)
[ "${LANG_TW:-1}" = "1" ] && ARGS+=(--language=tw)
/w/scummvm-src/scummvm "${ARGS[@]}" > "$OUT/run.log" 2>&1 &
sleep 10
xdotool mousemove 512 384 2>/dev/null

# 跳片頭
i=0
while [ $i -lt "$BOOT" ]; do
  xdotool key Escape 2>/dev/null; xdotool click 1 2>/dev/null
  sleep 1; i=$((i+1))
done
import -window root "$OUT/boot.png" 2>/dev/null

# 點擊序列
n=0
for c in ${CLICKS:-}; do
  x=${c%%,*}; y=${c##*,}
  # PQ3 的圖示列平常收起來，滑鼠碰到畫面頂端才降下 → 先喚出再點
  if [ "$y" -lt 200 ]; then
    xdotool mousemove "$x" 146; sleep 1
    xdotool mousemove "$x" 150; sleep 1
  fi
  xdotool mousemove "$x" "$y"; sleep 1
  xdotool click 1; sleep 2
  import -window root "$OUT/$(printf 'c%02d' $n).png" 2>/dev/null
  n=$((n+1))
done

# 收尾連拍（抓「只閃一下」的視窗）
i=0
while [ $i -lt "$TAIL" ]; do
  import -window root "$OUT/$(printf 't%02d' $i).png" 2>/dev/null
  sleep 1; i=$((i+1))
done

pkill -x scummvm 2>/dev/null
kill $XVFB_PID 2>/dev/null
grep -iE 'CHT:|big5|glyph|out of bounds' "$OUT/run.log" | head -10
