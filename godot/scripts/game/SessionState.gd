extends RefCounted
## 當前一局的狀態擁有者（`30_TECH_DESIGN.md` §2.3）。**局結束即銷毀，不持久化。**
##
## 這裡**只有狀態與查詢，沒有規則**——建造規則在 `sim/Build.gd`（純函式），
## 花錢與扣款在 `game/BuildController.gd`，每 tick 的解算在 `game/BattleController.gd`。
##
## 畫面層以**引用**取得本物件，不得持有副本；容器一律原地變更。

const Maps := preload("res://data/Maps.gd")
## `sim/` 一律以路徑 preload，不靠 global class name——
## `--script` 模式不載入 autoload，模擬層必須自足（`50_QA_PLAN.md` §2）。
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tech := preload("res://data/Tech.gd")
const Levels := preload("res://data/Levels.gd")

## 地圖原始資料與它的集合形式（查詢用，每局只轉一次）。
var map: Dictionary = {}
var sets: Dictionary = {}

## ★ 局外科技解算後的效果（B1.3、`data/Tech.gd`）。**開局時算一次就固定**——
## 科技是局外成長，局內不會變；每 tick 重讀存檔只會讓模擬多一條對外依賴，
## 而且那條依賴不進 `state_hash()`，重播就會對不上。
##
## 預設是 `Tech.NO_MODS`（全 1 / 全 0），所以**任何沒傳 mods 的呼叫端行為完全不變**
## ——測試、沙盤、示範佈局都走這條，B1.3 之前的數字因此逐項不動。
var mods: Dictionary = Tech.NO_MODS.duplicate()

## 帳上礦砂。**只有送達核心的礦砂才進得來**（`10_GDD.md` §7.3）。
var ore: float = 0.0
## 帳上合金。**同一條規則**：熔爐產的合金要經導管送達核心才入帳（§7.3）。
## 起始一律 0——沒有地圖參數，第一塊合金必然來自玩家自己蓋的熔爐。
var alloy: float = 0.0

## `{id, type, cell, hp, charge, cd, buffer}`。核心也是一個節點（type = "core"）。
## `cd` 是塔的射速累加器、`buffer` 是回收者尚未推進電網的回收能量——
## 兩個都給所有節點免得到處判型別，一個 float 比一個分支便宜。
var nodes: Array[Dictionary] = []
## `{id, a, b, level, hp}`。`a`→`b` 有向；儲槽那條線在解算時自動展開成雙向。
var conduits: Array[Dictionary] = []

## 依**節點類型**的優先權（`10_GDD.md` §3.1）。B0.5 起玩家可在面板拉動。
var priorities: Dictionary = {}

var tick_count: int = 0
var core_id: int = -1

# ── 戰鬥累計（B0.5）──────────────────────────────────────────────────
var kills: int = 0
## 全域擊殺回收累計（礦砂）。已經算進 `ore`，這裡另記一份給頂欄與結算。
var salvage_total: float = 0.0
## 回收者回收的能量累計。**注入電網的量**，不是瞬間到帳的量。
var reclaimed_total: float = 0.0
## 送達核心的礦砂累計。局末的**產能積分**分子（`10_GDD.md` §7.6）——
## 與頂欄 `▲/秒` 同一個口徑：採得出來但運不回去的不算產能。
var delivered_total: float = 0.0
## 送達核心的合金累計。**不併進 `delivered_total`**：產能積分的口徑是礦砂
## （§7.6 已定），把合金摻進去等於偷偷改掉一個已經算過分數的公式。
var alloy_total: float = 0.0
## 本 tick 的開火線 `[{from, to}]`——純渲染用，每 tick 重寫。
var shots: Array = []
## ★ 碎片爆（B1.6）。`{at: Vector2, kind: String, seed: int, life: int, ttl: int}`
## ——`at` 是**格座標的浮點值**（整數＝格中心；模擬層不碰像素）、
## `kind` 是 `chaos`（敵人消散）或
## `order`（建築破裂）、`seed` 決定碎片方向（零 RNG，由來源 id 給）。
##
## **純渲染，和 `shots` 一樣不進 `state_hash()`。** 由模擬層在擊殺與清殘骸時
## 生成是刻意的：那兩個時刻只有模擬知道，而渲染層看到的是「敵人不見了」——
## 從「不見了」反推爆炸位置就得在畫面層重建一份死亡判定。
var bursts: Array = []
## ★ 屏障擋格（B2.1d）。**純渲染**，和 `shots`／`bursts` 一樣不進 `state_hash()`。
var shields: Array = []

