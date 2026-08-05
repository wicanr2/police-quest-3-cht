#!/usr/bin/env python3
# 把開場/過場多行 crawl（script 內嵌、被 skeleton 拆裂漏譯）補回。
# 用「原文子字串」在 script dump 裡定位確切字串 → 算正規化 key（與引擎 sciChtNormKey 一致）
# → 配台式在地化譯文 → 產 translation/batch/zz_crawls.done。
import re, glob, sys

def norm(s):
    return re.sub(r'\s+', ' ', s.replace('\r', ' ').replace('\n', ' ')).strip()

# 蒐集所有 script null 終止字串
strings = []
for f in glob.glob('extract/dump/script.*'):
    for c in open(f, 'rb').read().split(b'\x00'):
        s = c.decode('latin-1')
        if len(s) > 8:
            strings.append(s)

def find(sub):
    """用子字串定位唯一 script 字串，回傳確切原文（含 \n）。"""
    hits = [s for s in strings if sub in s]
    # 取最短的（避免抓到更大的黏連塊）
    hits = sorted(set(hits), key=len)
    if not hits:
        print(f"!! 找不到: {sub!r}", file=sys.stderr); return None
    return hits[0]

# (定位子字串, 台式在地化譯文)  —— 譯文沿用譯名表：羅傑·威爾科/沃霍爾/佩斯圖倫/仙女座雙傑/廢渣軟體
PAIRS = [
    ("indeterminate amount",
     "自從羅傑·威爾科駕著逃生艙，從沃霍爾那座燃燒的太空要塞逃出來，也不知過了多久。我們的英雄在冷凍沉睡中，時間彷彿靜止了。"),
    ("Its engines long spent",
     "引擎早已燃盡，這艘小逃生艙漫無目的地飄過陌生星域，一路被小行星和太空垃圾撞得改了無數次航向。艙內，羅傑在睡眠艙裡睡得香甜……但好景不常。"),
    ("You enter a blackness",
     "你陷入一片前所未見的漆黑，對時間和速度的感覺全都消失了。"),
    ("A bright light becomes visible",
     "遠方浮現一道強光，隨著你的飛船疾速衝去而越變越大。最後，你被拋出黑暗，墜入一個平行宇宙。"),
    ("overwhelming force of the black hole",
     "黑洞以無法抗拒的引力把飛船吸了進去。你和乘客束手無策，只能繫好安全帶，聽天由命。"),
    ("sub-lightspeed",
     "你把引擎降到次光速，緩緩接近一顆看似適合居住的星球。"),
    # 掃描讀數：用讀數獨有子字串定位（避開較短的 ORBITING/APPROACHING 狀態行）
    ("1 KNOWN SETTLEMENT",
     "名稱：弗利布特星　星區：39　稀薄大氣　已知聚落：1 處"),
    ("NUMBER SERVED",
     "名稱：巨石漢堡速食小館　星區：62　供應數量：有限"),
    ("SURFACE UNCHARTED",
     "名稱：佩斯圖倫　星區：69　居民：不明　地表：未測繪。果然……"),
    ("CRATER-STREWN",
     "名稱：奧特加星　星區：82　居民：不明　地表：火山遍布、坑洞密集"),
    # 軌道狀態行（短，玩家可見）
    ("ORBITING PLANET PHLEEBHUT",
     "環繞弗利布特星軌道中"),
    ("APPROACHING MONOLITH BURGER",
     "接近巨石漢堡中"),
    ("ORBITING PLANET ORTEGA",
     "環繞奧特加星軌道中"),
    ("INSUFFICIENT POWER",
     "電力不足　無法啟動系統檢查"),
    ("USING STORED POWER",
     "使用儲備電力　低於 10%"),
    ("Thanks To The Following",
     "感謝以下各位在本遊戲製作期間的鼎力相助："),
    ("Two Babes From Andromeda",
     "仙女座來的兩位正妹（我們的老婆），忍受我們這整整 12 個月"),
    ("Shelling Out Your Hard Earned",
     "還有你！（願意掏出辛苦錢買下這款遊戲）"),
]

out = open('translation/batch/zz_crawls.done', 'w', encoding='utf-8')
n = 0
for sub, zh in PAIRS:
    orig = find(sub)
    if orig is None:
        continue
    key = norm(orig)
    out.write(f"{key}\t{zh}\n")
    n += 1
    print(f"[{n}] key={key[:55]!r}...")
out.close()
print(f"\n寫入 {n} 筆 → translation/batch/zz_crawls.done")
