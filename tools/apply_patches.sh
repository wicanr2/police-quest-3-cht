#!/bin/bash
# 把中文化引擎改動套進一棵已 checkout 好的 ScummVM 樹。
#
# 用法：apply_patches.sh <scummvm 樹路徑>
#
# 這支不會自己 clone——呼叫端要先 clone 並 checkout 到 patches/UPSTREAM_COMMIT.txt
# 記的那個 commit，否則上游漂移會讓 hunk 套不上（而 patch 的失敗訊息通常指向
# 「行號對不上」，容易被誤讀成 patch 檔壞了）。
set -euo pipefail

DST=${1:?需要 scummvm 樹路徑}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -d "$DST/engines/sci" ] || { echo "!! $DST 看起來不是 ScummVM 樹"; exit 2; }

# fontchinese.{cpp,h} 是新檔（不在上游），直接複製；其餘走 patch。
cp "$HERE/patches/fontchinese.cpp" "$HERE/patches/fontchinese.h" \
   "$DST/engines/sci/graphics/"

cd "$DST"
patch -p1 --forward < "$HERE/patches/0001-sci-cht-zh_twn.patch"

# 套完立刻反查關鍵改動確實在樹裡。patch 對某些 hunk 可能「already applied」而回 0，
# 只看 exit code 會漏掉半套上去的狀態。
grep -q 'GfxFontChinese'        engines/sci/graphics/cache.cpp   || { echo '!! cache.cpp 未套上'; exit 3; }
grep -q 'GFX_SCREEN_UPSCALED_640x400' engines/sci/graphics/screen.cpp || { echo '!! screen.cpp 未套上'; exit 3; }
grep -q 'chtFormatSpecsMatch'   engines/sci/engine/kstring.cpp   || { echo '!! kstring.cpp 未套上'; exit 3; }
grep -q 'big5NonStarters'       engines/sci/graphics/text16.cpp  || { echo '!! text16.cpp 未套上'; exit 3; }
grep -q 'ZH_TWN'                engines/advancedDetector.cpp     || { echo '!! advancedDetector.cpp 未套上'; exit 3; }
grep -q 'fontchinese'           engines/sci/module.mk            || { echo '!! module.mk 未套上'; exit 3; }

echo "patch 套用完成並通過反查：$DST"