# ── 敵潮與時間流（B0.4）──────────────────────────────────────────────
## `prep` 準備期／`wave` 波次中／`lost` 核心已毀／`won` 波次表跑完。
## **沒有 `paused`**：純即時不可暫停是鎖定的設計（`10_GDD.md` B5）。
var phase: String = "prep"
## 當前這一波的提前召喚倍率（按下當下鎖定，§7.6）。自然開波為 1.0。
var wave_bonus: float = 1.0
## 提前召喚折算成研究數據的累計加成（`Σ 10 × (倍率 − 1)`，§7.6）。
var bonus_data: float = 0.0
## 已完成的波次數。`wave_index` 同時是「下一波」的索引（0-based）。
var wave_index: int = 0
## 本階段已經過的秒數。
var phase_time: float = 0.0
## 準備期快進倍率（`10_GDD.md` §7.1 `FAST_FORWARD_RATE = 4`）。
## **戰鬥期恆為 1**——可跳過空等，不可加速戰鬥（B5）。
var speed_mult: int = 1
## 本波敵人的血量倍率（無盡模式，`10_GDD.md` §7.10）。戰役恆為 1.0。
## 在 `start_wave` 鎖給那一波——出場中途改倍率會讓同一波的敵人血量不一致。
var hp_mult: float = 1.0
## `{id, type, progress, hp}`。`progress` 單位是路徑格。
var enemies: Array[Dictionary] = []
## 本波尚未出場的：`[{type, at}]`，`at` 是距波次開始的秒數。
var spawn_queue: Array = []
## 敵人路徑（有序格）。每局算一次——它每 tick 都要用。
var path: Array = []

## 最近一次解算的顯示值（**單位/秒**，供渲染與頂欄讀取）。
## `conduit_flow` 依 conduit 索引；其餘依 node id。
var rates: Dictionary = {
	"ore_in": 0.0,       # 本 tick 實際入帳速率
	"alloy_in": 0.0,     # 本 tick 實際入帳的合金速率
	"power_supply": 0.0,
	"power_demand": 0.0,
	"silo_charge": 0.0,
	"silo_capacity": 0.0,
	"conduit_flow": {},   # {conduit id: 該線的最大資源流率}（線寬與顏色用）
	"conduit_net": {},    # {conduit id: Vector3(礦砂, 能量, 合金) 淨流率，沿 a→b 為正}（流動珠用）
	"satisfaction": {},   # {node id: 0..1}
	"engaged": 0,         # 本 tick 交戰中的塔座數（＝正在吃電的那些）
	"node_state": {},     # {node id: NORMAL/STARVED/OVERFLOW}（三態徽章，GDD §3.1）
}

## 節點三態（`10_GDD.md` §3.1）。`NORMAL` 不畫任何東西——徽章是例外標記。
##
## ★ `STARVED_POWER` 是 B2.4.8 從 `STARVED` 分出來的（遊玩測試 P2-1）。
##   舊版一律掛同一個徽章，於是地圖上唯一指出瓶頸的元素**說得出「誰在挨餓」，
##   說不出「餓的是礦砂還是電」**——而全案的核心命題就是峰值電力（§3.1），
##   「我現在缺的是電還是礦」是玩家每分鐘都要答的問題。
##
##   **新值接在最後**，既有的 `NORMAL/STARVED/OVERFLOW` 數值不動；
##   凡是問「有沒有在挨餓」的地方一律用 `is_starved()`，不要自己寫 `== STARVED`
##   ——那種寫法在新增第四態的當下就會安靜地漏掉一半的節點。
enum { NORMAL, STARVED, OVERFLOW, STARVED_POWER }


