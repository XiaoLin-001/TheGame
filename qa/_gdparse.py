"""GDScript 頂層宣告切塊與詞法工具（給 qa/gd_members.py 用）。

不是通用 parser：只處理本專案 Battle.gd 實際用到的語法，遇到不認得的地方寧可報錯。
"""
import re
from dataclasses import dataclass, field

DECL_RE = re.compile(r'^(static\s+func|func|var|const|enum|signal|class)\s+(\w+)')
BANNER_RE = re.compile(r'^#\s*[─═]')


@dataclass
class Chunk:
    kind: str          # func | var | const | enum | signal | static func
    name: str
    doc: list          # 前置註解行（col 0）
    body: list         # 宣告本體行（含縮排內容）
    start: int         # 原檔行號（1-based，宣告行）
    end: int
    dest: str = "Battle"

    def lines(self):
        return self.doc + self.body

    def text(self):
        return "\n".join(self.lines())


def split_chunks(src: str):
    """回傳 (header_lines, chunks)。header = 第一個宣告之前（extends、docstring）。"""
    lines = src.split("\n")
    decl_idx = []
    for i, l in enumerate(lines):
        if l[:1] in ("", " ", "\t", "#", ")", "]", "}"):
            continue
        m = DECL_RE.match(l)
        if m:
            decl_idx.append((i, m.group(1), m.group(2)))
    chunks = []
    header_end = decl_idx[0][0]
    # 往前吃連續的 col-0 註解當 doc
    def doc_start(i, floor):
        j = i
        while j - 1 >= floor and lines[j - 1].startswith("#") and not BANNER_RE.match(lines[j - 1]):
            j -= 1
        return j
    # header：extends / class docstring。doc 往前吃要避開 header 本身
    first_doc = doc_start(header_end, 0)
    header = lines[:first_doc]
    for n, (i, kind, name) in enumerate(decl_idx):
        nxt = decl_idx[n + 1][0] if n + 1 < len(decl_idx) else len(lines)
        floor = i + 1
        # 本體到下一個宣告的 doc 起點之前
        nd = doc_start(nxt, floor) if n + 1 < len(decl_idx) else len(lines)
        # 本體尾端的空白行不算
        e = nd
        while e - 1 > i and lines[e - 1].strip() == "":
            e -= 1
        # 吃掉本體尾端的 banner / 孤立註解（不屬於本體縮排內容者）
        while e - 1 > i and lines[e - 1][:1] == "#" :
            e -= 1
        while e - 1 > i and lines[e - 1].strip() == "":
            e -= 1
        ds = doc_start(i, decl_idx[n - 1][0] + 1 if n > 0 else 0) if n > 0 else first_doc
        doc = lines[ds:i]
        chunks.append(Chunk(kind.replace("  ", " "), name, doc, lines[i:e], i + 1, e))
    return header, chunks


# ── 詞法：把一行/多行程式碼拆成 (種類, 文字) 的 token 序列 ──────────────────

def tokenize(text: str):
    """回傳 token 列表：('str'|'cmt'|'id'|'ws'|'other', s)。字串可跨行。"""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(("cmt", text[i:j]))
            i = j
        elif c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == q:
                    break
                j += 1
            out.append(("str", text[i:j + 1]))
            i = j + 1
        elif c.isalpha() or c == "_" or ord(c) > 127 and c.isalpha():
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            out.append(("id", text[i:j]))
            i = j
        elif c.isdigit():
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in "._"):
                # 小心 1..2 之類不存在於 GDScript；"1.0" 吃掉即可
                j += 1
            out.append(("num", text[i:j]))
            i = j
        elif c in " \t\r\n":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            out.append(("ws", text[i:j]))
            i = j
        else:
            out.append(("other", c))
            i += 1
    return out


KEYWORDS = set("""if elif else for while match break continue pass return class class_name extends is in as
self signal func static const enum var breakpoint preload await yield assert void and or not true false null
PI TAU INF NAN super""".split())


def code_only(text: str) -> str:
    """把字串與註解抽掉（換成空白），給 regex 掃區域變數用。"""
    parts = []
    for k, s in tokenize(text):
        parts.append(" " * len(s) if k in ("str", "cmt") else s)
    return "".join(parts)


def local_names(chunk_text: str):
    """函式內宣告的名稱：var/const/for、函式與 lambda 參數。"""
    code = code_only(chunk_text)
    names = set()
    for m in re.finditer(r'\bvar\s+(\w+)', code):
        names.add(m.group(1))
    for m in re.finditer(r'\bconst\s+(\w+)', code):
        names.add(m.group(1))
    for m in re.finditer(r'\bfor\s+(\w+)', code):
        names.add(m.group(1))
    # 參數：func name(...) 或 func(...)；括號可能巢狀（預設值很少）
    for m in re.finditer(r'\bfunc\s*\w*\s*\(', code):
        i = m.end()
        depth = 1
        j = i
        while j < len(code) and depth:
            if code[j] in "([{":
                depth += 1
            elif code[j] in ")]}":
                depth -= 1
            j += 1
        params = code[i:j - 1]
        d = 0
        cur = ""
        parts = []
        for ch in params:
            if ch in "([{":
                d += 1
            elif ch in ")]}":
                d -= 1
            if ch == "," and d == 0:
                parts.append(cur)
                cur = ""
            else:
                cur += ch
        parts.append(cur)
        for p in parts:
            pm = re.match(r'\s*(\w+)', p)
            if pm:
                names.add(pm.group(1))
    return names


def rewrite(text: str, resolve, locals_: set, self_as=None):
    """逐個「裸識別字」（前一個有效字元不是 '.'）呼叫 resolve(name) → 新文字或 None。

    self_as：把裸 self 換成這個字串（None = 不動）。"""
    toks = tokenize(text)
    out = []
    prev_sig = ""   # 前一個非空白 token 的最後字元
    for k, s in toks:
        if k == "id":
            if prev_sig == ".":
                out.append(s)
            elif s == "self" and self_as is not None:
                out.append(self_as)
            elif s in KEYWORDS or s in locals_:
                out.append(s)
            else:
                r = resolve(s)
                out.append(s if r is None else r)
            prev_sig = s[-1]
        else:
            out.append(s)
            if k not in ("ws", "cmt"):
                prev_sig = s[-1]
    return "".join(out)
