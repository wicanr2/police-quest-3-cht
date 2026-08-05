#!/usr/bin/env python3
"""補掃：把 dump 出的 script/text 資源裡「看起來是玩家可見英文」但不在 skeleton 的字串撈出來。

存在的理由：主抽字工具（extract_strings.py + extract_ega_scripts.py）各有過濾條件，
實測至少漏掉兩類——
  1. 含硬換行的多行敘事（開場問句在 script.127，`\\n` 是真正的 0x0A）。
  2. 前導 bytecode 黏著、或只有大寫字母的 UI 標籤。
漏掉的症狀是實機顯示英文，而覆蓋率統計看不出來（因為它根本不在 worklist 裡）。

輸出與 skeleton 同格式（`原文<TAB>原文`，`\\n` 已跳脫），可直接併進 skeleton 再送翻譯。

用法：sweep_missing.py <dump_dir> <skeleton.tsv> <out.tsv>
"""
import sys, os, glob, re

WORDY = re.compile(r'[A-Za-z]{2,}')
# 明顯是引擎內部符號、不是給玩家看的
INTERNAL = re.compile(
    r'^(?:[a-z][a-zA-Z0-9]*|[A-Z][a-zA-Z0-9]*)$'          # 單一識別字
    r'|^\W+$'
    r'|^(?:p_|s_|gk|ego|the[A-Z])'
)


def esc(s):
    return (s.replace('\\', '\\\\').replace('\n', '\\n')
             .replace('\r', '\\r').replace('\t', '\\t'))


def candidates(path):
    d = open(path, 'rb').read()
    body = d[2 + d[1]:] if d[:1] in (b'\x80', b'\x83') else d
    for chunk in body.split(b'\x00'):
        if not (2 <= len(chunk) <= 800):
            continue
        try:
            s = chunk.decode('latin1')
        except Exception:
            continue
        # 允許 \n \r，其餘控制碼視為雜訊
        printable = sum(1 for c in s if 32 <= ord(c) < 127 or c in '\n\r')
        if printable / len(s) < 0.98:
            continue
        t = s.strip()
        if len(t) < 4 or not WORDY.search(t):
            continue
        if INTERNAL.match(t):
            continue
        # 至少兩個英文詞，或是有句讀的單句
        words = WORDY.findall(t)
        if len(words) < 2 and not re.search(r'[.!?:]', t):
            continue
        yield s


def main():
    dump_dir, skel, out = sys.argv[1], sys.argv[2], sys.argv[3]
    known = set()
    for line in open(skel, encoding='utf-8'):
        k = line.rstrip('\n').split('\t')[0]
        if k:
            known.add(k)

    found, seen = [], set()
    for path in sorted(glob.glob(os.path.join(dump_dir, 'script.*'))
                       + glob.glob(os.path.join(dump_dir, 'text.*'))):
        for s in candidates(path):
            k = esc(s)
            if k in known or k in seen:
                continue
            seen.add(k)
            found.append((os.path.basename(path), k))

    with open(out, 'w', encoding='utf-8') as f:
        for _, k in found:
            f.write(f'{k}\t{k}\n')

    print(f'skeleton {len(known)} 則；補掃發現 {len(found)} 則未收錄 → {out}')
    for src, k in found[:40]:
        print(f'  [{src}] {k[:90]}')
    if len(found) > 40:
        print(f'  …另有 {len(found) - 40} 則')


if __name__ == '__main__':
    main()
