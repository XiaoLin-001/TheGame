extends RefCounted
## 戰鬥計算（`10_GDD.md` §3.3、§7.4）。
##
## **純函式、零副作用、零系統 RNG。** 不引用 autoload。
## 回傳「打到誰、打多痛、回收多少」，狀態的變更一律在 `game/BattleController.gd`。
##
## ── 這支檔案在守的四條設計 ──────────────────────────────────────────
## ① **交戰才耗電，待機 0**：`engaged()` 只看幾何（射程內有沒有敵人），
##    與射速、與有沒有真的打中都無關。這是全案的心臟（§7.4）。
## ② **能量不足按滿足率線性降射速，不停火**：見 `shots()`。停機會雪崩（§3.1）。
## ③ **稜鏡只認四條軸線**：塔不替玩家選任意角度，擺位才能預測（§7.4）。
## ④ **匯率 1 礦砂 = 5 能量**：`reclaim_power()`。照字面 1:1 的話回收者是
##    淨耗電，「打破峰值約束的鑰匙」就成了假的。

const Tide := preload("res://scripts/sim/Tide.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Build := preload("res://scripts/sim/Build.gd")

const Clock := preload("res://scripts/sim/Clock.gd")
## 固定時間步。**值的唯一來源是 `sim/Clock.gd`**（B1.9）——這裡只是別名，
## 讓呼叫端維持讀得懂的 `Combat.TICK`。
const TICK := Clock.TICK
## 全域擊殺回收：任何塔擊殺 → 敵人價值的 25% 變礦砂（§3.3）。
const SALVAGE := 0.25
## 礦砂↔能量匯率（§3.3）。它不是新數字——就是發電機的 4 礦砂→20 能量。
const ORE_TO_POWER := 5.0
## 射程比較用的浮點寬容值（正好站在射程邊界上的敵人算在內）。
const EPS := 0.0001

## 稜鏡可用的四條軸線，**固定順序＝平手時的裁決順序**（水平→垂直→↘→↗）。
const AXES := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]

## ★ 減速的硬上限（B3.8）。**敵人永不停步**是鎖定設計（walk-by，`10_GDD.md` §3.5）
## ——1.0 的減速就是停下來，而升級開始乘光環強度之後，那個乘積不再是設計時
## 看得到的一個數字。夾在這裡而不是在資料表上：資料表管的是「這隻多強」，
## 這條管的是「再強也不准把敵人釘住」。
const SLOW_MAX := 0.85


# ── 幾何 ──────────────────────────────────────────────────────────────

## 圓形射程（歐幾里得，單位：格）。
static func in_range(a: Vector2i, b: Vector2i, r: float) -> bool:
	return Vector2(a - b).length() <= r + EPS


