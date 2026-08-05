#!/usr/bin/env python3
"""
烘 hi-res Big5 點陣字模(32px 寬 × H 列),供 640x400 upscale 時 GfxFontChinese 直接繪製。

格式(與 qfg1_big5.fnt 同族,只是寬 32):
  每字 = big-endian Big5 碼(>H) + H 列 × 4 bytes(32px 寬 1bpp,MSB 在左),最後 0xFFFF 終結。

用法:bake_hires_font.py <out.fnt> <tsv1> [tsv2 ...] [--size N] [--height H] [--width W] [--font PATH] [--face IDX]
  掃所有 tsv 的中文(Big5 雙位元組字),各烘一個 hi-res glyph。
"""
import sys, struct, argparse
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eten_font import EtenFont
from PIL import Image, ImageFont, ImageDraw

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("tsv", nargs="+")
    ap.add_argument("--width", type=int, default=32, help="字寬 px(須為 8 倍數)")
    ap.add_argument("--height", type=int, default=28, help="字高 px(glyph box)")
    ap.add_argument("--size", type=int, default=27, help="字型 pt(留描邊餘裕,略小於 height)")
    ap.add_argument("--font", default="/usr/share/fonts/truetype/arphic/uming.ttc")
    ap.add_argument("--face", type=int, default=2)
    ap.add_argument("--eten", default="out/eten",
                    help="倚天點陣字目錄（STDFONT.15/SPCFONT.15/SPCFSUPP.15）")
    a = ap.parse_args()
    W, H = a.width, a.height
    # W 不必為 8 倍數（rowBytes 用 ceil）

    # 收集所有 tsv 中出現的 Big5 雙位元組字
    chars = set()
    for path in a.tsv:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "\t" not in line:
                    continue
                zh = line.split("\t", 1)[1]
                for ch in zh:
                    try:
                        b5 = ch.encode("big5")
                    except UnicodeEncodeError:
                        continue
                    if len(b5) == 2:  # 雙位元組 = 中文/全形
                        chars.add(ch)
    # 引擎硬寫的 UI 字串不在 tsv 裡,同 build_cht.py 一併補烘,否則狀態列/存讀檔會缺字。
    from build_cht import ENGINE_UI_CHARS
    chars.update(ENGINE_UI_CHARS)

    # 同 build_cht.py：倚天為主、TTF 只補真缺字。hi-res 是把 16x15 放大到 32x28，
    # 用最近鄰而不是平滑縮放——點陣字一平滑就糊，那正是不用 TTF 的理由。
    eten = EtenFont(a.eten)
    font = ImageFont.truetype(a.font, a.size, index=a.face)
    glyphs = []
    from_eten = 0
    fallback = []
    row_bytes_n = (W + 7) // 8
    for ch in sorted(chars):
        b5 = ch.encode("big5")
        code = (b5[0] << 8) | b5[1]

        bits = eten.render(ch, W, H)
        if bits is not None:
            rows = bytearray()
            for y in range(H):
                for byte_i in range(row_bytes_n):
                    v = 0
                    for bit in range(8):
                        x = byte_i * 8 + bit
                        v = (v << 1) | (bits[y][x] if x < W else 0)
                    rows.append(v)
            glyphs.append((code, bytes(rows)))
            from_eten += 1
            continue
        fallback.append(ch)

        img = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(img)
        try:
            bbox = d.textbbox((0, 0), ch, font=font)
        except Exception:
            bbox = (0, 0, W, H)
        gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
        ox = (W - gw) // 2 - bbox[0]
        oy = (H - gh) // 2 - bbox[1]
        d.text((ox, oy), ch, fill=255, font=font)
        px = img.load()
        rows = bytearray()
        row_bytes = (W + 7) // 8  # ceil：W 不必為 8 的倍數
        for y in range(H):
            for byte_i in range(row_bytes):
                bits = 0
                for bit in range(8):
                    x = byte_i * 8 + bit
                    bits = (bits << 1) | (1 if (x < W and px[x, y] >= 128) else 0)
                rows.append(bits)
        glyphs.append((code, bytes(rows)))

    with open(a.out, "wb") as out:
        for code, bmp in glyphs:
            out.write(struct.pack(">H", code))
            out.write(bmp)
        out.write(struct.pack(">H", 0xFFFF))
    print(f"hi-res 字型 {len(glyphs)} 字 (W={W}, H={H}) → {a.out}")
    print(f"  倚天 {from_eten} 字，TTF fallback {len(fallback)} 字"
          + ("：" + "".join(fallback) if fallback else ""))

if __name__ == "__main__":
    main()
