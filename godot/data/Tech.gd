extends RefCounted
## 科技樹資料表（`10_GDD.md` §3.6、§7.8）。M1 首批 12 節點。
##
## 和 `NodeDefs` 一樣：**數值的唯一來源、純函式、零副作用**。放在 `data/` 而不是
## `sim/` 是因為它是一張表；但 `mods()` 會被模擬層讀，所以同樣禁用 RNG 與系統時間。
##
## ★ **效果一律走 `mods()` 回傳的那一個字典**，不讓各處自己去數 `unlocked` 裡有幾個
## 「導管擴容」。散開來數的話，每加一個節點就要記得改四個地方，而漏掉的那個
## 地方不會報錯——它只會讓玩家買的東西沒有生效。

## 三支路線（§3.6）。後勤支刻意不給數值、只給操作品質。
const PRODUCTION := "production"
const DEFENSE := "defense"
const LOGISTICS := "logistics"

const BRANCHES := [PRODUCTION, DEFENSE, LOGISTICS]

const BRANCH_NAMES := {
	PRODUCTION: "產能",
	DEFENSE: "防務",
	LOGISTICS: "後勤",
}

## ★ 12 節點。`line` 是同一串升級（I → II → III），`tier` 是它在那串裡的第幾階。
##
## **成本＝`50 × tier^1.6`**，tier 是**同一串之內**的階數——不是整支路線的已解鎖數。
## 依據是 §7.8 的成本表本身（50 / 152 / 289 在「導管擴容」與「能量效率」各出現
## 一次，而「採集精煉」與「校準」都是從 50 重新起算）。§7 的數值表是數值權威，
## 表底下那句「n 為該支已解鎖數＋1」複述不出這張表，B1.3 已同步修正那句話。
const NODES := [
	{
		"id": "cap1", "branch": PRODUCTION, "line": "cap", "tier": 1,
		"name": "導管擴容 I", "effect": "cap_bonus", "value": 2.0,
		"desc": "所有導管的**基礎**吞吐 +2（10 → 12），與局內加粗疊加。",
	},
	{
		"id": "cap2", "branch": PRODUCTION, "line": "cap", "tier": 2,
		"name": "導管擴容 II", "effect": "cap_bonus", "value": 2.0,
		"desc": "基礎吞吐再 +2（→ 14）。",
	},
	{
		"id": "cap3", "branch": PRODUCTION, "line": "cap", "tier": 3,
		"name": "導管擴容 III", "effect": "cap_bonus", "value": 2.0,
		"desc": "基礎吞吐再 +2（→ 16）。滿配（含局內 3 級）34。",
	},
	{
		"id": "mine1", "branch": PRODUCTION, "line": "mine", "tier": 1,
		"name": "採集精煉 I", "effect": "extractor_ore", "value": 1.0,
		"desc": "每座採集器 +1 礦砂/秒（6 → 7）。",
	},
	{
		"id": "mine2", "branch": PRODUCTION, "line": "mine", "tier": 2,
		"name": "採集精煉 II", "effect": "extractor_ore", "value": 1.0,
		"desc": "每座採集器再 +1 礦砂/秒（→ 8）。",
	},
	{
		"id": "eff1", "branch": DEFENSE, "line": "eff", "tier": 1,
		"name": "能量效率 I", "effect": "engage_mult", "value": 0.92,
		"desc": "塔的**交戰**耗能 −8%（待機本來就是 0）。",
	},
	{
		"id": "eff2", "branch": DEFENSE, "line": "eff", "tier": 2,
		"name": "能量效率 II", "effect": "engage_mult", "value": 0.92,
		"desc": "交戰耗能再 −8%（連乘，累計 −15.4%）。",
	},
	{
		"id": "eff3", "branch": DEFENSE, "line": "eff", "tier": 3,
		"name": "能量效率 III", "effect": "engage_mult", "value": 0.92,
		"desc": "交戰耗能再 −8%（連乘，累計 −22.1%）。",
	},
	{
		"id": "cal1", "branch": DEFENSE, "line": "cal", "tier": 1,
		"name": "校準 I", "effect": "damage_mult", "value": 1.06,
		"desc": "所有塔傷害 +6%。",
	},
	{
		"id": "cal2", "branch": DEFENSE, "line": "cal", "tier": 2,
		"name": "校準 II", "effect": "damage_mult", "value": 1.06,
		"desc": "所有塔傷害再 +6%（連乘，累計 +12.4%）。",
	},
	{
		"id": "bp1", "branch": LOGISTICS, "line": "bp", "tier": 1,
		"name": "藍圖槽 I", "effect": "blueprint_slots", "value": 1.0,
		"desc": "藍圖槽 +1。（藍圖庫本體排 M2，先把槽位存起來。）",
	},
	{
		"id": "bp2", "branch": LOGISTICS, "line": "bp", "tier": 2,
		"name": "藍圖槽 II", "effect": "blueprint_slots", "value": 1.0,
		"desc": "藍圖槽再 +1。",
	},
]

