# PQ3 中文化：這一輪踩到與查證的事

寫給下一款 SCI1 純 VGA 的自己。只記「查證過」的，還在猜的另外標明。

## 引擎判定

`.v56` 這個副檔名 SCI1 與 SCI1.1 共用，所以憑副檔名決定工具鏈會走錯整條路。
決定性的做法是拿解碼器對 ScummVM 逐像素比對：`sci1_view.py verify` 跑完 332 支 view，
全部一致 → SCI1 分支確認。這件事花不到十分鐘，比事後回頭改工具鏈便宜太多。

資源型別統計也回答了另一個問題：**dump 出來沒有 `heap.*`**，所以字串仍內嵌在
`script.NNN` + `text.NNN`（heap 是 SCI1.1 才有的），抽字要走 SCI0 那條路線，
不是 SQ4 的 heap 工具。

## `sci1_view.py` 有兩個會讓人誤判的 bug

兩個都不是「畫面壞掉」，而是**看起來像 codec 解錯**：

1. **`mirrorBits` 標記的 loop 沒做水平翻轉。** 症狀是那些 loop 約半數像素不符。
   我原本以為是 RLE 解錯，實際只是少了引擎繪製時的那一步翻轉
   （`view.cpp kViewVga`：`mirrorFlag` + `displaceX` 取負）。
   驗證方法很直接：把不符的 loop 編號跟 `mirrorBits` 的 set bit 對一次，完全吻合。
   **修的時候要一起處理 encode 端**，否則翻過的 bitmap 寫回資源、引擎再翻一次＝雙重翻轉。

2. **patch header 的 `headerSkip` 被寫死成 2。** PQ3 有 331 支 view 的 headerSkip 是 0
   （所以「固定跳 2」在絕大多數檔案上看起來完全正確），只有 `view.594` 是 32。
   症狀是 `IndexError` 而不是畫面錯，很容易被歸因到別的地方。
   **一個檔案例外，就足以證明假設是錯的**——別因為 331/332 對就收工。

## 排版

- **`Size()` 一定要跟 `Box()` 換同一份譯文。** 只掛繪製端的話，視窗是照英文長度開的，
  中文較長就溢出、句尾被裁；症狀非常像「譯文太長」，其實是量的跟畫的不是同一串。
- **`GetLongest()` 的日文 kinsoku 會誤傷 Big5。** 那段是為 PC-98 SJIS 寫的，
  `isDoubleByte()` 對 Big5 也成立，於是中文（無空格）被誤觸：它會刻意多塞一個
  超出 `maxWidth` 的雙位元組字，導致 `Box()` 的置中 `offset` 變負、行首字被裁掉左半邊。
  修法是 ZH_TWN 走自己的分支，斷在容得下的最後一字，再套 **Big5 避頭點**
  （。，、；：？！」』）…）**只往回退**，這樣行只會變短，`offset` 永遠 ≥ 0。
  - Big5 碼位要注意位元組順序：`curChar = byte0 | (byte1 << 8)`，所以「。」(A1 43) 是 `0x43A1`。
- **`_useEarlyGetLongestTextCalculations` 在 PQ3 是 false**（SCI1 走 `default: return false`），
  所以 KQ1 那條「每個中文控制項少掉最後一字」不適用，不要照抄那個修正。

## 抽字的兩個洞

主抽字工具（`extract_strings.py` + `extract_ega_scripts.py`）漏了 64 則，其中兩類是玩家看得到的：

1. **含硬換行的多行字串**（開場問句在 `script.127`，`\n` 是真的 0x0A）。
2. **全大寫的 UI 標籤**（`SAVE GAME`、`Change\r\nDirectory`）——過濾條件要求有小寫字母。

漏掉的症狀是實機顯示英文，而**覆蓋率統計看不出來**（它根本不在 worklist 裡）。
`tools/sweep_missing.py` 就是為此寫的：掃所有 script/text 的 null 終止字串，
與 skeleton 對帳，把差集列出來。**下一款開工就跑一次**，不要等 playtest 才發現。

漏抽的那則開場問句是玩家看到的第一個畫面。

