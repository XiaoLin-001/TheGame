# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

---

## 本專案註記

用預設字串（2026-07-27 拍板）——這是新建的追蹤器，沒有舊標籤要相容。

**`ready-for-agent` 在本專案有一條額外的門檻**：`docs/50_QA_PLAN.md` §0.1 規定
**樂趣由使用者本人判、agent 只判程式碼完整性與可讀性**。凡是判準寫「好不好玩」
「陌生人能不能上手」的 issue，一律 `ready-for-human`，**不得**標 `ready-for-agent`
（同 `40_PRODUCTION_PLAN.md` 的 R-14）。
