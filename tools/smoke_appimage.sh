#!/bin/bash
# 對「交付出去的那顆 AppImage」做開機實測，不是對源碼樹的 binary。
#
# 用法：smoke_appimage.sh <AppImage> <輸出目錄>
#
# 為什麼要分開做：verify_packages.sh 驗的是包裡有什麼（靜態），
# 這支驗的是包**跑不跑得起來**。兩者抓的是不同的錯——
# 檔案齊全但 AppRun 寫錯路徑、字型載不進去、ROM 沒被認出來，
# 靜態檢查全部看不到。
#
# 訊號取自引擎自己的 debug 輸出（-d1）：
#   CHT: loaded N translation entries        譯文表進得去
#   GfxFontChinese: loaded N hi-res glyphs   hi-res 字模進得去
#   Falling back to MT32                     Munt 先找 CM32L 才回退 = ROM 載入成功
# 反向訊號：cannot be used / could not open / blank
set -u
PKG=${1:?需要 AppImage 路徑}
OUT=${2:?需要輸出目錄}

export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
sleep 3
mkdir -p "$OUT"

# 容器內沒有 FUSE，用 runtime 內建的 extract-and-run；
# 這個參數由 AppImage runtime 自己消化，後面的參數照樣傳給 AppRun。
"$PKG" --appimage-extract-and-run -d1 > "$OUT/run.log" 2>&1 &

sleep 15
xdotool mousemove 512 384
import -window root "$OUT/01-boot.png" 2>/dev/null

# 跳過開場。這個「滑鼠停中央連點」的笨版本是實測有效的版本，
# 別改成精準點按鈕座標（改過，連續八次卡在開場對話框）。
for i in $(seq 1 20); do xdotool key Escape; xdotool click 1; sleep 1; done
import -window root "$OUT/02-ingame.png" 2>/dev/null

# 進遊戲的畫面上不一定有對白，而「沒有中文」與「中文壞掉」在截圖上長得一樣，
# 所以要主動逼出一句中文。
#
# [別用 F5] F5 開的是 ScummVM 自己的 GUI 存檔框，那是英文的（gui_language=en 是
# 刻意鎖的），拿它當證據等於什麼都沒驗到。要的是遊戲自己畫的字。
#
# 圖示列平常收起來，**滑鼠碰到畫面頂端才降下**；直接點座標會全部落空，
# 而畫面「只是沒動」，很容易誤判成引擎壞掉。
xdotool mousemove 512 150; sleep 2
xdotool mousemove 295 170; sleep 1; xdotool click 1; sleep 1   # 第 2 個圖示 = 眼睛（看）
xdotool mousemove 262 450; sleep 1; xdotool click 1             # 點電梯門
# 訊息框會自己消失，單張擷取常常差幾秒就撲空——而撲空的截圖跟「中文壞掉」
# 在畫面上分不出來。連拍幾張，事後挑有框的那張。
for n in 1 2 3 4 5 6; do sleep 1; import -window root "$OUT/03-chinese-$n.png" 2>/dev/null; done

pkill -x scummvm 2>/dev/null
sleep 2
pkill -x Xvfb 2>/dev/null
