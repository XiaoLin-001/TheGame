extends RefCounted
## 建造規則：幾何與合法性（`10_GDD.md` §3.2、§7.2、§7.3）。
##
## **純函式、零副作用**——放在 `sim/` 是刻意的：建造合法性是玩家每 45 秒準備期
## 要用上幾十次的規則，它必須能被測試斷言鎖住，而不是散在 UI 的 if 裡。
## 不引用 autoload，也不回傳中文字串（**回傳原因碼**，文案在遊戲層 `BuildController`）。

const NodeDefs := preload("res://data/NodeDefs.gd")

## 導管基礎吞吐與升級（§7.2）。
const CAP_BASE := 10.0
const CAP_PER_LEVEL := 6.0
const CAP_MAX_LEVEL := 3
const CONDUIT_COST_PER_CELL := 3

## 原因碼。空字串＝合法。
const OK := ""
const OUT_OF_BOUNDS := "out_of_bounds"
const ON_PATH := "on_path"          # 敵人路徑格不可蓋節點（跨越點也不行）
const OCCUPIED := "occupied"
const NEEDS_ORE_CELL := "needs_ore_cell"   # 採集器只能蓋在礦點上
const ORE_CELL_RESERVED := "ore_cell_reserved"  # 礦點只留給採集器
const NOT_STRAIGHT := "not_straight"  # 導管只能走 90°／45°，轉彎要用中繼
const SAME_NODE := "same_node"
const CROSSES_PATH := "crosses_path"  # 導管過路徑只能走跨越點
const DUPLICATE := "duplicate"
const MAX_LEVEL := "max_level"
const NO_ORE := "no_ore"
const NO_ALLOY := "no_alloy"
const LOCKED := "locked"            # 這一關還沒解鎖這種節點（`10_GDD.md` §7.9）
const OVERLAPS := "overlaps"        # 這條線會和既有導管疊在同一排格上（B1.6.1）


## 導管吞吐上限。局內升級每級 +6，上限 3 級 → 28（§7.2）。
##
## `base_bonus` 是**局外科技「導管擴容」**加在基礎值上的（B1.3，§7.2 註）：
## 三級全開 10 → 16，與局內加粗疊加，滿配 34。加在**基礎**而不是乘在總量上，
## 是 B1「加法為主、乘法為輔」的直接落地。
static func conduit_cap(level: int, base_bonus: float = 0.0) -> float:
	return CAP_BASE + base_bonus + CAP_PER_LEVEL * float(clampi(level, 0, CAP_MAX_LEVEL))


## 升到「下一級」的造價：20 × 級數（1→20、2→40、3→60）。
static func upgrade_cost(level: int) -> int:
	return 20 * (level + 1)


## 升到「下一級」的**合金**造價（§7.2）：1 級 0、2 級 20、3 級 50。
##
## ★ 1 級刻意不要合金：加粗到 2 級才是「送滿一台發電機」的門檻，但 1 級是
## B0.3 用來教玩家讀瓶頸的那一步——把它鎖在熔爐後面等於把教學鎖掉。
const UPGRADE_ALLOY := [0, 20, 50]

static func upgrade_alloy(level: int) -> int:
	return 0 if level < 0 or level >= UPGRADE_ALLOY.size() else int(UPGRADE_ALLOY[level])


# ── ★ 局內臨時升級（`10_GDD.md` §4.3、B3.5）────────────────────────
#
# 規格從 M0 就寫著：「局內可用礦砂即時升級**單座建築**（+1 級，最多 3 級），
# **隨局結束消失**」。做到 B3.4 為止，`upgrade()` 只吃導管——這條一直沒有實作。
#
# ── 為什麼「效果」和「耗能」一起長 ────────────────────────────────
# 只加效果的話，升級是**嚴格更好**的：能升就升，那不是決定。
# 兩個一起 ×1.25，效率完全不變——買到的是**集中**：
#   · 同樣的火力用更少的格子（而路徑旁邊安全的格子是稀缺的，退開 2 格才打不到）
#   · 同樣的火力用更少的導管（3 礦砂/格）
# 代價是那一條線要扛得動更大的量：一座 3 級稜鏡要 35 能量/秒，
# 而一條 cap 10 的線送不進去——**集中會把瓶頸推回導管上**。
# 核心取捨（同一份能量餵塔還是餵產線）因此原封不動，而多了一個空間維度。
const NODE_MAX_LEVEL := 3
## 每級 +25%（效果與耗能同步）。3 級 ＝ ×1.75。
const NODE_STEP := 0.25


