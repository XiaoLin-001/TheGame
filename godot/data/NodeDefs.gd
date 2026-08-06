extends RefCounted
## 節點資料表（`10_GDD.md` §7.3）。**數值的唯一來源**——不在程式碼裡即興發明。
##
## 不宣告 `class_name`：一律以路徑 `preload`。`--script` 模式（測試）不保證
## global class 可用，而資料表必須連測試都拿得到（`50_QA_PLAN.md` §2）。
##
##
## **塔也在這張表裡**（§7.4）。它們是節點——會被建造、會被連線、會吃電、會被打壞，
## 每一條規則都和其他節點共用同一套程式碼路徑。拆成第二張表只會讓
## `can_place` / `preview_place` / 存檔 / 渲染各自多一個分支。
## 塔專屬欄位：`tower` / `engage_power` / `range` / `rof` / `dmg` / `dmg_type`
## ／`pierce` / `slow` / `armor_break` / `reclaim`。

## 可建造的節點。`core` 不在此列——它由地圖宣告，玩家蓋不出來。
##
## ⚠ **這張表是「遊戲裡存在哪些節點」，不是「這一局蓋得出哪些」**（B2.4）。
## 後者要問 `data/Roster.gd` 的 `buildable()`——招募來的三隻不在每個人手上。
const BUILDABLE := [
	"extractor", "generator", "smelter", "relay", "silo",
	"anchor", "prism", "knell", "reclaimer", "breaker",
	"longcall", "frostreef", "ballast",
]

