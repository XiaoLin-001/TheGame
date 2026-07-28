extends RefCounted
## 節點資料表（`10_GDD.md` §7.3）。**數值的唯一來源**——不在程式碼裡即興發明。
##
## 不宣告 `class_name`：一律以路徑 `preload`。`--script` 模式（測試）不保證
## global class 可用，而資料表必須連測試都拿得到（`50_QA_PLAN.md` §2）。
##
## 熔爐 Smelter 是 M1（B1.1 第三資源）才進來的，這裡先不列。
##
## **塔也在這張表裡**（§7.4）。它們是節點——會被建造、會被連線、會吃電、會被打壞，
## 每一條規則都和其他節點共用同一套程式碼路徑。拆成第二張表只會讓
## `can_place` / `preview_place` / 存檔 / 渲染各自多一個分支。
## 塔專屬欄位：`tower` / `engage_power` / `range` / `rof` / `dmg` / `dmg_type`
## ／`pierce` / `slow` / `armor_break` / `reclaim`。

## 資源鍵。解算器一次只解一種（`sim/FlowNetwork.gd`）。
const ORE := "ore"
const POWER := "power"

## 可建造的節點。`core` 不在此列——它由地圖宣告，玩家蓋不出來。
const BUILDABLE := [
	"extractor", "generator", "relay", "silo",
	"anchor", "prism", "knell", "reclaimer",
]

const DEFS := {
	"extractor": {
		"name": "採集器",
		"cost": 40,
		"hp": 60.0,
		"ore_out": 6.0,      # 礦砂/秒
		"on_ore_only": true, # 只能蓋在礦點上
	},
	"generator": {
		"name": "發電機",
		"cost": 60,
		"hp": 50.0,
		"ore_in": 4.0,       # 礦砂/秒
		"power_out": 20.0,   # 能量/秒（依礦砂滿足率線性縮放）
	},
	"relay": {
		"name": "中繼",
		"cost": 15,
		"hp": 30.0,
		# 分流／合流／**轉折**。導管只能走 90°/45°，轉彎就靠它（§7.2）。
	},
	"silo": {
		"name": "儲槽",
		"cost": 50,
		"hp": 80.0,
		"capacity": 300.0,   # 能量緩衝
	},
	"core": {
		"name": "核心",
		"cost": 0,
		"hp": 1000.0,
		# 礦砂銀行：demand = max(0, 全網供給 − 其他消費者需求)（§7.3）
	},

	# ── 塔（§7.4）────────────────────────────────────────────────────
	# `engage_power` 是**射程內有敵人時**的每秒耗能；`power_in`（待機）刻意
	# 不寫＝0。這一欄就是全案的心臟：同一份能量，餵塔還是餵生產線。
	"anchor": {
		"name": "錨",
		"cost": 50,
		"hp": 60.0,
		"tower": true,
		"engage_power": 4.0,
		"range": 4.0,
		"rof": 1.2,
		"dmg": 18.0,
		"dmg_type": "physical",
	},
	"prism": {
		"name": "稜鏡",
		"cost": 120,
		"hp": 60.0,
		"tower": true,
		"engage_power": 20.0,   # 一座稜鏡開火 ≈ 五座錨。儲槽因此成為硬需求。
		"range": 9.0,
		"rof": 0.5,
		"dmg": 30.0,
		"dmg_type": "energy",
		"pierce": true,
	},
	"knell": {
		"name": "潮鳴",
		"cost": 90,
		"hp": 60.0,
		"tower": true,
		"engage_power": 9.0,
		"range": 5.0,
		"rof": 0.0,             # 不開火。證明「不造成傷害的建築也值得佔用電力」。
		"dmg": 0.0,
		"dmg_type": "none",
		"slow": 0.4,
		"armor_break": 0.25,
	},
	"reclaimer": {
		"name": "回收者",
		"cost": 100,
		"hp": 60.0,
		"tower": true,
		"engage_power": 7.0,
		"range": 5.0,
		"rof": 0.9,
		"dmg": 14.0,
		"dmg_type": "physical",
		"reclaim": 0.6,         # 射程內任何死亡 → 價值 ×0.6 ×5（匯率）為能量
		# ★ 回收緩衝的上限。**沒有上限的話回收者就是第二座儲槽**——一座沒有
		# 容量欄位、沒有造價、也沒被列進優先權面板的儲槽，那正是「無全域
		# 能量池」要擋掉的東西。100 剛好裝得下單次最大的一筆回收（甲殼 90），
		# 所以一發大的永遠不會溢流，一連串的才會。滿了就丟棄：推不出去的電
		# 本來就沒人用得到。
		"reclaim_buffer": 100.0,
	},
}

## 優先權預設值（1–5，依**節點類型**，`10_GDD.md` §3.1）。
const DEFAULT_PRIORITY := {
	"generator": 4,  # 燃料優先於入帳（礦砂網）
	"anchor": 3,     # 能量網：塔預設搶得贏儲槽充能——波次期先餵防線
	"prism": 3,
	"knell": 3,
	"reclaimer": 3,
	"silo": 2,       # 充能搶不贏塔，這是刻意的
	"core": 1,
	"relay": 1,
	"extractor": 1,
}

## 優先權面板的列與**恆定順序**（`10_GDD.md` §3.1：滑桿恆在同一位置，
## 操作負擔不隨建築數量成長）。中繼與採集器沒有需求，給它們滑桿只是假選項。
const PRIORITY_ROWS := ["generator", "core", "silo", "anchor", "prism", "knell", "reclaimer"]

const PRIORITY_MIN := 1
const PRIORITY_MAX := 5


static func of(type: String) -> Dictionary:
	return DEFS.get(type, {})


static func label(type: String) -> String:
	return String(of(type).get("name", type))


static func cost(type: String) -> int:
	return int(of(type).get("cost", 0))


static func hp(type: String) -> float:
	return float(of(type).get("hp", 1.0))
