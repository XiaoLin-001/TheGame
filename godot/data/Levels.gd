extends RefCounted
## 等級軸（`10_GDD.md` §1 B2 ②、§7.15；B2.7）。**數值的唯一來源、純函式、零副作用。**
##
## 和 `data/Tech.gd` 並排放：兩者是「局外成長的兩軸」，形狀刻意長得一樣
## （一張表 → 一個 `mods()` 字典 → 一支量上限的 `gain()`）。
##
## ── 為什麼兩軸的上限要分開量 ────────────────────────────────────────
## §1 B2 給的是**兩把各自獨立的尺**：科技軸 ≤ +35%、等級軸滿級 +80%。
## 把它們加成一個數字去斷言，會讓任一邊調數值時另一邊的上限無聲地位移——
## 所以 `Tech.combat_gain()` 只量科技、`Levels.gain()` 只量等級，各自有自己的斷言。

## 兩軸。字串直接就是存檔裡的鍵。
const TOWER := "tower"
const LINE := "line"
const AXES: Array[String] = [TOWER, LINE]

const AXIS_NAMES := {
	TOWER: "塔",
	LINE: "生產",
}

const AXIS_DESC := {
	TOWER: "所有塔的傷害。每級 +8%（加法），滿級 +80%。",
	LINE: "所有生產節點的產出（礦砂／能量／合金）。每級 +8%（加法），滿級 +80%。",
}

const MAX_LEVEL := 10

## 每級 +8%，**加法不是連乘**——連乘的 10 級是 +115.9%，那不是 §1 B2 寫的數字。
const PER_LEVEL := 0.08

## 買第 n 級要多少升級材料（§7.15 的成本表）。線性就夠了：
## 這一軸的煞車是**材料的產出速率**（波數／訂單），不是成本的階數。
const COST_PER_LEVEL := 12


## 存檔（整份）→ 某一軸的級數。
static func level_of(save: Dictionary, axis: String) -> int:
	return of_levels(save.get("levels", {}), axis)


## `save["levels"]` 那一格 → 某一軸的級數。
##
## 兩支並存是因為模擬層拿到的是**那一格**而不是整份存檔（`SessionState.setup()`
## 的參數）——把整份存檔遞進模擬層，等於給它一條讀任何進度的路。
static func of_levels(levels: Dictionary, axis: String) -> int:
	return clampi(int(levels.get(axis, 0)), 0, MAX_LEVEL)


## 買**下一級**（從 `level` 升到 `level + 1`）要多少材料。滿級回 0。
static func cost(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return COST_PER_LEVEL * (level + 1)


## 從 0 推到滿級的單軸總價。**測試與 UI 都問這一支**，不各自去跑迴圈。
static func total_cost() -> int:
	var sum := 0
	for i in MAX_LEVEL:
		sum += cost(i)
	return sum


## 這一軸現在的乘數。`0 級 ＝ 1.0`，滿級 ＝ 1.8。
static func mult(level: int) -> float:
	return 1.0 + PER_LEVEL * float(clampi(level, 0, MAX_LEVEL))


## ★ 這一軸的增幅（`mult - 1`）。**B2 ② 的 +80% 上限量的就是它**。
static func gain(level: int) -> float:
	return mult(level) - 1.0


## ★ 把等級軸折進 `Tech.mods()` 那一個字典（全案唯一一個把等級翻成數字的地方）。
##
## 折進同一個字典而不是另開一條路：`s.mods` 已經有五個消費端
## （`BattleController` ×3、`BuildController` ×2），而每一個「要記得也乘上等級」
## 的呼叫端都是一個會靜靜失效的地方——那正是 `Tech.gd` 開頭那段註解的內容。
static func apply(mods: Dictionary, levels: Dictionary) -> Dictionary:
	mods["damage_mult"] = float(mods.get("damage_mult", 1.0)) * mult(of_levels(levels, TOWER))
	mods["produce_mult"] = float(mods.get("produce_mult", 1.0)) * mult(of_levels(levels, LINE))
	return mods


## 能不能升？回傳原因碼（空字串＝可以），文案在畫面層——同 `Tech.can_unlock()` 的分工。
const OK := ""
const UNKNOWN := "unknown"
const MAXED := "maxed"
const NO_COMPONENTS := "no_components"

static func can_upgrade(save: Dictionary, axis: String, components: int) -> String:
	if not AXES.has(axis):
		return UNKNOWN
	var lv := level_of(save, axis)
	if lv >= MAX_LEVEL:
		return MAXED
	if components < cost(lv):
		return NO_COMPONENTS
	return OK
