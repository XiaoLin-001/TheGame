# -*- coding: utf-8 -*-
"""比對 `20_ART_DIRECTION.md` §3.5 的四條禁令（B2.7.3）。

跑法：  cd godot && python ../qa/copy_extract.py && python ../qa/copy_tells.py

**這不是一支會紅的測試。** 它只把候選列出來，因為四條禁令裡
有兩條有合法的例外（錯誤訊息的補救步驟、`標籤：值`），而分辨那兩者
需要讀句子。數字才是重點：B2.7.3 稽核後的基準是
**破折號 8 條、開發代號 0 條、`**` 0 條**。跑出比這多的就是又漏進來了。
"""
import io, sys, re
sys.stdout.reconfigure(encoding='utf-8')
rows=[l.rstrip('\n').split('\t',1) for l in io.open('strings.txt',encoding='utf-8')]
rows=[(a,b) for a,b in rows if not a.startswith('scripts/core/Hooks') ]
def has(s, pat): return re.search(pat, s) is not None
tells = {
 '破折號說教 ——': lambda s: '——' in s,
 '「不是X是Y」對句': lambda s: has(s, r'不是[^，。]{1,12}[，、]?(?:是|而是)') or has(s,r'[^，。]{1,12}不是[^，。]{1,10}$'),
 '冒號解釋句':  lambda s: has(s, r'^[^：]{2,10}：'),
 '批次／里程碑代號': lambda s: has(s, r'B\d\.\d|M[0-4]\b'),
 'markdown ** ': lambda s: '**' in s,
 '第二人稱說教「你的」': lambda s: '你的' in s or '你就' in s,
}
for name, f in tells.items():
    hits=[(a,b) for a,b in rows if f(b)]
    print('\n### %s  → %d 條' % (name, len(hits)))
    for a,b in hits[:40]: print('  %-42s %s' % (a,b))