## 這座建築的**耗能**倍率。與 `steps` 無關——每一級一律 +25%。
##
## ★ B3.8 起這不再同時是效果倍率（效果走 `effect_scale()`）。分開的理由是
## 使用者實玩回報的兩件事：**潮鳴與霜礁升級完全沒用**（它們的效果全在
## `slow`／`armor_break` 上，而只有 `dmg` 被乘過），以及「應該要每次升級有不同效果」。
## **耗能這一半保持原樣**——「效果與耗能一起長」是鎖定設計（§4.3），
## 變的只有「長的是哪一項」。
static func node_scale(level: int) -> float:
	return 1.0 + NODE_STEP * float(clampi(level, 0, NODE_MAX_LEVEL))


# ── ★ 三級各不相同（`10_GDD.md` §4.3，B3.8，使用者指定）───────────────
#
# 每一級加什麼寫在 `NodeDefs` 的 `steps` 裡，四個詞：
#   `power`  出力 ×1.25 累乘（傷害／減速／破甲／回收／產出／發電）
#   `range`  射程 +1 格
#   `rof`    射速 ×1.25 累乘
#   `splash` 濺射半徑 +1 格
#
# 沒有 `steps` 的節點走三個 `power` ＝ B3.5 的原行為，一個數字都不變。
const STEP_POWER := "power"
const STEP_RANGE := "range"
const STEP_ROF := "rof"
const STEP_SPLASH := "splash"
const DEFAULT_STEPS: Array[String] = [STEP_POWER, STEP_POWER, STEP_POWER]


## 這個級數為止，某一種 step 出現了幾次。
static func step_count(type: String, level: int, step: String) -> int:
	var steps: Array = NodeDefs.of(type).get("steps", DEFAULT_STEPS)
	var n := 0
	for i in mini(clampi(level, 0, NODE_MAX_LEVEL), steps.size()):
		if String(steps[i]) == step:
			n += 1
	return n


## 出力倍率（傷害／減速／破甲／回收／產出／發電都乘它）。
static func effect_scale(type: String, level: int) -> float:
	return 1.0 + NODE_STEP * float(step_count(type, level, STEP_POWER))


## 這座塔此刻的射程（格）。**畫面上的圈、交戰判定、光環範圍全部讀這一支**
## ——各讀各的話，玩家會看到一個和實際打得到的範圍不一樣的圈。
static func node_range(type: String, level: int) -> float:
	return (float(NodeDefs.of(type).get("range", 0.0))
		+ float(step_count(type, level, STEP_RANGE)))


## 射速倍率。
static func rof_scale(type: String, level: int) -> float:
	return 1.0 + NODE_STEP * float(step_count(type, level, STEP_ROF))


## 濺射半徑（格）。**沒有濺射的塔永遠是 0**——`splash` 那個 step 只寫給有的那隻，
## 但這條守衛讓「手滑寫給沒有濺射的塔」的後果是無效而不是憑空長出濺射。
static func splash_radius(type: String, level: int) -> float:
	var base := float(NodeDefs.of(type).get("splash", 0.0))
	if base <= 0.0:
		return 0.0
	return base + float(step_count(type, level, STEP_SPLASH))


## 下一級會加什麼（給面板寫在鈕旁邊）。滿級回空字串。
static func next_step(type: String, level: int) -> String:
	if level < 0 or level >= NODE_MAX_LEVEL:
		return ""
	var steps: Array = NodeDefs.of(type).get("steps", DEFAULT_STEPS)
	return String(steps[level]) if level < steps.size() else ""


## 升到「下一級」的礦砂造價 ＝ **造價 × (級數+1) ÷ 2**（半價、全價、一倍半）。
##
## 三級全升的總價是造價的 3 倍，換到 ×1.75——**比多蓋兩座還貴而且更弱**。
## 那是刻意的：升級買的是格子與導管，不是數值效率。划算與否由地形決定，
## 而地形是關卡設計的主要刻度尺（§7.7）。
static func node_upgrade_cost(base_cost: int, level: int) -> int:
	return int(ceil(float(base_cost) * float(level + 1) * 0.5))


## 導管走向合法嗎？只有水平、垂直、正 45°（§7.2）。
## 這條限制正是「中繼＝轉折器」的存在理由，不是簡化。
static func is_straight(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if d == Vector2i.ZERO:
		return false
	return d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y)