## 譯文品質

- **驗證器用「能不能 encode 成 Big5」當繁體檢查**，比字表可靠：簡體字不在 Big5 裡，
  而這剛好也是字型的硬需求（烘不出字模的字＝畫不出來）。
- **Big5 檢查抓不到「過度繁化」**：`皇后→皇後`、`歇斯底里→歇斯底裡`、`公里→公裡`
  這些詞正體中文本來就用「簡體那一邊」的字，而且全都是合法 Big5。要另外列黑名單。
  便宜 model 特別容易犯，還會在回報裡寫「已修正簡體字」。
- **key 的尾端空白掉一個，引擎就靜默退回英文**，不會有任何錯誤訊息。驗證器一定要逐字元比對 key。
- **批次檔缺尾端換行**，`cat` 合併時會把跨檔的兩行黏成一行，兩則譯文一起消失。
  合併前先正規化。

## 打包

- **引擎指紋要用 `LC_ALL=C sort`。** 不加的話本機（zh_TW.UTF-8）與 CI runner（C）
  排序不同 → 同一棵樹算出兩個指紋。我第一版就踩到，還好有拿去跟 CI 對，
  否則會留下一個永遠誤報的檢查——**不穩定的指紋比沒有指紋更糟**，因為人會開始忽略它。
  診斷法：先 `diff -rq` 兩棵樹確認內容是否真的相同，再懷疑腳本。
- **Windows configure 漏帶 `--disable-freetype2` → exe 從 17 MB 變 69 MB。**
  MXE 有 freetype，configure 偵測到就把 38 MB 的 `fonts-cjk.dat` 嵌進 `.rsrc`。
  診斷特徵是 `objdump -h` 看到 `.rsrc` 遠大於 `.text`（54 MB vs 10 MB）。
  那四套 Noto CJK 對「已經自帶 Big5 字型」的專案毫無用處。
- **mingw image 要裝 `binutils`。** configure 的 endianness 測試是編一支程式再用
  `strings` 掃它；PATH 裡只有 MXE 前綴版的 `strings` 時會回報 `endianness unknown`
  然後 exit 1。這跟「漏帶 config.guess/config.sub」症狀相同、成因不同，別直接套舊結論。
- **YAML block scalar 裡不能放頂格的 heredoc**：不縮排會破壞 YAML，縮排了 shebang
  又不在第 0 byte。用 `printf` 逐行寫出，兩邊都不得罪。
- **`gh run watch --exit-status` 回非零不等於 CI 失敗**（這次是 Node 20 deprecation
  annotation）。真相在 artifact 與 `gh run view`，不在 watcher 的 exit code。

## headless 驅動

- PQ3 的圖示列平常收起來，**滑鼠碰到畫面頂端才降下**。直接點座標會全部落空，
  而畫面「只是沒動」，很容易誤判成引擎壞掉。
- SCI debugger 的 `room` 跳房**確實不穩**（實測多次只成功一兩次），
  拿它當唯一手段會卡住。要走到深處的畫面，還是得靠真人試玩。

## 還沒查清楚的

- **CHIPSTER 終端機的功能列（`REVIEW CASE` / `NEW FILE` / `SERIAL #` / `QUIT`）來源不明。**
  已排除：解壓後的 script/text/message 資源（grep + strings 都沒有）、
  尺寸相符的 view cel（7929 個 cel 沒有一個是 320×8~20）、pic 205（那是 Sierra logo）。
  下一步應該是在 `GfxText16::Draw` 開 `SCI_LOG_TEXT` 並**真的走進那個畫面**——
  這次三次 room jump 只成功一次，而那次沒開 log。
- **終端機欄位式畫面（`VICTIM - ` 這類）的中文行距沒有實機驗過。**
  `kernelDisplay` 絕對座標在本作確實有用（分數 `MOVEPEN(276,14)`、時間 `MOVEPEN(12,11)`），
  PQ1 在同型畫面上出現過上下相黏。**沒驗到就沒有套 PQ1 的推擠修正**——
  那個修正本身也可能弄壞版面，柵欄原則對「別人的修正」同樣成立。