## 這個狀態算不算「在挨餓」（兩種缺料都算）。
static func is_starved(state: int) -> bool:
	return state == STARVED or state == STARVED_POWER

var _next_id: int = 1


## `unlocked` ＝ 這一關可蓋的節點類型（`10_GDD.md` §7.9）。
## **空陣列＝不限制**——測試圖「淺灘」與沙盤「靜水」走的是這條。
## ★ `levels` ＝ 存檔的 `levels` 那一格（B2.7 的等級軸）。**預設空字典＝零級**，
## 所以既有的呼叫端（測試圖、沙盤、全部測試）一個字都不必改，而且拿到的是 ×1.0。
##
## 傳的是那一格而不是整份存檔：第三、第四個參數合起來是**這一局所有局外成長的
## 唯一入口**（`sim/Daily.gd` 的說明），遞整份存檔進來等於在旁邊開一扇沒人看的門。
func setup(
	map_def: Dictionary, unlocked: Array = [], tech: Array = [], levels: Dictionary = {}
) -> void:
	map = map_def
	sets = Maps.to_sets(map_def)
	sets["unlocked"] = unlocked
	mods = Levels.apply(Tech.mods(tech), levels)
	path = Maps.path_of(map_def)
	ore = float(map_def.get("start_ore", 0))
	priorities = NodeDefs.DEFAULT_PRIORITY.duplicate()
	core_id = add_node("core", map_def.get("core", Vector2i.ZERO))


func core() -> Dictionary:
	for n: Dictionary in nodes:
		if int(n["id"]) == core_id:
			return n
	return {}


func core_hp() -> float:
	var c := core()
	return 0.0 if c.is_empty() else float(c["hp"])


## 本關宣告的準備期。**是關卡參數不是隱藏係數**——計時器就在畫面上（§7.7）。
func prep_time() -> float:
	return float(map.get("prep_time", 45.0))