## 導管實際佔用的格（含頭尾兩個節點格）。走向不合法時回空陣列。
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not is_straight(a, b):
		return cells
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	var step := Vector2i(signi(d.x), signi(d.y))
	for i in range(steps + 1):
		cells.append(a + step * i)
	return cells


## 導管造價 = 長度(格) × 3 礦砂（§7.2）。長度不含起點那一格。
static func conduit_cost(a: Vector2i, b: Vector2i) -> int:
	if not is_straight(a, b):
		return 0
	var d := b - a
	return maxi(absi(d.x), absi(d.y)) * CONDUIT_COST_PER_CELL


## 節點放置合法性。
## `occupied`：`{Vector2i: true}`，已有節點的格。
static func can_place(sets: Dictionary, occupied: Dictionary, type: String, cell: Vector2i) -> String:
	# ★ 關卡解鎖（B1.2）。**空陣列＝不限制**（測試圖與沙盤走這條）。
	# 規則放在這裡而不是 UI：畫面上不畫那顆鈕只是一半，藍圖展開（B2.3）與
	# 重播都會繞過 UI 直接呼叫建造——鎖不在規則層，它就不是規則。
	var unlocked: Array = sets.get("unlocked", [])
	if not unlocked.is_empty() and not unlocked.has(type):
		return LOCKED
	var size: Vector2i = sets.get("size", Vector2i.ZERO)
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return OUT_OF_BOUNDS
	# 路徑格禁節點——**跨越點也禁**（橋上可鋪導管，不可蓋節點，§3.2）。
	if (sets.get("path", {}) as Dictionary).has(cell):
		return ON_PATH
	if occupied.has(cell):
		return OCCUPIED
	var on_ore: bool = (sets.get("ore", {}) as Dictionary).has(cell)
	if type == "extractor" and not on_ore:
		return NEEDS_ORE_CELL
	# 礦點被中繼佔掉是無法挽回的手滑（拆了才能重蓋），直接擋下。
	if type != "extractor" and on_ore:
		return ORE_CELL_RESERVED
	return OK


## 導管合法性。兩端都必須是既有節點的格（呼叫端保證），中間不得跨路徑，
## **除非那一格是跨越點**（§3.2：橋是路徑上唯一可鋪導管處）。
##
## ★ **不得和既有導管疊在同一排格上**（B1.6.1，使用者回報「有破圖、有重疊」）。
##
## 兩條線**共用 2 格以上**就是疊在一起：畫面上是兩條線畫在同一排像素、
## 兩排流動珠交錯成一團，而沒有任何辦法看出那裡有兩條線；`conduit_near()`
## 的距離判定在它們之間也只能任選一條（加粗會加到你沒指的那一條）。
##
## **共用 1 格是合法的**——那是交叉或在同一個節點分岔，本來就要允許。
##
## 這條規則刻意**不是**「不准穿過節點」：從一個節點旁邊經過而不接它，
## 在流量網路裡是一個真的戰術選擇（接上去就得和它共用那條線的 cap）。
## 被禁掉的只有「看起來是一條線、其實是兩條」這件事。
##
## `existing_cells` 是既有導管的 `cells` 陣列；省略就是不檢查這一條
## （純幾何的呼叫端不需要它）。
static func can_connect(
	sets: Dictionary, existing: Dictionary, a: Vector2i, b: Vector2i,
	existing_cells: Array = []
) -> String:
	if a == b:
		return SAME_NODE
	if not is_straight(a, b):
		return NOT_STRAIGHT
	if existing.has(conduit_key(a, b)):
		return DUPLICATE
	var path: Dictionary = sets.get("path", {})
	var crossings: Dictionary = sets.get("crossings", {})
	var mine: Dictionary = {}
	for c: Vector2i in line_cells(a, b):
		mine[c] = true
		if c == a or c == b:
			continue
		if path.has(c) and not crossings.has(c):
			return CROSSES_PATH
	for cells: Array in existing_cells:
		var shared := 0
		for c: Vector2i in cells:
			if mine.has(c):
				shared += 1
				if shared >= 2:
					return OVERLAPS
	return OK


## 導管的無向鍵——同兩點之間只能有一條線，A→B 與 B→A 視為同一條。
static func conduit_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	return "%d,%d-%d,%d" % [lo.x, lo.y, hi.x, hi.y]
