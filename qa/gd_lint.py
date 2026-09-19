# -*- coding: utf-8 -*-
"""GDScript 的靜態地雷掃描（B3.11）。**不需要 Godot**，所以沒有 Godot 的機器上也跑得了。

跑法：  python qa/gd_lint.py            # 從 repo 根目錄
退出碼 0 ＝ 沒抓到東西。它抓的是 `CLAUDE.md`「技術慣例」列的那幾條**編譯期或執行期
才會炸、而肉眼很難看出來**的規則：

  1. `Color(` 字面量只准出現在 `scripts/render/Palette.gd`
  2. 泛型 `lerp(`（要用 `lerpf()`；`.lerp(` 方法呼叫不算）
  3. `scripts/sim/` 裡的 `randf()`／`randi()`／`Time.get_ticks_*()`
  4. 同一支函式的 `match` 各分支共享作用域：**兩個分支各宣告同名的 `var` 是 parse error**
  5. 括號／方括號／大括號逐檔平衡
  6. 縮排用空白（本專案一律 tab）
  7. 字串裡的 `\u0000`／`\x00`（GDScript 把它讀成 NUL，匯入時每次噴
     「Unicode parsing error: Unexpected NUL character」，B3.13 踩到）

它抓不到型別錯誤——那要 Godot。但這六條每一條本專案都至少踩過一次。
"""
import io, os, re, sys

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot')
problems = []

def strip_comment(line):
    # 粗略：去掉字串外的 `#`。字串裡的 # 很少見，出現時只會少掃一行。
    out, in_str, q = [], False, ''
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            out.append(ch)
            if ch == '\\':
                i += 1
                if i < len(line):
                    out.append(line[i])
            elif ch == q:
                in_str = False
        else:
            if ch in ('"', "'"):
                in_str, q = True, ch
                out.append(ch)
            elif ch == '#':
                break
            else:
                out.append(ch)
        i += 1
    return ''.join(out)

def scan(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
    lines = io.open(path, encoding='utf-8').read().split('\n')
    depth = {'(': 0, '[': 0, '{': 0}
    pairs = {')': '(', ']': '[', '}': '{'}
    func_vars = {}      # (func_name) -> {var_name: (line, indent)}
    cur_func = None
    match_stack = []    # [(match_indent, {var_name: line})]
    for no, raw in enumerate(lines, 1):
        code = strip_comment(raw)
        st = code.strip()
        indent = len(raw) - len(raw.lstrip('\t')) if raw.startswith('\t') else 0
        if raw and raw[0] == ' ' and not raw.strip() == '':
            problems.append('%s:%d 縮排用了空白（本專案一律 tab）' % (rel, no))
        # 1. Color 字面量
        if 'Palette.gd' not in rel and re.search(r'(?<![\w.])Color\(', code):
            problems.append('%s:%d `Color(` 字面量（只准在 Palette.gd）' % (rel, no))
        # 2. 泛型 lerp
        if re.search(r'(?<![\w.])lerp\(', code):
            problems.append('%s:%d 泛型 `lerp(`（用 `lerpf()`）' % (rel, no))
        # 3. sim 裡的系統 RNG／時間
        # `rng.randf()`（注入的 seeded RandomNumberGenerator）是合法的——只抓**全域**函式。
        if rel.startswith('scripts/sim/') and re.search(r'(?<![\w.])(randf|randi|randfn|randi_range|randf_range)\(|Time\.get_ticks', code):
            problems.append('%s:%d sim 層用了系統 RNG／時間' % (rel, no))
        # 7b. 真的 NUL 字元（寫檔工具把跳脫字面量轉成了 NUL，B3.13 踩到）
        if chr(0) in raw:
            problems.append('%s:%d 有一個真的 NUL 字元' % (rel, no))
        # 7. 字串裡的 NUL 跳脫
        if re.search(r'\\u0000|\\x00', code):
            problems.append('%s:%d 字串裡有 NUL 跳脫（`\\u0000`／`\\x00`）' % (rel, no))
        # 5. 括號平衡
        in_str, q = False, ''
        for ch in code:
            if in_str:
                if ch == q:
                    in_str = False
                continue
            if ch in ('"', "'"):
                in_str, q = True, ch
            elif ch in depth:
                depth[ch] += 1
            elif ch in pairs:
                depth[pairs[ch]] -= 1
                if depth[pairs[ch]] < 0:
                    problems.append('%s:%d 多了一個 `%s`' % (rel, no, ch))
                    depth[pairs[ch]] = 0
        # 4. match 分支的同名 var
        m = re.match(r'^(static\s+)?func\s+(\w+)', st)
        if m and indent <= 1:
            cur_func = m.group(2)
            match_stack = []
        # 離開 match 區塊（要在 push 之前判，否則剛 push 的那一層會被自己 pop 掉）
        while match_stack and st and indent <= match_stack[-1][0]:
            match_stack.pop()
        if st.startswith('match ') and st.endswith(':'):
            match_stack.append((indent, {}))
        if match_stack:
            mi, seen = match_stack[-1]
            # 分支體的直接子句在 mi+2；分支標籤在 mi+1
            vm = re.match(r'^var\s+(\w+)', st)
            if vm and indent == mi + 2:
                name = vm.group(1)
                if name in seen and seen[name][0] != indent_branch_id(lines, no, mi):
                    problems.append('%s:%d `match` 兩個分支各宣告 `var %s`（第 %d 行也有）——分支共享作用域，是 parse error'
                                    % (rel, no, name, seen[name][1]))
                elif name not in seen:
                    seen[name] = (indent_branch_id(lines, no, mi), no)
    for k, v in depth.items():
        if v != 0:
            problems.append('%s `%s` 不平衡（差 %d）' % (rel, k, v))

def indent_branch_id(lines, no, mi):
    """這一行屬於哪一個分支：往上找最近的分支標籤（縮排 mi+1、以冒號結尾）。"""
    for i in range(no - 1, -1, -1):
        raw = lines[i]
        ind = len(raw) - len(raw.lstrip('\t'))
        if raw.strip() and ind == mi + 1:
            return i
    return -1

for dp, _, fs in os.walk(ROOT):
    if '.godot' in dp:
        continue
    for f in fs:
        if f.endswith('.gd'):
            scan(os.path.join(dp, f))

if problems:
    print('\n'.join(problems))
    print('\n%d 條' % len(problems))
    sys.exit(1)
print('gd_lint: 0 條')
