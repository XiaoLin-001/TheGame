# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## ★ 本專案：既有的權威文件優先於本節

**這是 single-context repo，但它已經有一套自己的權威體系。** `CONTEXT.md` 與 `docs/adr/`
目前都不存在，也**沒有要補建**——`docs/00`–`50` 已經在做同一件事，而且是更完整的版本。
探索本 repo 之前該讀的是這些，順序即權威順序（`CLAUDE.md`）：

```
00_CONCEPT.md  ──►  10_GDD.md  ──►  20_ART_DIRECTION.md
（願景與紅線）      （設計唯一權威）    （視覺／動效／音訊唯一權威）
                         │
                         ├──►  30_TECH_DESIGN.md（架構／存檔／測試鉤子／效能）
                         ├──►  40_PRODUCTION_PLAN.md（里程碑／批次／風險）
                         ├──►  50_QA_PLAN.md（測試策略／bug／回歸）
                         └──►  CLAUDE.md（工程慣例；與上述衝突時以上述為準）
```

| 通用的角色 | 本專案對應 |
|---|---|
| `CONTEXT.md`（詞彙表） | `10_GDD.md` §3 的物件模型與系統名詞（節點／導管／網路／滿足率／跨越點／儲槽…） |
| `docs/adr/`（決策紀錄） | `10_GDD.md` §8 的修訂表 ＋ `40_PRODUCTION_PLAN.md` §4 砍案清單 ＋ `CHANGELOG.md` 每批的「取捨與理由」 |

**開工前一律先載入 `game-studio` skill**（`CLAUDE.md` 開頭），再照它的盤點三步走。

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

**本專案**：詞彙表讀 `10_GDD.md` §3。**數值一律寫在 §7，不在程式碼裡即興發明**——
這條比詞彙一致性更硬。

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

**本專案的等價規則**：與 `CLAUDE.md`「鎖定的設計」牴觸時**先問使用者**，不得逕自實作；
與下位文件牴觸時，照權威順序修正下位文件，**當批修完**。
