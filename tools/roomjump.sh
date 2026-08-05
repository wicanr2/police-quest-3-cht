#!/bin/bash
# 用 SCI debugger 跳到指定房間並截圖。
#
# 用法：roomjump.sh <房間號> <輸出目錄>
#
# ⑨ [HARD] 的四個坑：
#   - Xvfb 起來後要暖機 ~10 秒，太早送 ctrl+alt+d 會落進遊戲而不是 console。
#   - root 用 1024x768，實測 640x480 時 console 收不到鍵盤。
#   - 換完場要先 exit 離開 console 再截圖，否則截到被 console 蓋住的畫面。
#   - 一個行程只跳一次房，跳第二次會 invalid port id 然後黑屏 → 每個目標房重開行程。
#   - xdotool 不能帶 --window（SDL2 忽略 XSendEvent），type 要 --delay 120。
set -u
ROOM=${1:?需要房間號}; OUT=${2:?需要輸出目錄}

export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
XVFB_PID=$!
sleep 3
mkdir -p "$OUT"

ARGS=(--path=/w/game --extrapath=/w/dist-cht --auto-detect)
[ "${LANG_TW:-1}" = "1" ] && ARGS+=(--language=tw)
/w/scummvm-src/scummvm "${ARGS[@]}" > "$OUT/run.log" 2>&1 &

sleep 12
xdotool mousemove 512 384

# 跳過開場（連點 + Esc），讓遊戲進到可互動狀態
# 開場會跳出「要看完整段嗎？」對話框，Skip it 按鈕在 script(6,51)
# → 螢幕 (192+6*2, 144+51*2) = (204, 246)。只點畫面中央會錯過它。
for i in $(seq 1 25); do
  xdotool key Escape
  xdotool mousemove 240 250; xdotool click 1
  xdotool mousemove 512 384; xdotool click 1
  sleep 1
done
import -window root "$OUT/before.png" 2>/dev/null

# 開 console → 換房 → 離開 console
xdotool key ctrl+alt+d; sleep 3
import -window root "$OUT/console.png" 2>/dev/null
xdotool type --delay 120 "room $ROOM"; sleep 1
xdotool key Return; sleep 3
xdotool type --delay 120 "exit"; sleep 1
xdotool key Return; sleep 3

for i in $(seq 0 3); do
  import -window root "$OUT/$(printf 'r%02d' $i).png" 2>/dev/null
  sleep 1
done

# 跳完房後的操作序列：POST="x,y  x,y  type:文字  key:Return"
n=0
for a in ${POST:-}; do
  case "$a" in
    type:*) xdotool type --delay 120 "${a#type:}" ;;
    key:*)  xdotool key "${a#key:}" ;;
    *)      xdotool mousemove "${a%%,*}" "${a##*,}"; sleep 1; xdotool click 1 ;;
  esac
  sleep 2
  import -window root "$OUT/$(printf 'p%02d' $n).png" 2>/dev/null
  n=$((n+1))
done

pkill -x scummvm 2>/dev/null
kill $XVFB_PID 2>/dev/null
grep -iE 'SCI_LOG_DISPLAY|invalid port|CHT:' "$OUT/run.log" | head -25
