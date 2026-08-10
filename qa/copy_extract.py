# -*- coding: utf-8 -*-
"""掃出全部**玩家看得到的字串**（`20_ART_DIRECTION.md` §3.5；B2.7.3）。

跑法：  cd godot && python ../qa/copy_extract.py

只掃 `scripts/` 與 `data/`，跳過整行註解——註解是寫給自己的，
它的語氣不受 §3.5 管（而那正是問題的來源：兩種語氣寫在同一個檔案裡）。
輸出一份 `strings.txt` 給 `copy_tells.py` 用。
"""
import io, os, re
pat = re.compile(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"')
rows=[]
for root in ['scripts','data']:
    for dp,_,fs in os.walk(root):
        for f in fs:
            if not f.endswith('.gd'): continue
            p=os.path.join(dp,f)
            for i,line in enumerate(io.open(p,encoding='utf-8'),1):
                st=line.lstrip()
                if st.startswith('#'): continue
                for m in pat.finditer(line):
                    rows.append((p.replace(os.sep,'/'),i,m.group(1)))
print('total strings:', len(rows))
from collections import Counter
for k,v in Counter(r[0] for r in rows).most_common(): print('%4d  %s'%(v,k))
io.open('strings.txt','w',encoding='utf-8').write(
    '\n'.join('%s:%d\t%s'%r for r in rows))
