#!/bin/bash
# 算出 SCI 引擎源碼的指紋（12 碼），寫進包裡供驗收比對。
#
# 為什麼需要：中文資料（translation.tsv / *.fnt）的 md5 驗收對「只改引擎」完全無效——
# 修完引擎 bug 後重打包，資料一個 byte 都沒動，驗收會全綠，而包裡裝的可能還是舊 binary。
#
# [HARD] macOS 的指紋必須由 CI 從「runner 上實際編出那顆 binary 的樹」算，
# 不可以拿本機的樹事後補算——那只是代理值，兩邊一旦不同步就會產生一個
# 「看起來對」的假指紋，比沒有還糟。所以 ENGINE_SRC 沒設時直接失敗，不靜默略過。
set -euo pipefail

SRC=${1:-${ENGINE_SRC:-}}
[ -n "$SRC" ] || { echo "!! 需要 ScummVM 樹路徑（參數或 ENGINE_SRC）"; exit 2; }
[ -d "$SRC/engines/sci" ] || { echo "!! $SRC/engines/sci 不存在"; exit 2; }

# [HARD] 一支腳本涵蓋兩個平台，不要為 macOS 另外留一份。
# macOS 預設沒有 sha256sum、只有 shasum；曾經因此在 repo 與 workplace 各放一份，
# 兩份就開始各自漂——而這支正好是「保證包與源碼對得上」的那支，
# 它自己有兩個版本，指紋就失去意義了。兩者都是 SHA-256、輸出格式相同（awk 取 $1）。
if command -v sha256sum >/dev/null 2>&1; then SHA=(sha256sum); else SHA=(shasum -a 256); fi

# [HARD] LC_ALL=C：sort 的排序受 locale 影響，本機（zh_TW.UTF-8）與 CI runner（C）
# 會排出不同順序 → 同一棵樹算出兩個不同指紋。不穩定的指紋比沒有指紋更糟，
# 因為它會一直誤報，然後人就開始忽略它。
find "$SRC/engines/sci" \( -name '*.cpp' -o -name '*.h' \) -print0 \
  | LC_ALL=C sort -z | xargs -0 "${SHA[@]}" | awk '{print $1}' | "${SHA[@]}" | cut -c1-12