const DEFS := {
	"extractor": {
		"name": "採集器",
		"cost": 40,
		"hp": 60.0,
		"ore_out": 6.0,      # 礦砂/秒（「只能蓋在礦點上」寫在 `sim/Build.can_place`）
	},
	"generator": {
		"name": "發電機",
		"cost": 60,
		"hp": 50.0,
		"ore_in": 4.0,       # 礦砂/秒
		"power_out": 20.0,   # 能量/秒（依礦砂滿足率線性縮放）
	},
	"smelter": {
		"name": "熔爐",
		"cost": 80,
		"hp": 70.0,
		"ore_in": 8.0,       # 礦砂/秒
		"power_in": 10.0,    # 能量/秒——**待機也吃**，這是它與塔最大的不同
		"alloy_out": 2.0,    # 合金/秒（乘上礦砂與能量兩個滿足率中較低的那一個）
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
	"breaker": {
		"name": "碎浪",
		"cost": 140,
		"alloy_cost": 60,       # ★ 第一個要合金的東西（另一個是導管 2/3 級）
		"hp": 60.0,
		"tower": true,
		"engage_power": 12.0,   # 三座錨的電。只在敵人擠成一團時值這個價。
		"range": 5.0,
		"rof": 0.6,
		"dmg": 22.0,
		"dmg_type": "physical",
		# 濺射半徑（格）。主目標仍是「最前」那一隻，濺射以**它所在的格**為圓心，
		# 所以實際打到的是「領頭那隻 ＋ 它後面 2.5 格內的」——半徑要涵蓋
		# 一整段隊列的**後半**，2.5 是照第 5 波最擠的間距（0.6 格）反推的。
		# 不另寫幾何：`Combat.in_range_indices()` 本來就是「這個圓內有誰」。
		"splash": 2.5,
	},

	# ── 招募專屬的三隻（§7.13，B2.4）─────────────────────────────────
	# 三隻**全部只用既有的欄位**（`range`／`rof`／`dmg`／`slow`／`splash`…），
	# `sim/Combat.gd` 一行都沒改。招募是外層系統，它不該是新戰鬥規則的載體——
	# 那會讓「抽到才玩得到的機制」變成事實，而 B6 說所有東西都要能靠遊玩取得。
	#
	# 三隻都**不出現在戰役**（戰役的建造欄是各關明列的，§7.9），所以 B1.2 校準過的
	# 五關難度不受影響。它們活在無盡與每日的自由配置榜。
	"longcall": {
		"name": "長哨",
		"cost": 180,
		"hp": 60.0,
		"tower": true,
		# 每瓦 2.28 dps，介於稜鏡（0.75）與錨（5.4）之間。**買的是覆蓋範圍不是輸出**：
		# 射程 12 在無盡的大圖上一座蓋掉一個象限，也是唯一夠得到漏網之魚的塔。
		"engage_power": 8.0,
		"range": 12.0,
		"rof": 0.35,
		"dmg": 52.0,
		"dmg_type": "physical",
	},
	"frostreef": {
		"name": "霜礁",
		"cost": 200,
		"alloy_cost": 40,
		"hp": 60.0,
		"tower": true,
		# 潮鳴的極端版：減速 0.65（vs 0.4）、射程 3（vs 5）、電費 1.8 倍、**沒有破甲**。
		# 光環取最強不疊加（§7.4），但減速與破甲是**各自取最大**——所以霜礁＋潮鳴
		# 是一個真的組合技，而兩座都要吃電，峰值電力仍然是唯一的約束。
		"engage_power": 16.0,
		"range": 3.0,
		"rof": 0.0,
		"dmg": 0.0,
		"dmg_type": "none",
		"slow": 0.65,
	},
	"ballast": {
		"name": "定潮",
		"cost": 240,
		"alloy_cost": 100,
		# 90（其餘塔 60）。它是壓在路邊撐的那一座，撐不住就沒有存在的理由。
		"hp": 90.0,
		"tower": true,
		# ★ 唯一一隻**用礦砂與合金買電費折扣**的塔：每瓦 8.0 dps（錨 5.4），
		# 但造價是錨的 4.8 倍**再加 100 合金**——而合金要一座熔爐（8 礦砂/秒 ＋
		# 待機 10 能量/秒）。「便宜的電」是拿一整條產線換來的，取捨沒有消失，
		# 只是從峰值電力挪到了經濟。這正是電網已經拉到極限之後唯一還能加的火力。
		"engage_power": 3.0,
		"range": 4.0,
		"rof": 1.0,
		"dmg": 24.0,
		"dmg_type": "physical",
	},
}

## 優先權預設值（1–5，依**節點類型**，`10_GDD.md` §3.1）。
const DEFAULT_PRIORITY := {
	"generator": 4,  # 燃料優先於入帳（礦砂網）
	"anchor": 3,     # 能量網：塔預設搶得贏儲槽充能——波次期先餵防線
	"prism": 3,
	"knell": 3,
	"reclaimer": 3,
	"breaker": 3,
	"longcall": 3,
	"frostreef": 3,
	"ballast": 3,
	# ★ 熔爐預設 2：**它搶不贏塔，但搶得贏儲槽充能**。這一格就是「餵塔還是餵
	# 生產線」的預設答案，而且是玩家隨時拉得動的——拉到 4 就是「這一波我賭
	# 產能，塔慢一點沒關係」。預設站在防線那邊，因為輸掉核心是不可逆的。
	"smelter": 2,
	"silo": 2,       # 充能搶不贏塔，這是刻意的
	"core": 1,
	"relay": 1,
	"extractor": 1,
}

## 優先權面板的列與**恆定順序**（`10_GDD.md` §3.1：滑桿恆在同一位置，
## 操作負擔不隨建築數量成長）。中繼與採集器沒有需求，給它們滑桿只是假選項。
const PRIORITY_ROWS := [
	"generator", "smelter", "core", "silo",          # 生產側
	"anchor", "prism", "knell", "reclaimer", "breaker",  # 防線側
]
## 面板換欄的位置＝上面那條註解的分界。**兩欄不是排版，是這個面板的整句話**：
## 左欄是生產線、右欄是防線，而玩家要做的決定就是把電從左邊挪到右邊或反過來。
const PRIORITY_SPLIT := 4

## ★ 新角色併進既有的那一列，**滑桿數量永遠是 `PRIORITY_ROWS` 那九條**（B2.4）。
##
## 為什麼需要這個表：`10_GDD.md` §3.1 鎖死「5–8 條滑桿恆在同一位置」，理由是
## **不可暫停的戰術動作必須是一個手勢，操作負擔不得隨建築數量成長（R-1）**。
## 一隻角色一條滑桿的話，M3 的 24 隻角色就是 28 條滑桿——那個面板已經不是
## 一個手勢，是一份表單。所以優先權的單位是**角色的角色**（單體物理／光環／
## 穿透…），不是資料表上的鍵。
##
## 只影響 UI 與預設值：`FlowNetwork` 仍然逐 type 讀 `priorities[type]`，
## 面板只是把同一列的幾個 type 一起推。
const PRIORITY_GROUP := {
	"longcall": "anchor",     # 單體物理
	"ballast": "anchor",      # 單體物理
	"frostreef": "knell",     # 光環
}


## 這個 type 的優先權由哪一列的滑桿控制。沒有併列的就是它自己。
static func priority_row(type: String) -> String:
	return String(PRIORITY_GROUP.get(type, type))


## 這一列的滑桿要一起推哪幾個 type。
static func priority_members(row: String) -> Array[String]:
	var out: Array[String] = [row]
	for type: String in PRIORITY_GROUP:
		if String(PRIORITY_GROUP[type]) == row:
			out.append(type)
	return out

const PRIORITY_MIN := 1
const PRIORITY_MAX := 5


static func of(type: String) -> Dictionary:
	return DEFS.get(type, {})


static func label(type: String) -> String:
	return String(of(type).get("name", type))


static func cost(type: String) -> int:
	return int(of(type).get("cost", 0))


## 合金造價。**大多數節點是 0**——合金是高階貨幣，不是第二條普遍稅（§7.4）。
static func alloy_cost(type: String) -> int:
	return int(of(type).get("alloy_cost", 0))


static func hp(type: String) -> float:
	return float(of(type).get("hp", 1.0))
