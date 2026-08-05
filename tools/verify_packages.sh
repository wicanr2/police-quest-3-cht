#!/bin/bash
# 六個交付包的收尾驗收。
#
# 用法：verify_packages.sh [包...]        （不給參數就驗 dist-all/ 全部）
#
# 為什麼要有這支腳本，而不是每次手打指令：
#
#   ① **只比對「包裡找到的檔案」會漏掉最慘的一種**——新增一種中文資料而打包腳本
#      忘了加時，逐檔比對會照樣印 ✓。所以基準是 dist-cht/ 的清單，反查缺件。
#   ② **只比中文資料對「只改引擎」完全無效**。修完引擎 bug 後六個包可以全綠，
#      其中兩個裝的卻是修正前的 binary——因為 .fnt/.tsv 一個 byte 都沒動，
#      驗收沒有任何察覺的管道。所以要另外比 ENGINE.txt 的引擎指紋。
#   ③ patch 版誤含遊戲資源是 [HARD] 紅線，要獨立檢查，不能靠「打包腳本應該沒錯」。
#
# [HARD] 改完這支要重跑一次正對照（--self-test）：故意造一個六條全違反的包餵給它，
#        確認每條都叫得出來。「沒有紅字」永遠有兩種解釋——包是好的，或檢查自己壞了。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${PQ3_WORKPLACE:-$(dirname "$HERE")}"
DIST_CHT="$W/dist-cht"
TMPBASE=$(mktemp -d)
trap 'rm -rf "$TMPBASE"' EXIT

# 期待的引擎指紋：從當前源碼樹現算，不是寫死的常數
# （寫死的話，改了引擎忘了更新常數 → 驗收綠燈但包是舊的，正是 ② 要防的事）
EXPECT_FP=$(ENGINE_SRC="$W/scummvm-src" bash "$HERE/engine_fingerprint.sh")

FAIL=0

# 把任一種容器攤平成一個目錄，之後的檢查對目錄跑，不必為三種格式各寫一套
explode() {  # explode <包> <目標目錄>
  local pkg=$1 dst=$2
  mkdir -p "$dst"
  case "$pkg" in
    *.AppImage) (cd "$dst" && "$pkg" --appimage-extract >/dev/null 2>&1) ;;
    *.zip)      unzip -o -q "$pkg" -d "$dst" ;;
    *.tar.gz)   tar xzf "$pkg" -C "$dst" ;;
    *)          echo "  ✗ 不認得的容器格式" ; return 1 ;;
  esac
}

