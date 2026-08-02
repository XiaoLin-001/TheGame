extends RefCounted
## 敵人與波次資料表（`10_GDD.md` §7.5、§7.6）。**數值的唯一來源。**
## 不宣告 `class_name`，一律以路徑 preload。

## M0 三種敵人。`dmg` 是**對建築傷害（每秒）**——walk-by 每 tick 扣 `dmg × TICK`。
## `armor` 減物理傷害（減法）、`barrier` 減能量傷害（百分比）——兩者要到 B0.5
## 有塔開火時才用得上，先放進表裡免得屆時又要動資料層。
const DEFS := {
	"drifter": {
		"name": "漂蟲", "hp": 60.0, "speed": 1.0, "armor": 0.0, "barrier": 0.0,
		"dmg": 8.0, "value": 12, "radius": 9.0,
	},
	"carapace": {
		"name": "甲殼", "hp": 180.0, "speed": 0.6, "armor": 8.0, "barrier": 0.0,
		"dmg": 14.0, "value": 30, "radius": 12.0,
	},
	"ember": {
		"name": "熾泳", "hp": 90.0, "speed": 1.6, "armor": 0.0, "barrier": 0.4,
		"dmg": 10.0, "value": 22, "radius": 8.0,
	},
}

## 測試圖「淺灘」的波次表。**手作，不是公式**——戰役關卡的難度只能用玩家看得見的
## 關卡參數表達（§7.7），而波次組成正是其中最主要的一個。
##
## `gap` 是同一組內兩隻之間的間隔（秒）；組與組之間也用同一個間隔接著排。
## 前兩波只出漂蟲，是 §7.7「前兩關只出漂蟲，數量少」的同一條理由。
const SHOAL_WAVES := [
	{"groups": [{"type": "drifter", "count": 4, "gap": 1.5}]},
	{"groups": [{"type": "drifter", "count": 6, "gap": 1.2}]},
	{"groups": [
		{"type": "drifter", "count": 5, "gap": 1.0},
		{"type": "carapace", "count": 2, "gap": 2.0},
	]},
	{"groups": [
		{"type": "ember", "count": 4, "gap": 0.8},
		{"type": "carapace", "count": 3, "gap": 1.8},
	]},
	{"groups": [
		{"type": "drifter", "count": 8, "gap": 0.6},
		{"type": "ember", "count": 5, "gap": 0.8},
		{"type": "carapace", "count": 4, "gap": 1.5},
	]},
]


## ★ 戰役五關的波次表（B1.2，`10_GDD.md` §7.9）。**手作，不是公式。**
##
## 難度階梯只用玩家看得見的東西（§7.7）：**波數**與**組成**。
##   第 1 關 3 波、只有漂蟲——「前兩關只出漂蟲，數量少」的字面實作。
##   甲殼（護甲 8）在第 2 關末尾首次出現，正好是稜鏡解鎖的那一關：
##     錨的 18 物理傷害被護甲砍成 10，稜鏡的 30 能量傷害不受影響。
##   熾泳（能量抗性 40%）在第 3 關首次出現，把「稜鏡打什麼都行」擋回去。
## 三種敵人各有一關是它的登場考，之後才混編。
const L1_WAVES := [
	{"groups": [{"type": "drifter", "count": 4, "gap": 1.5}]},
	{"groups": [{"type": "drifter", "count": 5, "gap": 1.4}]},
	{"groups": [{"type": "drifter", "count": 6, "gap": 1.2}]},
]

const L2_WAVES := [
	{"groups": [{"type": "drifter", "count": 5, "gap": 1.4}]},
	{"groups": [{"type": "drifter", "count": 7, "gap": 1.2}]},
	{"groups": [{"type": "drifter", "count": 8, "gap": 1.0}]},
	{"groups": [
		{"type": "drifter", "count": 6, "gap": 1.0},
		{"type": "carapace", "count": 2, "gap": 2.0},
	]},
]

const L3_WAVES := [
	{"groups": [{"type": "drifter", "count": 6, "gap": 1.2}]},
	{"groups": [
		{"type": "drifter", "count": 6, "gap": 1.0},
		{"type": "carapace", "count": 2, "gap": 2.0},
	]},
	{"groups": [
		{"type": "ember", "count": 4, "gap": 0.9},
		{"type": "drifter", "count": 4, "gap": 1.2},
	]},
	{"groups": [
		{"type": "carapace", "count": 3, "gap": 1.8},
		{"type": "ember", "count": 4, "gap": 0.8},
	]},
	{"groups": [
		{"type": "drifter", "count": 8, "gap": 0.7},
		{"type": "carapace", "count": 3, "gap": 1.6},
		{"type": "ember", "count": 4, "gap": 0.8},
	]},
]

const L4_WAVES := [
	{"groups": [{"type": "drifter", "count": 8, "gap": 1.0}]},
	{"groups": [
		{"type": "carapace", "count": 3, "gap": 1.8},
		{"type": "drifter", "count": 6, "gap": 1.0},
	]},
	{"groups": [
		{"type": "ember", "count": 6, "gap": 0.8},
		{"type": "carapace", "count": 2, "gap": 2.0},
	]},
	{"groups": [
		{"type": "carapace", "count": 5, "gap": 1.4},
		{"type": "ember", "count": 5, "gap": 0.8},
	]},
	{"groups": [
		{"type": "drifter", "count": 12, "gap": 0.6},
		{"type": "carapace", "count": 4, "gap": 1.4},
		{"type": "ember", "count": 6, "gap": 0.7},
	]},
]

const L5_WAVES := [
	{"groups": [{"type": "drifter", "count": 10, "gap": 0.9}]},
	{"groups": [
		{"type": "carapace", "count": 4, "gap": 1.5},
		{"type": "ember", "count": 4, "gap": 0.9},
	]},
	{"groups": [
		{"type": "ember", "count": 8, "gap": 0.7},
		{"type": "carapace", "count": 3, "gap": 1.6},
	]},
	{"groups": [
		{"type": "carapace", "count": 6, "gap": 1.3},
		{"type": "drifter", "count": 10, "gap": 0.7},
	]},
	{"groups": [
		{"type": "drifter", "count": 14, "gap": 0.5},
		{"type": "carapace", "count": 5, "gap": 1.2},
		{"type": "ember", "count": 8, "gap": 0.6},
	]},
]


static func of(type: String) -> Dictionary:
	return DEFS.get(type, {})


static func label(type: String) -> String:
	return String(of(type).get("name", type))


## 一波的完整出場表：`[{type, at}]`，`at` 是距波次開始的秒數。
## **純函式、零 RNG**——同一個波次索引永遠產生同一張表（§2.4 確定性）。
static func schedule(waves: Array, index: int) -> Array:
	var out: Array = []
	if index < 0 or index >= waves.size():
		return out
	var t := 0.0
	for g: Dictionary in (waves[index] as Dictionary)["groups"]:
		var gap := float(g["gap"])
		for i in int(g["count"]):
			out.append({"type": String(g["type"]), "at": t})
			t += gap
	return out

# ★ 無盡模式的縮放公式（§7.6 的 `1.11^波次` 與 `4 + ⌊波次/3⌋`）**刻意不在這裡**：
#   它從 B0.4 就寫著「B2.1 才會用到」，而唯一的呼叫端一直是測試自己。
#   數值權威在 `10_GDD.md` §7.6，B2.1 真的做無盡時再從那裡長出來——
#   一個只有測試在用的公式，測的是它自己還記不記得自己（B1.9 刪除）。