## `mods()` 的完整骨架。**加法效果預設 0、乘法效果預設 1**——
## 呼叫端一律無條件套用，不寫 `if 有解鎖`（那種分支正是效果會靜靜失效的地方）。
const NO_MODS := {
	"cap_bonus": 0.0,        # 導管基礎 cap 加成
	"extractor_ore": 0.0,    # 每座採集器的礦砂/秒加成
	"engage_mult": 1.0,      # 塔交戰耗能乘數
	"damage_mult": 1.0,      # 塔傷害乘數
	"blueprint_slots": 0.0,  # 藍圖槽（M2 才用得到）
	# ★ 生產節點的產出乘數（B2.7 的等級軸；科技樹本身沒有節點動它）。
	#   骨架列在這裡而不是只在 `Levels.apply()` 裡長出來：呼叫端一律
	#   `float(s.mods["produce_mult"])` 無條件讀，而**沒有等級軸的局**
	#   （測試圖、統一配置榜）走的正是這個 1.0 預設。
	"produce_mult": 1.0,
}

## 乘法效果（連乘）；其餘為加法。
const MULTIPLICATIVE := ["engage_mult", "damage_mult"]


static func of(id: String) -> Dictionary:
	for n: Dictionary in NODES:
		if n["id"] == id:
			return n
	return {}


static func count() -> int:
	return NODES.size()


## 每一階的價（§7.8 的成本表）。`50 × tier^1.6` 是它的來歷，但**表才是權威**：
## 那個式子在 tier 2 要進位（151.57 → 152）、在 tier 3 要捨去（289.98 → 289），
## 沒有任何一種取整方式同時得到表上這兩個數。與其寫一個對不出自己那張表的
## 公式，不如直接列出來——12 個節點只有 3 種價。
const TIER_COST := [50, 152, 289]

static func cost(id: String) -> int:
	var n := of(id)
	if n.is_empty():
		return 0
	return int(TIER_COST[clampi(int(n["tier"]) - 1, 0, TIER_COST.size() - 1)])


## 前置：同一串的前一階。第一階無前置。
static func prereq(id: String) -> String:
	var n := of(id)
	if n.is_empty() or int(n["tier"]) <= 1:
		return ""
	for m: Dictionary in NODES:
		if m["line"] == n["line"] and int(m["tier"]) == int(n["tier"]) - 1:
			return String(m["id"])
	return ""


## 能不能解鎖？回傳原因碼（空字串＝可以），文案在畫面層——同 `sim/Build.gd` 的分工。
const OK := ""
const UNKNOWN := "unknown"
const ALREADY := "already"
const NEEDS_PREREQ := "needs_prereq"
const NO_DATA := "no_data"

static func can_unlock(id: String, unlocked: Array, data: float) -> String:
	if of(id).is_empty():
		return UNKNOWN
	if unlocked.has(id):
		return ALREADY
	var req := prereq(id)
	if req != "" and not unlocked.has(req):
		return NEEDS_PREREQ
	if data < float(cost(id)):
		return NO_DATA
	return OK


## ★ 已解鎖清單 → 效果字典。**全案唯一一個把科技翻成數字的地方。**
##
## 順序無關（加法與連乘都可交換），所以存檔裡 `unlocked` 的排列不影響結果——
## 這是確定性的前提之一：同一份存檔在任何機器上必得同一組 mods。
static func mods(unlocked: Array) -> Dictionary:
	var m: Dictionary = NO_MODS.duplicate()
	for n: Dictionary in NODES:
		if not unlocked.has(n["id"]):
			continue
		var key := String(n["effect"])
		if MULTIPLICATIVE.has(key):
			m[key] = float(m[key]) * float(n["value"])
		else:
			m[key] = float(m[key]) + float(n["value"])
	return m


## ★ B2 硬上限：**全解鎖對戰鬥數值的總增幅 ≤ +35%**（`10_GDD.md` §1 B2）。
##
## 「戰鬥數值」＝防務支的兩串：傷害的增幅、交戰耗能的**降幅**。
## 兩者相加（不是相乘）——它們作用在不同的東西上，乘起來沒有意義，
## 而相加是比較嚴的那個算法，正好也是這條上限該有的態度。
##
## 產能支（導管 cap、採集）不算在內：它們是經濟數值，而且 §7.2 已明文
## 「基礎 cap +2/+2/+2 → 16」是設計好的（`10_GDD.md` §7.2 註）。
static func combat_gain(unlocked: Array) -> float:
	var m := mods(unlocked)
	return (float(m["damage_mult"]) - 1.0) + (1.0 - float(m["engage_mult"]))


## 一支路線的節點（畫面依這個排欄）。
static func of_branch(branch: String) -> Array:
	var out: Array = []
	for n: Dictionary in NODES:
		if n["branch"] == branch:
			out.append(n)
	return out
