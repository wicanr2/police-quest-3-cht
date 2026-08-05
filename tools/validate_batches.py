#!/usr/bin/env python3
"""驗證翻譯批次檔，並與 skeleton 的原文對帳。

檢查項（每一項都會指出是哪一行、哪個字）：
  1. 每行剛好一個 TAB。
  2. 第一欄（key）確實存在於 full_skeleton.tsv —— key 錯一個字元，引擎的內容比對
     就會 MISS 而退回英文，且不會有任何錯誤訊息。這是最容易無聲失敗的一項。
  3. 譯文的 % 格式符序列與原文完全相同（種類與順序）。少一個或順序不同，
     kFormat 的 %s 會讀到錯的暫存器。
  4. 譯文的字面 \n 數量與原文相同。
  5. 譯文每個字元都能編成 Big5。簡體字不在 Big5 裡，所以這一項同時抓到
     「混進簡體字」與「用了烘不出字模的符號」——對這個專案來說兩者都是壞的。
  6. 重複 key（後面的批次會蓋掉前面的，靜默）。

用法：validate_batches.py <skeleton.tsv> <batch_dir>
離開碼 0 = 全過。
"""
import sys, os, glob, re

SPEC = re.compile(r'%[-+ #0]*[0-9]*\.?[0-9]*([a-zA-Z%])')

# 過度繁化：這些詞在正體中文裡本來就用「簡體那一邊」的字，機器式的繁簡轉換會改錯。
# 全部是 Big5 合法字元，所以 Big5 檢查抓不到——要另外列。
OVERCONVERTED = {
    '皇後': '皇后', '太後': '太后', '皇太後': '皇太后',
    '歇斯底裡': '歇斯底里', '公裡': '公里', '裡程': '里程',
    '鄰裡': '鄰里', '裡長': '里長',
    '一並': '一併', '身份証': '身分證',
}


def specs(s):
    return [m for m in SPEC.findall(s) if m != '%']


def main():
    skel_path, batch_dir = sys.argv[1], sys.argv[2]
    keys = set()
    for line in open(skel_path, encoding='utf-8'):
        k = line.rstrip('\n').split('\t')[0]
        if k:
            keys.add(k)

    problems = []
    seen = {}
    total = 0

    for path in sorted(glob.glob(os.path.join(batch_dir, '*.tsv'))):
        name = os.path.basename(path)
        for lineno, raw in enumerate(open(path, encoding='utf-8'), 1):
            line = raw.rstrip('\n')
            if not line.strip():
                continue
            total += 1
            where = f'{name}:{lineno}'

            if line.count('\t') != 1:
                problems.append(f'{where} TAB 數 = {line.count(chr(9))}，應為 1')
                continue
            en, zh = line.split('\t')

            if en not in keys:
                problems.append(f'{where} key 不在 skeleton（引擎會靜默退回英文）: {en[:60]!r}')
            if en in seen:
                problems.append(f'{where} key 與 {seen[en]} 重複: {en[:50]!r}')
            else:
                seen[en] = where

            if specs(en) != specs(zh):
                problems.append(f'{where} 格式符不符 原文{specs(en)} 譯文{specs(zh)}: {en[:50]!r}')

            if en.count('\\n') != zh.count('\\n'):
                problems.append(f'{where} \\n 數不符 原文{en.count(chr(92)+"n")} 譯文{zh.count(chr(92)+"n")}: {en[:50]!r}')

            bad = sorted({c for c in zh if not _big5_ok(c)})
            if bad:
                problems.append(f'{where} 非 Big5 字元 {bad}（簡體字或烘不出字模的符號）: {zh[:40]!r}')

            for wrong, right in OVERCONVERTED.items():
                if wrong in zh:
                    problems.append(f'{where} 過度繁化 {wrong!r} 應為 {right!r}: {zh[:40]!r}')

    print(f'檢查 {total} 則、{len(seen)} 個相異 key')
    if problems:
        print(f'\n發現 {len(problems)} 個問題：')
        for p in problems[:200]:
            print('  ' + p)
        if len(problems) > 200:
            print(f'  …另有 {len(problems) - 200} 個')
        return 1
    print('全部通過')
    return 0


_cache = {}


def _big5_ok(ch):
    r = _cache.get(ch)
    if r is None:
        try:
            ch.encode('big5')
            r = True
        except Exception:
            r = False
        _cache[ch] = r
    return r


if __name__ == '__main__':
    sys.exit(main())
