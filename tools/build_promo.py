#!/usr/bin/env python3
"""把實機截圖組成推廣片的每一格畫面（1280×720 PNG），並產出 ffmpeg 合成指令。

為什麼用 PIL 而不是 ImageMagick / ffmpeg drawtext：
  兩者都無法指定 TTC 的字面索引，而 NotoSansCJK-Bold.ttc 的 face 0 是**日文**，
  繁體要 face 3。用錯字面，卡片上的字會是日文字形（察、直、骨這類看得出來）。
  另外這台的 ImageMagick 字型查找是壞的（montage 與 -annotate 直接 core dump），
  只有指定絕對路徑才動得了——PIL 兩個問題一次避開。

素材一律是引擎實機截圖（out/promo、out/lines），不是設計稿。
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
GAME = (192, 184, 832, 584)          # 1024×768 畫面裡的遊戲區（640×400）
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FACE_TC = 3                          # 0=JP 1=KR 2=SC 3=TC 4=HK
GOLD = (216, 176, 74)
GREY = (150, 150, 150)

OUT = sys.argv[1] if len(sys.argv) > 1 else "/w/out/video"
SRC_PROMO = "/w/out/promo"
SRC_LINES = "/w/out/lines"
AUDIO = "/w/out/audio/cap.wav"


def font(size):
    return ImageFont.truetype(FONT, size, index=FACE_TC)


def centred(d, y, text, size, fill=(255, 255, 255)):
    f = font(size)
    w = d.textbbox((0, 0), text, font=f)[2]
    d.text(((W - w) // 2, y), text, font=f, fill=fill)


def game(path):
    return Image.open(path).convert("RGB").crop(GAME)


def scene_full(path):
    """整幅遊戲畫面：640×400 放大 1.8 倍填滿高度，左右留黑邊。"""
    c = Image.new("RGB", (W, H), "black")
    c.paste(game(path).resize((1152, 720), Image.NEAREST), (64, 0))
    return c


def scene_sbs(en_path, cht_path):
    """左英文右中文對照。兩幅 640×400 併排剛好 1280 寬。"""
    c = Image.new("RGB", (W, H), "black")
    c.paste(game(en_path), (0, 180))
    c.paste(game(cht_path), (640, 180))
    d = ImageDraw.Draw(c)
    f = font(26)
    for x, label in ((320, "英文原版"), (960, "繁體中文化")):
        w = d.textbbox((0, 0), label, font=f)[2]
        d.text((x - w // 2, 132), label, font=f,
               fill=GREY if label == "英文原版" else GOLD)
    d.line([(640, 180), (640, 580)], fill=(70, 70, 70), width=2)
    return c


def card_open():
    c = Image.new("RGB", (W, H), "black")
    d = ImageDraw.Draw(c)
    centred(d, 250, "警察故事Ⅲ 陰謀", 62)
    centred(d, 340, "Police Quest 3: The Kindred", 26, GREY)
    centred(d, 420, "繁體中文化", 38, GOLD)
    return c


def card_close():
    c = Image.new("RGB", (W, H), "black")
    d = ImageDraw.Draw(c)
    centred(d, 150, "2,772 則遊戲文字中譯", 44, GOLD)
    centred(d, 240, "中文以 640×400 直接繪進畫面，不是把 320×200 的字放大", 24)
    centred(d, 285, "字模為倚天中文系統點陣字，1,953 字全數命中字庫", 24)
    d.line([(340, 360), (940, 360)], fill=(70, 70, 70), width=2)
    centred(d, 400, "github.com/wicanr2/police-quest-3-cht", 26, GREY)
    centred(d, 500, "原作腳本 Jim Walls", 26)
    centred(d, 545, "加州公路巡邏隊出身，把真實的警務程序寫進了遊戲", 22, GREY)
    return c


# ── 分鏡 ────────────────────────────────────────────────────────────────
# (產生函式, 秒數)
SHOTS = [
    (card_open,                                                   4.5),
    (lambda: scene_full(f"{SRC_PROMO}/cht/02-intro-03.png"),      3.0),
    (lambda: scene_full(f"{SRC_PROMO}/cht/02-intro-11.png"),      3.0),
    (lambda: scene_full(f"{SRC_PROMO}/cht/02-intro-22.png"),      3.0),
    (lambda: scene_sbs(f"{SRC_LINES}/en/L08-a.png",
                       f"{SRC_LINES}/cht/L08-a.png"),             5.0),
    (lambda: scene_sbs(f"{SRC_LINES}/en/L06-a.png",
                       f"{SRC_LINES}/cht/L06-a.png"),             5.0),
    (lambda: scene_sbs(f"{SRC_LINES}/en/L02-a.png",
                       f"{SRC_LINES}/cht/L02-a.png"),             5.0),
    (lambda: scene_full(f"{SRC_LINES}/cht/L03-a.png"),            3.2),
    (lambda: scene_full(f"{SRC_LINES}/cht/L07-a.png"),            3.2),
    (lambda: scene_full(f"{SRC_LINES}/cht/L10-a.png"),            3.2),
    (lambda: scene_full(f"{SRC_PROMO}/cht/04-look-elevator-2.png"), 3.5),
    (card_close,                                                  6.0),
]
XFADE = 0.5


def main():
    os.makedirs(OUT, exist_ok=True)
    durs = []
    for i, (make, dur) in enumerate(SHOTS):
        p = f"{OUT}/s{i:02d}.png"
        make().save(p)
        durs.append(dur)
        print(f"  s{i:02d}.png  {dur}s")

    # xfade 串接：第 k 個轉場的 offset = 目前已合成長度 - 轉場長度
    inputs, filt, prev = [], [], "[0:v]"
    for i, d in enumerate(durs):
        inputs += ["-loop", "1", "-t", f"{d}", "-i", f"{OUT}/s{i:02d}.png"]
    merged = durs[0]
    for k in range(1, len(durs)):
        off = merged - XFADE
        tag = f"[v{k}]"
        filt.append(f"{prev}[{k}:v]xfade=transition=fade:duration={XFADE}:offset={off:.2f}{tag}")
        merged = merged + durs[k] - XFADE
        prev = tag
    total = merged
    filt.append(f"{prev}format=yuv420p[vout]")
    # 配樂：原版遊戲音樂（即時側錄真實 Munt MT-32 輸出），淡入淡出
    filt.append(f"[{len(durs)}:a]atrim=2:{2 + total:.2f},asetpts=PTS-STARTPTS,"
                f"afade=t=in:st=0:d=1.5,afade=t=out:st={total - 2.5:.2f}:d=2.5[aout]")

    cmd = (["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + inputs +
           ["-i", AUDIO, "-filter_complex", ";".join(filt),
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-r", "30",
            "-c:a", "aac", "-b:a", "160k", "-shortest",
            f"{OUT}/pq3-cht-promo.mp4"])

    # PIL 在 pq3-tools、ffmpeg 在 pq3-video，沒有一顆 image 兩者都有 →
    # 這裡只把指令寫成腳本，合成那步在 video image 跑。
    sh = f"{OUT}/render.sh"
    with open(sh, "w", encoding="utf-8") as f:
        f.write("#!/bin/bash\nset -e\n" +
                " ".join(f"'{a}'" if any(c in a for c in " ;[]") else a for a in cmd) + "\n")
    os.chmod(sh, 0o755)
    print(f"\n總長 {total:.1f}s")
    print(f"畫格已產出，合成指令寫在 {sh}")
    if subprocess.run(["which", "ffmpeg"], capture_output=True).returncode == 0:
        subprocess.run(cmd, check=True)
        print(f"完成：{OUT}/pq3-cht-promo.mp4")


if __name__ == "__main__":
    main()
