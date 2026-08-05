#!/bin/bash
# 打包 Linux AppImage。
#
# 用法：package_appimage.sh <patch|full>
#   patch = 只有引擎 + 中文資料（上 GitHub Release，玩家自備遊戲）
#   full  = 內嵌整份 game/（只留本機，不外流）
set -euo pipefail

MODE=${1:?需要 patch 或 full}
# 路徑不寫死：以腳本所在位置推導專案根目錄，允許環境變數覆寫。
# （寫死 /home/anr2/... 的話，別人 clone 下來這支就直接失效。）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${PQ3_WORKPLACE:-$(dirname "$HERE")}"
# MT-32 ROM 有版權、不在 repo 裡，位置由環境變數指定（預設是本機慣用路徑）
MT32_ROM_SRC="${MT32_ROM_SRC:-$HOME/cht/mt32}"
OUT=$W/dist-all
mkdir -p "$OUT"

APPDIR=$W/build/AppDir-$MODE
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/cht"

cp "$W/scummvm-src/scummvm" "$APPDIR/usr/bin/"
cp "$W"/dist-cht/* "$APPDIR/usr/share/cht/"
ENGINE_SRC="$W/scummvm-src" bash "$W/tools/engine_fingerprint.sh" > "$APPDIR/usr/share/cht/ENGINE.txt"

# 只挑用得到的 engine-data。全套約 59MB，其中 fonts-cjk.dat 就佔 37MB——
# 我們自己烘 Big5 字型，那份完全用不到；Roland_SC-55.sf2 同理（走 MT-32 ROM）。
# 但 scummremastered.zip 是預設主題，漏帶會在啟動器 GUI 出現 fallback 警告。
mkdir -p "$APPDIR/usr/share/scummvm"
for f in scummremastered.zip scummmodern.zip scummclassic.zip fonts.dat encoding.dat; do
  [ -f "$W/scummvm-src/gui/themes/$f" ] && cp "$W/scummvm-src/gui/themes/$f" "$APPDIR/usr/share/scummvm/" || true
  [ -f "$W/scummvm-src/dists/engine-data/$f" ] && cp "$W/scummvm-src/dists/engine-data/$f" "$APPDIR/usr/share/scummvm/" || true
done

if [ "$MODE" = "full" ]; then
  mkdir -p "$APPDIR/usr/share/game"
  cp "$W"/game/RESOURCE.* "$APPDIR/usr/share/game/"
  cp "$W"/game/*.SCR "$W"/game/*.TEX "$W"/game/*.V56 "$APPDIR/usr/share/game/" 2>/dev/null || true
  # MT-32 ROM 只有 full 版（本機保留）能附；[HARD] 絕不入 git、絕不上 Release
  for pair in "MT32_CONTROL.1987-10-07.v1.07.ROM:MT32_CONTROL.ROM" "MT32_PCM.ROM:MT32_PCM.ROM"; do
    src="$MT32_ROM_SRC/${pair%%:*}"; dst=${pair##*:}
    [ -f "$src" ] && cp "$src" "$APPDIR/usr/share/game/$dst"
  done
fi

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SAVE="$XDG_DATA_HOME/pq3-cht/saves"
mkdir -p "$SAVE"
CHT="$HERE/usr/share/cht"
ARGS=(--extrapath="$CHT" --savepath="$SAVE" --auto-detect --language=tw)
[ -d "$HERE/usr/share/scummvm" ] && ARGS+=(--themepath="$HERE/usr/share/scummvm")

if [ -d "$HERE/usr/share/game" ]; then
  # full 版：遊戲就在包裡，直接開
  ARGS+=(--path="$HERE/usr/share/game")
  [ -f "$HERE/usr/share/game/MT32_CONTROL.ROM" ] && ARGS+=(--music-driver=mt32)
else
  # patch 版：玩家自備遊戲
  if [ -n "${PQ3_GAME_DIR:-}" ]; then
    ARGS+=(--path="$PQ3_GAME_DIR")
  else
    echo "《警察故事3》繁體中文化（patch 版，不含遊戲本體）"
    read -r -p "請輸入 Police Quest 3 遊戲資料夾路徑：" G
    ARGS+=(--path="$G")
  fi
fi
exec "$HERE/usr/bin/scummvm" "${ARGS[@]}" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/pq3-cht.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Police Quest 3 CHT
Exec=AppRun
Icon=pq3-cht
Categories=Game;
EOF
# 需要一個 icon，隨便給個 1x1 也行，但給張截圖縮圖比較像樣
printf '\x89PNG\r\n\x1a\n' > "$APPDIR/pq3-cht.png"
cp "$W/scummvm-src/icons/scummvm.png" "$APPDIR/pq3-cht.png" 2>/dev/null || true

NAME="PQ3-CHT-${MODE}-linux-x86_64.AppImage"
docker run --rm --name pq3-appimage -v "$W":/w -w /w pq3-appimage:latest \
  /opt/appimagetool --appimage-extract-and-run "/w/build/AppDir-$MODE" "/w/dist-all/$NAME" 2>&1 | tail -3

ls -la "$OUT/$NAME"
