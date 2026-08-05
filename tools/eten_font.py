#!/usr/bin/env python3
"""倚天中文系統 (ETEN 3.53) 原生點陣字讀取。

老遊戲的中文該長什麼樣，倚天就長什麼樣。TTF 縮到 15px 會糊、筆劃比例也不對；
倚天是為那個尺寸手工調的點陣字。本專案的字形一律以倚天為主、TTF 只補真缺字。

字型檔從 `ET353S.iso` 抽出來放 `out/eten/`（gitignored，光碟是使用者自有）：

    STDFONT.15   13094 字 16x15  30 B/字   漢字（A440 起，**不含標點**）
    SPCFONT.15     408 字 16x15  30 B/字   全形標點與符號（A140–A3BF）
    SPCFSUPP.15    365 字 16x15  30 B/字   符號補充（C6A1 起）

[雷] 只帶 STDFONT 的話，「，。！？「」『』（）《》」全部會落到 fallback，
畫面上變成「字是倚天、標點是另一種字」。三個檔要一起帶。

點陣佈局：每列 (W+7)//8 bytes、MSB-first、由上而下。
"""
import os

W, H, STRIDE = 16, 15, 30


def _raw(hi, lo):
    """Big5 → 線性序號。低位元組跳過 0x7F 那個洞。"""
    return (hi - 0xA1) * 157 + ((lo - 0x40) if lo < 0x7F else (lo - 0x62))


LAST_SPC = _raw(0xA3, 0xBF)      # 符號區尾 = 407
BASE_A440 = _raw(0xA4, 0x40)     # 漢字區起點
LAST_COMMON = _raw(0xC6, 0x7E)   # 常用字尾
BASE_C6A1 = _raw(0xC6, 0xA1)     # 符號補充起點
LAST_SUPP = _raw(0xC8, 0xFE)
BASE_C940 = _raw(0xC9, 0x40)     # 次常用起點
N_COMMON = 5401

# Python big5 codec 與 Big5 表在少數符號上有歧義（～ 是 U+FF5E 還是 U+301C），
# encode 會丟例外，手動補。
MANUAL_BIG5 = {"～": b"\xa1\xe3", "－": b"\xa1\xbd"}


class EtenFont:
    def __init__(self, root):
        self.root = root
        self.std = self._load("STDFONT.15", 13094)
        self.spc = self._load("SPCFONT.15", 408)
        self.supp = self._load("SPCFSUPP.15", 365)
        self._oracle()

    def _load(self, name, expect):
        p = os.path.join(self.root, name)
        if not os.path.exists(p):
            raise SystemExit(f"缺少倚天字型 {p}（從 ET353S.iso 抽出來放這裡）")
        b = open(p, "rb").read()
        n = len(b) // STRIDE
        if n != expect:
            raise SystemExit(f"{name} 字數 {n} 與預期 {expect} 不符，格式可能不對")
        return b

    def _oracle(self):
        """idx=0 必須是「一」：只有第 8 列連續一長條。整批偏移的話這關會先擋下來。"""
        g = self.std[:STRIDE]
        ink = [i for i in range(H) if g[i * 2] or g[i * 2 + 1]]
        if ink not in ([6, 7], [7]):
            raise SystemExit(f"倚天索引 oracle 失敗：STDFONT idx=0 的墨列是 {ink}，不像「一」")

    def bitmap(self, ch):
        """回傳 (rows, W)；rows 是 15 個 int（每個 16 bits，MSB 在左）。查無回 None。"""
        try:
            e = MANUAL_BIG5.get(ch) or ch.encode("big5")
        except UnicodeEncodeError:
            return None
        if len(e) != 2:
            return None
        r = _raw(e[0], e[1])
        if r <= LAST_SPC:
            src, idx = self.spc, r
        elif r <= LAST_COMMON:
            src, idx = self.std, r - BASE_A440
        elif BASE_C6A1 <= r <= LAST_SUPP:
            src, idx = self.supp, r - BASE_C6A1
        elif r >= BASE_C940:
            src, idx = self.std, N_COMMON + (r - BASE_C940)
        else:
            return None
        off = idx * STRIDE
        if off < 0 or off + STRIDE > len(src):
            return None
        g = src[off:off + STRIDE]
        return [(g[i * 2] << 8) | g[i * 2 + 1] for i in range(H)]

    def render(self, ch, out_w, out_h):
        """縮放到 out_w x out_h，回傳 list[list[0/1]]。查無回 None。

        用最近鄰取樣而不是平滑縮放：點陣字平滑化會糊掉，那正是要避開 TTF 的理由。
        32x28 的 hi-res 是 2x 寬、垂直 15→28（13 列加倍、2 列單倍），
        比「取前 14 列加倍」保險——後者會讓那 0.2% 末列有墨的字掉一截。
        """
        rows = self.bitmap(ch)
        if rows is None:
            return None
        out = []
        for y in range(out_h):
            sy = min(H - 1, y * H // out_h)
            row = rows[sy]
            out.append([(row >> (W - 1 - min(W - 1, x * W // out_w))) & 1
                        for x in range(out_w)])
        return out