verify_one() {
  local pkg=$1
  local base; base=$(basename "$pkg")
  local mode; case "$base" in *-patch-*) mode=patch ;; *-full-*) mode=full ;; *) mode=? ;; esac
  echo "=== $base（$mode 版）==="

  local d="$TMPBASE/$base.d"
  explode "$pkg" "$d" || { FAIL=1; return; }

  local bad=()

  # ── ① 中文資料反查缺件 + 逐檔 md5 ────────────────────────────────
  local f name found want got
  for f in "$DIST_CHT"/*; do
    name=$(basename "$f")
    found=$(find "$d" -name "$name" -type f | head -1)
    if [ -z "$found" ]; then
      bad+=("缺中文資料 $name")
      continue
    fi
    want=$(md5sum "$f" | cut -d' ' -f1)
    got=$(md5sum "$found" | cut -d' ' -f1)
    [ "$want" = "$got" ] || bad+=("$name md5 不符（包內 $got ≠ dist-cht $want）")
  done

  # ── ② 引擎指紋 ───────────────────────────────────────────────────
  local fp_file fp
  fp_file=$(find "$d" -name ENGINE.txt -type f | head -1)
  if [ -z "$fp_file" ]; then
    bad+=("缺 ENGINE.txt（無法判斷包內是哪一版引擎）")
  else
    fp=$(tr -d '[:space:]' < "$fp_file")
    [ "$fp" = "$EXPECT_FP" ] || bad+=("引擎指紋 $fp ≠ 當前源碼樹 $EXPECT_FP（包裡是舊 binary）")
  fi

  # ── ③ 遊戲資源與 ROM ─────────────────────────────────────────────
  local nres nrom
  nres=$(find "$d" -type f \( -iname 'RESOURCE.MAP' -o -iname 'RESOURCE.0*' \) | wc -l)
  nrom=$(find "$d" -type f -iname '*.ROM' | wc -l)
  # .DRV/.EXE/.V56/.SCR/.TEX 也是遊戲資源；scummvm.exe 是我們自己編的引擎，排除
  local nmisc
  nmisc=$(find "$d" -type f \( -iname '*.DRV' -o -iname '*.V56' -o -iname '*.SCR' -o -iname '*.TEX' -o -iname '*.EXE' \) \
          ! -iname 'scummvm.exe' | wc -l)

  if [ "$mode" = patch ]; then
    [ "$nres" -eq 0 ]  || bad+=("[HARD] patch 版含 $nres 個遊戲資源")
    [ "$nrom" -eq 0 ]  || bad+=("[HARD] patch 版含 $nrom 個 MT-32 ROM")
    [ "$nmisc" -eq 0 ] || bad+=("[HARD] patch 版含 $nmisc 個遊戲檔（.DRV/.V56/.SCR/.TEX/.EXE）")
  elif [ "$mode" = full ]; then
    # RESOURCE.MAP + .000～.004 共 6 個
    [ "$nres" -ge 6 ] || bad+=("full 版遊戲資源只有 $nres 個（應 ≥6）")
    [ "$nrom" -eq 2 ] || bad+=("full 版 MT-32 ROM 有 $nrom 個（應為 2）")
  else
    bad+=("檔名看不出是 patch 還是 full")
  fi

  if [ ${#bad[@]} -gt 0 ]; then
    printf '  ✗ %s\n' "${bad[@]}"
    FAIL=1
  else
    echo "  ✓ 中文資料齊全且 md5 相符／引擎指紋 $EXPECT_FP／遊戲資源 $nres 個、ROM $nrom 個"
  fi
}

# ── 正對照：故意造一個違反每一條的包，確認每條都叫得出來 ────────────────
self_test() {
  echo "########## 正對照（故意造壞包，每條規則都該叫）##########"
  local t="$TMPBASE/selftest"
  mkdir -p "$t/stage/cht"
  # 違反①：只放一個中文資料檔（缺件），而且內容是錯的（md5 不符）
  echo "這不是真的字型" > "$t/stage/cht/pq3_big5.fnt"
  # 違反②：引擎指紋是假的
  echo "deadbeef0000" > "$t/stage/cht/ENGINE.txt"
  # 違反③：patch 版塞進遊戲資源與 ROM
  echo x > "$t/stage/RESOURCE.MAP"
  echo x > "$t/stage/MT32_PCM.ROM"
  echo x > "$t/stage/IBMKBD.DRV"
  (cd "$t/stage" && zip -q -r "$t/PQ3-CHT-patch-selftest.zip" .)

  local out
  out=$(FAIL=0; verify_one "$t/PQ3-CHT-patch-selftest.zip" 2>&1)
  echo "$out"

  local miss=()
  echo "$out" | grep -q '缺中文資料'       || miss+=('① 缺件沒抓到')
  echo "$out" | grep -q 'md5 不符'          || miss+=('① md5 不符沒抓到')
  echo "$out" | grep -q '引擎指紋'          || miss+=('② 指紋不符沒抓到')
  echo "$out" | grep -q 'patch 版含 1 個遊戲資源' || miss+=('③ 遊戲資源沒抓到')
  echo "$out" | grep -q 'MT-32 ROM'         || miss+=('③ ROM 沒抓到')
  echo "$out" | grep -q '.DRV/.V56'         || miss+=('③ 其他遊戲檔沒抓到')

  echo "---------- 正對照結果 ----------"
  if [ ${#miss[@]} -gt 0 ]; then
    printf '  ✗ %s\n' "${miss[@]}"
    echo "  → 檢查腳本自己有洞，這時候的「全綠」不能信"
    return 1
  fi
  echo "  ✓ 六條規則全部叫得出來，檢查本身是活的"
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test; exit $?
fi

PKGS=("$@")
[ ${#PKGS[@]} -eq 0 ] && PKGS=("$W"/dist-all/PQ3-CHT-*)

for p in "${PKGS[@]}"; do verify_one "$p"; done

echo "================================"
if [ $FAIL -ne 0 ]; then
  echo "驗收未通過"; exit 1
fi
echo "六項全數通過（引擎指紋 $EXPECT_FP）"
