# -*- coding: utf-8 -*-
"""比對 `20_ART_DIRECTION.md` §3.5 的禁令（B2.7.3 立四條，B3.9.5 加三條）。

跑法：  cd godot && python ../qa/copy_extract.py && python ../qa/copy_tells.py

**這不是一支會紅的測試。** 它只把候選列出來，因為前四條裡有兩條有合法的例外
（錯誤訊息的補救步驟、`標籤：值`），而分辨那兩者需要讀句子。數字才是重點：
**破折號 8 條、開發代號 0 條、`**` 0 條、結論詞 0 條、評價詞 0 條、辯護詞 0 條**。
跑出比這多的就是又漏進來了。

★ B3.9.5 加的後三條是**這支腳本自己漏掉的那一類**：使用者的原話是
「把所有長得像 AI 文字的部分都修掉」，而我手動掃出來的十七條裡，
四條禁令一條都沒抓到——它們的形狀是「替玩家下結論」「替設計辯護」，
不是破折號。抓不到的規則等於沒有規則，所以補進來。
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
 # ★ B3.9.5 三條。前四條抓的是「句子的形狀」，這三條抓的是**語氣**——
 #   而語氣才是「像 AI 寫的」那件事本身。
 '結論詞 所以／因此／於是': lambda s: has(s, r'所以|因此|於是|才划算|才成立|才是'),
 '評價詞 划算／吃虧／聰明': lambda s: has(s, r'划算|吃虧|聰明|漂亮|強力|厲害|最好的|值得'),
 '辯護詞 本來就／其實／畢竟': lambda s: has(s, r'其實|畢竟|本來就|之所以|當然'),
}
for name, f in tells.items():
    hits=[(a,b) for a,b in rows if f(b)]
    print('\n### %s  → %d 條' % (name, len(hits)))
    for a,b in hits[:40]: print('  %-42s %s' % (a,b))
