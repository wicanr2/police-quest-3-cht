#!/bin/bash
# 打包 Windows zip。
#
# 用法：package_windows.sh <patch|full>
#
# ⑥-Windows 的六條在 Linux 上唯一驗得到的時機就是打包當下，所以檢查放在收尾：
#   1. .bat 換行必須 CRLF（cmd.exe 對 LF-only 的 batch 解析不可靠 → 黑視窗閃一下就關）
#   2. 中文不進 .bat 的 echo（cmd 以目前 code page 解讀 .bat、ScummVM 讀 ini 是 UTF-8，
#      兩邊要的編碼相反，怎麼存都有一邊讀錯）→ ini 用預先寫好的 UTF-8 靜態檔，.bat 只複製
#   3. zip 檔名純 ASCII 或設 UTF-8 旗標（Windows 內建解壓縮以 ANSI 解讀 → 中文檔名解不出來，
#      玩家看到的現象是「檔案消失」）
#   4. .bat 要把錯誤留在畫面上（否則任何失敗都是「閃一下就沒了」）
#   5. README.txt 補 UTF-8 BOM（舊版記事本沒 BOM 會當 ANSI，整份中文變亂碼）
#   6. ini 鎖 gui_language=en（非英文 GUI 下 theme 會去要 TTF，而這棵樹 #undef USE_FREETYPE2
#      → theme 載入失敗退回陽春樣式；繁中 GUI 上游是空的，自動挑到的往往是簡體）
set -euo pipefail

MODE=${1:?需要 patch 或 full}
# 路徑不寫死：以腳本所在位置推導專案根目錄，允許環境變數覆寫。
# （寫死 /home/anr2/... 的話，別人 clone 下來這支就直接失效。）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${PQ3_WORKPLACE:-$(dirname "$HERE")}"
# MT-32 ROM 有版權、不在 repo 裡，位置由環境變數指定（預設是本機慣用路徑）
MT32_ROM_SRC="${MT32_ROM_SRC:-$HOME/cht/mt32}"
STAGE=$W/build/win-$MODE
OUT=$W/dist-all
rm -rf "$STAGE"; mkdir -p "$STAGE/cht" "$OUT"