## 每隻敵人此刻所在的格，**與 `enemies` 同索引**。
static func enemy_cells(enemies: Array, path: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e: Dictionary in enemies:
		out.append(Tide.cell_of(path, float(e["progress"])))
	return out


## 射程內的敵人索引。**依 `enemies` 順序回傳**——確定性靠這個，不靠字典迭代。
static func in_range_indices(cell: Vector2i, cells: Array, r: float) -> Array[int]:
	var out: Array[int] = []
	for i in cells.size():
		if in_range(cell, cells[i], r):
			out.append(i)
	return out


## ★ 交戰狀態（§7.4）：**射程內有敵人就算交戰**，本 tick 要付交戰耗能。
## 回傳 `{tower id: bool}`——只回答「有沒有」。目標是誰要等敵人走完才算，
## 那是 `_fire()` 的事（見 `game/BattleController.gd`）。
static func engaged(nodes: Array, cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for n: Dictionary in nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.get("tower", false):
			continue
		# ★ 射程讀 `Build.node_range()`，**不是表上的原值**（B3.8）：有些塔的
		# 升級加的就是射程，而交戰判定是「這一刻付不付交戰電費」——
		# 讀原值的話，一座升過射程的塔會打到它自己不用付電費的敵人。
		out[int(n["id"])] = not in_range_indices(
			n["cell"], cells, Build.node_range(String(n["type"]), int(n.get("level", 0)))
		).is_empty()
	return out


# ── 目標選擇 ──────────────────────────────────────────────────────────

## 「最前」＝路徑進度最大者（最靠近核心的那隻）。
## §3.3 的四選一選單是後續批次；M0 只有這一種，且沒有 UI。
static func front_most(indices: Array, enemies: Array) -> int:
	var best := -1
	var best_p := -1.0
	for i: int in indices:
		var p := float((enemies[i] as Dictionary)["progress"])
		if p > best_p:
			best_p = p
			best = i
	return best


## ★ 稜鏡：穿過自己的四條軸線中**敵人最多的那一條**（§7.4）。
## 平手時 `AXES` 的順序就是裁決順序——零 RNG，同一局面永遠選同一條線。
static func pierce_indices(cell: Vector2i, cells: Array, r: float) -> Array[int]:
	var best: Array[int] = []
	for axis: Vector2i in AXES:
		var hit: Array[int] = []
		for i in cells.size():
			var d: Vector2i = cells[i] - cell
			if d.x * axis.y - d.y * axis.x != 0:
				continue  # 不共線
			if in_range(cell, cells[i], r):
				hit.append(i)
		if hit.size() > best.size():
			best = hit
	return best


# ── 潮鳴光環 ──────────────────────────────────────────────────────────

## 每隻敵人身上的光環效果，**與 `cells` 同索引**：`Vector2(減速比例, 破甲比例)`。
##
## 強度按該座潮鳴自己的能量滿足率縮放（§7.4）——電不夠，控場也跟著弱。
## **多座不疊加，取最強的那一座**：疊加會讓控場塔變成堆量遊戲。
static func auras(nodes: Array, cells: Array, satisfaction: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.resize(cells.size())
	out.fill(Vector2.ZERO)
	for n: Dictionary in nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("slow"):
			continue
		var k := clampf(float(satisfaction.get(int(n["id"]), 1.0)), 0.0, 1.0)
		# ★ B3.8：光環的**強度與範圍都吃級數**。使用者實玩回報「潮鳴跟霜礁升級
		#   都沒用」——這兩隻的 `dmg` 與 `rof` 都是 0，效果全在下面這兩欄上，
		#   而在此之前只有 `dmg` 被級數乘過。升級只讓它們多吃 25% 的電。
		var type := String(n["type"])
		var lvl := int(n.get("level", 0))
		var g := Build.effect_scale(type, lvl) * k
		for i: int in in_range_indices(n["cell"], cells, Build.node_range(type, lvl)):
			out[i] = Vector2(
				# ⚠ 減速夾在 `SLOW_MAX`：**敵人永不停步**是鎖定設計（walk-by），
				#   而 1.0 的減速就是停下來，超過 1.0 是倒著走。現行最強的組合
				#   （霜礁 0.65 ＋ 一個 power 級）是 0.81，這條夾子不會咬到它——
				#   它守的是日後新增光環塔時沒有人記得算這個乘積。
				maxf(out[i].x, minf(float(def["slow"]) * g, SLOW_MAX)),
				maxf(out[i].y, minf(float(def.get("armor_break", 0.0)) * g, 1.0))
			)
	return out


# ── ★ 敵人自己的兩個光環（B3.2b）──────────────────────────────────────
#
# 到 B3.2 為止**光環只有塔會發**。這兩支是反過來的那一半，而且刻意和
# `auras()` 同構：同索引的陣列、多個不疊加取最強、純函式。
# 不同構的話，日後「光環」這個詞在這個檔案裡會是兩件事。

## 庇護（殼衛）：每隻敵人身上**別人給它的**護甲加成，與 `cells` 同索引。
##
## ⚠ **不加給自己**——「站在自己光環裡」要是免費的，這一隻就變成一個
## 走路的護甲數字，而不是一個「先打誰」的問題。殼衛自己的 4 點寫在資料表上，
## 兩隻殼衛並肩走才是 10 點，那是玩家看得到成因的疊法。
static func guard_armor(enemies: Array, cells: Array) -> Array[float]:
	var out: Array[float] = []
	out.resize(cells.size())
	out.fill(0.0)
	for g in enemies.size():
		var bonus := float(Enemies.of(String((enemies[g] as Dictionary)["type"]))
			.get("guard_armor", 0.0))
		if bonus <= 0.0 or g >= cells.size():
			continue
		for i in cells.size():
			if i == g:
				continue
			# 相鄰 1 格（Chebyshev），和 walk-by 的半徑同一個尺——玩家已經學過那個範圍。
			var d: Vector2i = (cells[i] as Vector2i) - (cells[g] as Vector2i)
			if maxi(absi(d.x), absi(d.y)) <= 1:
				out[i] = maxf(out[i], bonus)
	return out


## 汲取（汲潮）：每座**塔**的交戰耗能倍率，鍵是節點 id。
##
## 只算得出倍率，不動任何狀態——扣款在 `BattleController` 那一層（§7.4 的
## 交戰耗能那一行）。回傳只含被汲到的那幾座：**沒有被汲到就不該出現在字典裡**，
## 否則呼叫端會分不出「倍率 1.0」和「這座塔不存在」。
static func drain_mult(nodes: Array, enemies: Array, cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for g in enemies.size():
		var def := Enemies.of(String((enemies[g] as Dictionary)["type"]))
		var mult := float(def.get("drain_mult", 1.0))
		if mult <= 1.0 or g >= cells.size():
			continue
		var rng := float(def.get("drain_range", 0.0))
		for n: Dictionary in nodes:
			if not bool(NodeDefs.of(String(n["type"])).get("tower", false)):
				continue
			if not in_range(n["cell"], cells[g], rng):
				continue
			# 多隻不疊乘，取最強——`auras()` 的同一條（疊加會讓它變成堆量）。
			out[int(n["id"])] = maxf(float(out.get(int(n["id"]), 1.0)), mult)
	return out


# ── 傷害與回收 ────────────────────────────────────────────────────────

## 護甲是**減法**（吃物理）、屏障是**百分比**（吃能量）——§3.5 的剋制表。
## 潮鳴的破甲只減護甲、不碰屏障：屏障的剋制方式是物理傷害，不是破甲。
## ★ B3.2b：`armor_bonus` 是**別人給它的**護甲（殼衛的庇護）。它和敵人自己的
## 護甲**先相加、再一起被破甲砍**——分開砍的話，破甲對「被罩住的那一隻」
## 只砍得到一半，而玩家看到的是同一條青色描邊。
static func hit_damage(
	raw: float, dmg_type: String, enemy: Dictionary, armor_break: float,
	armor_bonus: float = 0.0
) -> float:
	if dmg_type == "energy":
		return maxf(0.0, raw * (1.0 - clampf(float(enemy.get("barrier", 0.0)), 0.0, 1.0)))
	var armor := ((float(enemy.get("armor", 0.0)) + maxf(armor_bonus, 0.0))
		* (1.0 - clampf(armor_break, 0.0, 1.0)))
	return maxf(0.0, raw - armor)


## ★ 固定時間步下的射速。每 tick 累加 `射速 × 滿足率 × TICK`，滿 1 發一發。
## 回傳 `{cd: 新的累加器, n: 本 tick 的發數}`。
##
## **滿足率 60% → 射速 60%，線性、不停火**（§3.1、§7.4）。累加器讓
## 「1.2 發/秒」這種除不盡的射速在 0.1 秒的格子上仍然平均正確。
##
## ── 兩個非顯而易見的地方 ──────────────────────────────────────────
## ① **回傳 Dictionary 而不是 Vector2**：`Vector2` 的分量是 32 位元浮點。
##    把跨 tick 的累加器塞進去，每個 tick 都被截斷一次，100 個 tick 後
##    誤差大到足以吞掉一整發——**塔會因為容器型別少打一發**。
## ② `FIRE_EPS`：`0.12` 在浮點裡略小於十分之一點二，累加 100 次停在 11.999…。
##    加一個遠大於累積誤差、又遠小於一發的常數把它扶正。這是確定性的補強
##    不是破壞——同樣的輸入永遠得到同樣的輸出。
const FIRE_EPS := 0.000000001

static func shots(cd: float, rof: float, satisfaction: float) -> Dictionary:
	var acc := cd + rof * clampf(satisfaction, 0.0, 1.0) * TICK
	var n := floorf(acc + FIRE_EPS)
	return {"cd": maxf(0.0, acc - n), "n": int(n)}


## 全域擊殺回收：敵人價值的 25%，**以礦砂直接入帳**（§3.3）。
static func salvage_ore(value: float) -> float:
	return value * SALVAGE


## ★ 回收者：射程內任何死亡 → `價值 × ratio × 5`。**這個 5 就是匯率。**
static func reclaim_power(value: float, ratio: float) -> float:
	return value * ratio * ORE_TO_POWER
