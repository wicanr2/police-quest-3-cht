#!/bin/bash
# macOS full 版：CI 產的 engine-only artifact + 本機注入遊戲與 MT-32 ROM。
#
# 為什麼分兩段：.app 只能在 macOS host 組（codesign/hdiutil 都是 macOS 限定），
# 但 CI 拿不到遊戲資源與 ROM（那些不在公開 repo 裡）。所以引擎在 CI 產，
# 遊戲在本機塞。
#
# 用法：package_macos_full.sh <CI 下載的 engine tar.gz>
#
# [HARD] 改動已簽名的 .app 會讓簽章失效 → 移除 _CodeSignature（「未簽」勝過「壞簽」），
# 並附一支 修復－macOS.command 讓玩家在 Mac 上重新 ad-hoc 簽章。
# Linux 端無法 codesign 也無法實測，所以這個包**必須請使用者在 Mac 上跑一次
# 修復.command 再開一次 app** 才算驗完 —— 不要假設它會動。
set -euo pipefail

SRC=${1:?需要 CI 的 engine tar.gz}
# 路徑不寫死：以腳本所在位置推導專案根目錄，允許環境變數覆寫。
# （寫死 /home/anr2/... 的話，別人 clone 下來這支就直接失效。）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${PQ3_WORKPLACE:-$(dirname "$HERE")}"
# MT-32 ROM 有版權、不在 repo 裡，位置由環境變數指定（預設是本機慣用路徑）
MT32_ROM_SRC="${MT32_ROM_SRC:-$HOME/cht/mt32}"
STAGE=$W/build/macos-full
OUT=$W/dist-all
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"

tar xzf "$SRC" -C "$STAGE"
APP="$STAGE/ScummVM.app"
[ -d "$APP" ] || { echo "!! artifact 裡沒有 ScummVM.app"; exit 2; }

# 統一的 game/ 夾：遊戲資源 + 中文資料 + ROM 全放一起，啟動器只要指一個路徑
G="$APP/Contents/Resources/game"
mkdir -p "$G"
cp "$W"/game/RESOURCE.* "$G/"
cp "$W"/game/*.SCR "$W"/game/*.TEX "$W"/game/*.V56 "$G/" 2>/dev/null || true
cp "$W"/dist-cht/* "$G/"
cp "$MT32_ROM_SRC/MT32_CONTROL.1987-10-07.v1.07.ROM" "$G/MT32_CONTROL.ROM"
cp "$MT32_ROM_SRC/MT32_PCM.ROM" "$G/MT32_PCM.ROM"

# 啟動器：.app 旁邊的一支 .command，不動 bundle 的啟動機制
# （script 當進入點 / 改過的 Info.plist / codesign --deep 對混合結構，
#  任何一環出問題 Finder 雙擊都是靜默失敗，玩家只能回報「沒反應」）
L="$STAGE/玩－警察故事3－中文版.command"
printf '%s\n' '#!/bin/bash' \
  'cd "$(dirname "$0")"' \
  'G="$PWD/ScummVM.app/Contents/Resources/game"' \
  'exec ./ScummVM.app/Contents/MacOS/scummvm \' \
  '  --path="$G" --extrapath="$G" --auto-detect --language=tw \' \
  '  --music-driver=mt32' > "$L"
chmod +x "$L"

F="$STAGE/修復－macOS.command"
printf '%s\n' '#!/bin/bash' \
  'cd "$(dirname "$0")"' \
  'xattr -cr ScummVM.app && codesign --force --deep --sign - ScummVM.app' \
  'echo "已移除隔離屬性並重新簽章，接著雙擊「玩－警察故事3－中文版.command」。"' > "$F"
chmod +x "$F"

# 注入後原簽章一定失效：留著壞簽比沒簽更糟
rm -rf "$APP/Contents/_CodeSignature"

NAME=PQ3-CHT-full-macos-universal.tar.gz
(cd "$STAGE" && tar czf "$OUT/$NAME" ScummVM.app 玩－警察故事3－中文版.command 修復－macOS.command)

echo "=== 驗收 ==="
# [雷] 不要寫成 `tar tzf ... | grep -q X && echo ok`：grep -q 找到就提早結束、
# 關掉管線，tar 收到 SIGPIPE，配上 set -o pipefail 整條管線回非零 → && 不會執行。
# 結果是「內容其實在、檢查卻靜靜地什麼都沒說」。先把清單抓進變數再比。
LIST=$(tar tzf "$OUT/$NAME")
chk() {  # chk <樣式> <說明>
  if printf '%s\n' "$LIST" | grep -q "$1"; then echo "  ✓ $2"; else echo "  ✗ $2"; return 1; fi
}
chk 'Resources/game/RESOURCE\.MAP'      '含遊戲資源（full 版應有）'
chk 'Resources/game/translation\.tsv'   '含中文資料'
chk 'Resources/game/pq3_big5\.fnt'      '含 16x15 字型'
chk 'Resources/game/pq3_big5_hi\.fnt'   '含 hi-res 字型'
chk 'Resources/game/MT32_CONTROL\.ROM'  '含 MT-32 ROM（僅 full 版，不外流）'
# 只檢查 app 層級的簽章：注入檔案讓它失效了，所以要移除。巢狀的
# scummvm.docktileplugin 有自己的簽章、我沒動過那個 bundle，別順手刪
# （修復腳本的 codesign --deep 會一併重簽）。
if printf '%s\n' "$LIST" | grep -qE '^ScummVM.app/Contents/_CodeSignature'; then
  echo "  ✗ app 層級殘留失效簽章"; exit 1
else
  echo "  ✓ app 層級失效簽章已移除"
fi
ls -la "$OUT/$NAME"
