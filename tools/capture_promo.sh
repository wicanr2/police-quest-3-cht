#!/bin/bash
# 推廣片用的定點擷取：跑一段固定的操作序列，在同樣的位置截圖。
#
# 用法：capture_promo.sh <輸出目錄>
# 環境變數：LANG_TW=0 跑英文版（同一序列，讓中英鏡頭配得起來）
#
# 跟 capture.sh 的差別：那支是定時連拍（找畫面用），這支是**腳本化定點**，
# 中英兩次跑同一串操作，出來的檔名一一對應，才併得成左右對照。
#
# ⑨ 的坑都適用：Xvfb 暖機、root 用 1024x768、xdotool 不帶 --window、
# 收尾用 pkill -x。另外兩個本作專屬的：
#   - 圖示列平常收起來，滑鼠碰到畫面頂端才降下（直接點座標會全部落空）
#   - 訊息框會自己消失，單張擷取常撲空 → 一律連拍再挑
set -u
OUT=${1:?需要輸出目錄}
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp & sleep 3
mkdir -p "$OUT"

# -d1 是為了讓 "CHT: loaded N" 這行出現（它是 debug(1,…)）——收尾自檢要靠它。
ARGS=(--path=/w/game --extrapath=/w/dist-cht --auto-detect -d1)
[ "${LANG_TW:-1}" = "1" ] && ARGS+=(--language=tw)

# [HARD] 只能有一個 --extrapath。第二個會蓋掉第一個，中文字型與譯文就找不到，
# 而畫面**看起來只是沒翻譯**——很容易誤判成「這句漏譯」。
# 踩過：為了開 MT-32 而多加一個 --extrapath 指向 ROM 夾，整輪擷取全變英文。
# 截圖不需要音樂（配樂是另外側錄的），所以這裡不開 MT-32。
# 驗證訊號在 run.log：要有 "CHT: loaded N translation entries"，
# 不能出現 "could not open 'pq3_big5.fnt'"。
/w/scummvm-src/scummvm "${ARGS[@]}" > "$OUT/run.log" 2>&1 &
sleep 12
xdotool mousemove 512 384

burst() {  # burst <名稱> <張數>
  for n in $(seq 1 "$2"); do sleep 1; import -window root "$OUT/$1-$n.png" 2>/dev/null; done
}

# ── 01 標題 ───────────────────────────────────────────────────────────
import -window root "$OUT/01-title.png" 2>/dev/null

# ── 02 開場（含「要不要跳過動畫」問句，那是已翻譯的）────────────────
# 不要急著點：那個問句要等片頭真的開始才跳出來，只等 5 秒會整段錯過。
for i in $(seq -w 1 26); do import -window root "$OUT/02-intro-$i.png" 2>/dev/null; sleep 1; done
for i in $(seq 1 18); do xdotool key Escape; xdotool click 1; sleep 1; done

# ── 03 遊戲畫面（警局走廊）＋圖示列 ───────────────────────────────
xdotool mousemove 512 150; sleep 2
import -window root "$OUT/03-iconbar.png" 2>/dev/null

# 圖示列由左到右：走路 / 看 / 手 / 說話 / ? / 道具 / 設定 / 說明
EYE=295; BAG=563; TALK=400
sel() { xdotool mousemove 512 150; sleep 1; xdotool mousemove "$1" 170; sleep 1; xdotool click 1; sleep 1; }

# ── 04 看電梯門 ───────────────────────────────────────────────────────
sel $EYE
xdotool mousemove 262 450; xdotool click 1
burst 04-look-elevator 5
xdotool click 1; sleep 1

# ── 05 看走廊深處 ─────────────────────────────────────────────────────
sel $EYE
xdotool mousemove 520 380; xdotool click 1
burst 05-look-hall 5
xdotool click 1; sleep 1

# ── 06 道具欄（視窗內文字也是翻譯過的）───────────────────────────────
sel $BAG
burst 06-inventory 4
xdotool key Escape; sleep 1
xdotool click 1; sleep 1

# ── 07 對話（對自己說話會有旁白）─────────────────────────────────────
sel $TALK
xdotool mousemove 262 450; xdotool click 1
burst 07-talk 5

pkill -x scummvm 2>/dev/null; sleep 2; pkill -x Xvfb 2>/dev/null

# ── 收尾自檢：中文那一輪必須真的載入了中文 ─────────────────────────
# 沒有這段的話，「27 張截圖」跟「27 張英文截圖」在輸出上完全一樣，
# 要等人肉看圖才會發現。
if [ "${LANG_TW:-1}" = "1" ]; then
  if grep -q "could not open 'pq3_big5" "$OUT/run.log"; then
    echo "!! 字型沒載入 —— 這批截圖是英文的，不能用" >&2; exit 1
  fi
  grep -q 'CHT: loaded' "$OUT/run.log" \
    || { echo "!! run.log 沒有 'CHT: loaded'，譯文沒進去" >&2; exit 1; }
  echo "自檢通過：$(grep -o 'CHT: loaded [0-9]* translation entries' "$OUT/run.log" | head -1)"
fi