func add_node(type: String, cell: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	nodes.append({
		"id": id,
		"type": type,
		"cell": cell,
		"hp": NodeDefs.hp(type),
		"charge": 0.0,
		"cd": 0.0,
		"buffer": 0.0,
	})
	return id


func add_conduit(a: Vector2i, b: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	# `cells` 在建造時算一次就存著：敵潮每 tick 要拿它做破壞判定，
	# 每次重算等於把 O(敵人 × 導管) 再乘上一個長度。
	conduits.append({
		"id": id, "a": a, "b": b, "level": 0, "hp": 40.0,
		"cells": Build.line_cells(a, b),
	})
	return id


func add_enemy(type: String) -> int:
	var id := _next_id
	_next_id += 1
	enemies.append({
		"id": id,
		"type": type,
		"progress": 0.0,
		"hp": float(Enemies.of(type).get("hp", 1.0)) * hp_mult,
	})
	return id


## 移除一個節點，連同所有碰到它的導管（斷了的線留著只會騙人）。
func remove_node_at(cell: Vector2i) -> void:
	for i in range(nodes.size() - 1, -1, -1):
		if nodes[i]["cell"] == cell:
			nodes.remove_at(i)
	for i in range(conduits.size() - 1, -1, -1):
		var c: Dictionary = conduits[i]
		if c["a"] == cell or c["b"] == cell:
			conduits.remove_at(i)


func remove_conduit(index: int) -> void:
	if index >= 0 and index < conduits.size():
		conduits.remove_at(index)


func node_at(cell: Vector2i) -> Dictionary:
	for n: Dictionary in nodes:
		if n["cell"] == cell:
			return n
	return {}


func occupied() -> Dictionary:
	var d: Dictionary = {}
	for n: Dictionary in nodes:
		d[n["cell"]] = true
	return d


## 既有導管佔用的格，供「不得疊在一起」檢查用（B1.6.1）。
func conduit_cells() -> Array:
	var out: Array = []
	for c: Dictionary in conduits:
		out.append(c["cells"])
	return out


func conduit_keys() -> Dictionary:
	var d: Dictionary = {}
	for c: Dictionary in conduits:
		d[Build.conduit_key(c["a"], c["b"])] = true
	return d


## ★ 點到哪條導管上？（拆除／升級要用）
##
## **距離判定，不是格子成員判定**（B1.2.1，使用者回報「45 度的線沒辦法加粗」）。
## 舊版比對「點到的格是不是這條線的中間格」，於是：
##   ① 兩個**對角相鄰**的節點之間那條 45° 線**一個中間格都沒有** → 永遠點不到。
##      而 45° 線在實戰佈局裡多半就是這種一格長的（稜鏡菱形的四條邊全是）。
##   ② 就算有中間格，45° 的線只從那些格的**正中央**穿過去，滑鼠往垂直方向
##      偏半格就掉進一個不屬於這條線的格；水平線則整排格子都算命中。
##      同一條線，畫得斜一點就變難點——那不是規則，是實作漏出來的。
##
## `p` 用**格為單位的浮點座標**（整數＝格中心），`sim/` 不碰像素。
## 呼叫端給得越精確，多條線擠在同一個節點時就越不會選錯。
func conduit_near(p: Vector2, radius: float = 0.5) -> int:
	var best := -1
	var best_d := radius
	for i in conduits.size():
		var c: Dictionary = conduits[i]
		var d := _point_to_segment(p, Vector2(c["a"]), Vector2(c["b"]))
		if d <= best_d:
			best_d = d
			best = i
	return best


## 格為單位的點到線段距離。
static func _point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## ★ 局狀態雜湊（`30_TECH_DESIGN.md` §2.4）。**同一組 `(seed, ops)` 跑兩次必得同一個字串。**
##
## 這是每日挑戰雙榜（B2.2）、重播、可驗證榜單的地基：沒有它，「同種子同地圖」
## 就只是一句宣稱。`determinism_test` 拿它當唯一判準。
##
## 兩條紀律：
##   ① **遍歷一律依 id 排序**——Dictionary 與 Array 的順序不是狀態的一部分，
##      拿插入順序當狀態會讓「刪一個節點再蓋回來」變成不同的局。
##   ② **只雜湊權威狀態，不雜湊 `rates`**——後者是同一份狀態推導出來的，
##      放進來只會讓同一個缺陷被記兩次，卻讓雜湊看起來更可靠。
func state_hash() -> String:
	var parts := PackedStringArray([
		"tick=%d" % tick_count,
		"phase=%s/%s/%s" % [phase, wave_index, phase_time],
		"ore=%s/%s" % [ore, alloy],
		"tally=%s/%s/%s/%s/%s" % [
			kills, salvage_total, reclaimed_total, delivered_total, alloy_total
		],
		"bonus=%s/%s" % [wave_bonus, bonus_data],
	])
	for type: String in priorities.keys().duplicate():
		parts.append("p:%s=%d" % [type, int(priorities[type])])
	parts.sort()  # 優先權是 Dictionary，鍵序不保證——排序後才是狀態本身
	for n: Dictionary in _by_id(nodes):
		parts.append("n:%d,%s,%s,%s,%s,%s,%s" % [
			n["id"], n["type"], n["cell"], n["hp"], n["charge"], n["cd"], n["buffer"]
		])
	for c: Dictionary in _by_id(conduits):
		parts.append("c:%d,%s,%s,%d,%s" % [c["id"], c["a"], c["b"], int(c["level"]), c["hp"]])
	for e: Dictionary in _by_id(enemies):
		parts.append("e:%d,%s,%s,%s" % [e["id"], e["type"], e["progress"], e["hp"]])
	return "|".join(parts).sha256_text()


static func _by_id(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["id"]) < int(y["id"]))
	return out


func count_of(type: String) -> int:
	var n := 0
	for node: Dictionary in nodes:
		if node["type"] == type:
			n += 1
	return n