cp "$W/scummvm-win/scummvm.exe" "$STAGE/"
cp "$W"/dist-cht/* "$STAGE/cht/"
ENGINE_SRC="$W/scummvm-win" bash "$W/tools/engine_fingerprint.sh" > "$STAGE/cht/ENGINE.txt"

for f in scummremastered.zip scummmodern.zip scummclassic.zip; do
  cp "$W/scummvm-win/gui/themes/$f" "$STAGE/" 2>/dev/null || true
done

if [ "$MODE" = "full" ]; then
  mkdir -p "$STAGE/game"
  cp "$W"/game/RESOURCE.* "$STAGE/game/"
  cp "$W"/game/*.SCR "$W"/game/*.TEX "$W"/game/*.V56 "$STAGE/game/" 2>/dev/null || true
  cp "$MT32_ROM_SRC/MT32_CONTROL.1987-10-07.v1.07.ROM" "$STAGE/game/MT32_CONTROL.ROM" 2>/dev/null || true
  cp "$MT32_ROM_SRC/MT32_PCM.ROM" "$STAGE/game/MT32_PCM.ROM" 2>/dev/null || true
fi

# ── ini：UTF-8 靜態檔，相對路徑（玩家搬資料夾也不用重建設定）─────────────
{
  printf '[scummvm]\n'
  printf 'gui_language=en\n'
  printf 'themepath=.\n'
  printf 'extrapath=cht\n'
  printf 'savepath=saves\n'
  printf '\n[pq3-cht]\n'
  printf 'engineid=sci\n'
  printf 'gameid=pq3\n'
  printf 'description=警察故事3 繁體中文版\n'
  printf 'language=tw\n'
  if [ "$MODE" = "full" ]; then
    printf 'path=game\n'
    printf 'extrapath=cht;game\n'
    printf 'music_driver=mt32\n'
  fi
} > "$STAGE/scummvm-cht.ini"

# ── .bat：純 ASCII、CRLF、失敗要看得到 ────────────────────────────────
BAT="$STAGE/PLAY-PQ3-CHT.bat"
{
  printf '@echo off\r\n'
  printf 'cd /d "%%~dp0"\r\n'
  printf 'if not exist scummvm.exe (\r\n'
  printf '  echo scummvm.exe not found. Please extract the whole ZIP first.\r\n'
  printf '  pause\r\n'
  printf '  exit /b 1\r\n'
  printf ')\r\n'
  printf 'if not exist scummvm.ini copy /y scummvm-cht.ini scummvm.ini >nul\r\n'
  if [ "$MODE" = "full" ]; then
    printf 'scummvm.exe --config=scummvm.ini pq3-cht\r\n'
  else
    printf 'echo.\r\n'
    printf 'echo Police Quest 3 - Traditional Chinese (patch only, game not included)\r\n'
    printf 'set /p GAMEDIR=Enter your Police Quest 3 folder path: \r\n'
    printf 'scummvm.exe --config=scummvm.ini --path="%%GAMEDIR%%" --extrapath=cht --auto-detect --language=tw\r\n'
  fi
  printf 'if errorlevel 1 (\r\n'
  printf '  echo.\r\n'
  printf '  echo ScummVM exited with an error. The message above may help.\r\n'
  printf '  pause\r\n'
  printf ')\r\n'
} > "$BAT"

# ── README.txt：UTF-8 BOM ────────────────────────────────────────────
{
  printf '\xEF\xBB\xBF'
  cat <<'EOF'
《警察故事3》繁體中文化
======================

雙擊 PLAY-PQ3-CHT.bat 開始。

patch 版不含遊戲本體，啟動時會問你 Police Quest 3 的資料夾路徑
（裡面要有 RESOURCE.MAP 與 RESOURCE.000～004）。

如果視窗閃一下就關掉，代表啟動失敗但錯誤訊息來不及看。
請改用「命令提示字元」切到這個資料夾再執行 PLAY-PQ3-CHT.bat，
訊息就會留在畫面上。

MT-32 音樂：把 MT32_CONTROL.ROM 與 MT32_PCM.ROM 放進遊戲資料夾，
再到 ScummVM 的音效選項選 Roland MT-32。ROM 有版權，本包不附。
EOF
} > "$STAGE/README.txt"

# ── 打包（-UN=UTF8 設檔名旗標；zip 內檔名仍盡量純 ASCII 當第二道）─────
NAME="PQ3-CHT-${MODE}-win64.zip"
rm -f "$OUT/$NAME"
(cd "$STAGE" && zip -q -r -UN=UTF8 "$OUT/$NAME" .)

# ── 收尾檢查 ─────────────────────────────────────────────────────────
echo "=== 檢查 $NAME ==="
PQ3_DIST_CHT="$W/dist-cht" python3 - "$OUT/$NAME" "$MODE" <<'PY'
import sys, zipfile, re
p, mode = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(p)
names = z.namelist()
bad = []

# 1. .bat 必須 CRLF
for n in names:
    if n.lower().endswith('.bat'):
        d = z.read(n)
        if b'\r\n' not in d or re.search(rb'(?<!\r)\n', d):
            bad.append(f'{n} 不是純 CRLF')

# 2. .bat 必須純 ASCII（中文只能待在 UTF-8 的 ini 裡）
for n in names:
    if n.lower().endswith('.bat'):
        try:
            z.read(n).decode('ascii')
        except UnicodeDecodeError:
            bad.append(f'{n} 含非 ASCII 位元組')

# 3. 檔名純 ASCII 或有 UTF-8 旗標（純 ASCII 時 Info-ZIP 本來就不設 bit 11，
#    要求「都要有」會把一個完全正確的包判成失敗）
for i in z.infolist():
    try:
        i.filename.encode('ascii')
    except UnicodeEncodeError:
        if not i.flag_bits & 0x800:
            bad.append(f'{i.filename} 非 ASCII 檔名但未設 UTF-8 旗標')

# 4. .bat 要有 pause（失敗訊息留得住）
for n in names:
    if n.lower().endswith('.bat') and b'pause' not in z.read(n).lower():
        bad.append(f'{n} 沒有 pause，失敗時玩家看不到訊息')

# 5. README.txt 要有 UTF-8 BOM
r = [n for n in names if n.lower().endswith('readme.txt')]
if not r:
    bad.append('缺 README.txt')
elif not z.read(r[0]).startswith(b'\xef\xbb\xbf'):
    bad.append('README.txt 缺 UTF-8 BOM')

# 6. ini 要鎖 gui_language=en
ini = [n for n in names if n.endswith('.ini')]
if not ini:
    bad.append('缺 ini')
elif b'gui_language=en' not in z.read(ini[0]):
    bad.append('ini 未鎖 gui_language=en')

# 7. patch 版不得含遊戲資源
if mode == 'patch':
    leak = [n for n in names if re.search(r'RESOURCE\.[0-9M]|\.DRV$|\.EXE$|\.ROM$|\.V56$|\.SCR$|\.TEX$', n, re.I)
            and not n.lower().endswith('scummvm.exe')]
    if leak:
        bad.append(f'patch 版含遊戲資源: {leak[:5]}')
else:
    if not any('RESOURCE.MAP' in n for n in names):
        bad.append('full 版缺 RESOURCE.MAP')

# 8. 中文資料反查缺件（用 dist-cht 清單當基準，不是只比對「包裡找到的」）
import os
need = set(os.listdir(os.environ.get('PQ3_DIST_CHT','dist-cht'))) | {'ENGINE.txt'}
have = {n.split('/')[-1] for n in names if n.startswith('cht/')}
missing = need - have
if missing:
    bad.append(f'cht 資料缺件: {sorted(missing)}')

if bad:
    print('\n'.join('  ✗ ' + b for b in bad)); sys.exit(1)
print('  ✓ 八項檢查全過')
PY

ls -la "$OUT/$NAME"
