#!/bin/bash
# 逐一「看」場景裡的東西，把描述台詞撈出來當推廣片素材。
#
# 用法：capture_lines.sh <輸出目錄>
# 環境變數：LANG_TW=0 跑英文版（同序列，出來的檔名一一對應）
#
# 為什麼不靠換房間拿更多台詞：本作 headless 走得到的只有警局走廊附近，
# 除錯器 room 跳房實測十次只成功一兩次。同一個場景裡「看」十個東西，
# 拿到的台詞數比冒險換場多，而且穩定。
set -u
OUT=${1:?需要輸出目錄}
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp & sleep 3
mkdir -p "$OUT"

ARGS=(--path=/w/game --extrapath=/w/dist-cht --auto-detect -d1)
[ "${LANG_TW:-1}" = "1" ] && ARGS+=(--language=tw)
# [HARD] 只能有一個 --extrapath，第二個會蓋掉第一個 → 中文靜默失效（踩過）
/w/scummvm-src/scummvm "${ARGS[@]}" > "$OUT/run.log" 2>&1 &
sleep 12
xdotool mousemove 512 384
for i in $(seq 1 45); do xdotool key Escape; xdotool click 1; sleep 1; done

# 圖示列平常收起來，滑鼠碰頂端才降下
sel() { xdotool mousemove 512 150; sleep 1; xdotool mousemove "$1" 170; sleep 1; xdotool click 1; sleep 1; }
EYE=295

n=0
for xy in "262 450" "520 380" "385 285" "620 380" "690 375" "450 390" "500 520" "500 230" "760 380" "340 430"; do
  n=$((n+1)); set -- $xy
  sel $EYE
  xdotool mousemove "$1" "$2"; xdotool click 1
  # 訊息框會自己消失，連拍兩張再挑
  sleep 1; import -window root "$OUT/L$(printf '%02d' $n)-a.png" 2>/dev/null
  sleep 1; import -window root "$OUT/L$(printf '%02d' $n)-b.png" 2>/dev/null
  xdotool click 1; sleep 1
done

pkill -x scummvm 2>/dev/null; sleep 2; pkill -x Xvfb 2>/dev/null

if [ "${LANG_TW:-1}" = "1" ]; then
  grep -q "could not open 'pq3_big5" "$OUT/run.log" && { echo "!! 字型沒載入，這批是英文的" >&2; exit 1; }
  grep -q 'CHT: loaded' "$OUT/run.log" || { echo "!! 譯文沒進去" >&2; exit 1; }
  echo "自檢通過：$(grep -o 'CHT: loaded [0-9]* translation entries' "$OUT/run.log" | head -1)"
fi
