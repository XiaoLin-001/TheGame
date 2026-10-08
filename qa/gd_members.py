"""靜態驗證：畫面元件之間的成員參照（B3.14）。**不需要 Godot。**

為什麼要有它：`Battle.gd` 拆成 `BattleXxx.gd` 之後，元件以 `battle.<成員>`／`battle.<handle>.<成員>`
互相取用。GDScript 對「已知型別上不存在的成員」在**載入時不報錯**，只在執行到那一行時才炸——
所以一條很少走到的分支裡打錯一個字，所有測試都是綠的。這支把每一個 `battle.X` 對回真實宣告。

檢查的東西：
  · `battle.X`            X 必須是 `Battle.gd` 的成員，或 `Control` 繼承來的成員
  · `battle.handle.Y`     Y 必須是 handle 對應元件（`var cam: BattleCamera`）的成員
  · `BattleXxx.Z`         Z 必須是該元件的成員（靜態常數、列舉）

`qa/control_members.json` 是 Godot 4.7 的 `Control` 成員名單（`qa/dump_control_members.gd` 產生；
升 Godot 版本時重跑）。0 條才算過。

  python qa/gd_members.py
"""
import json, os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _gdparse as gdparse   # noqa: E402

D = os.path.join(ROOT, 'godot', 'scripts', 'screens') + os.sep
inherited = set(json.load(open(os.path.join(ROOT, 'qa', 'control_members.json')))["Control"])


def members_of(path):
    src = open(path, encoding='utf-8').read()
    h, ch = gdparse.split_chunks(src)
    return {c.name for c in ch}, src


battle_names, battle_src = members_of(D + 'Battle.gd')
handles = {}
for m in re.finditer(r'^var (\w+): (Battle\w+)$', battle_src, flags=re.M):
    names, _ = members_of(D + m.group(2) + '.gd')
    handles[m.group(1)] = (m.group(2), names)
class_members = {cls: names for cls, names in handles.values()}
class_members['BattleScreen'] = battle_names

bad = []
checked = 0
for path in sorted(glob.glob(D + '*.gd')):
    code = gdparse.code_only(open(path, encoding='utf-8').read())
    for i, line in enumerate(code.split('\n'), 1):
        for m in re.finditer(r'(?<![\w.])battle\.(\w+)(?:\.(\w+))?', line):
            first, second = m.group(1), m.group(2)
            checked += 1
            if first in handles:
                if second and second not in handles[first][1] and second not in inherited \
                        and second not in ('new', 'call', 'connect', 'bind'):
                    bad.append((os.path.basename(path), i, 'battle.%s.%s' % (first, second)))
            elif first not in battle_names and first not in inherited and first != 'new':
                bad.append((os.path.basename(path), i, 'battle.%s' % first))
        for m in re.finditer(r'(?<![\w.])(Battle\w+)\.(\w+)', line):
            cls, name = m.group(1), m.group(2)
            if cls in class_members:
                checked += 1
                if name not in class_members[cls] and name != 'new' and name not in inherited:
                    bad.append((os.path.basename(path), i, '%s.%s' % (cls, name)))

print('gd_members: 檢查 %d 處參照，%d 條不存在' % (checked, len(bad)))
for b in bad:
    print('  %s:%d  %s' % b)
sys.exit(1 if bad else 0)
