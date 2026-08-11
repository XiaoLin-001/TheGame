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

	# ── M3 第一批（B3.2）。三隻，**一隻一條新規則**，而且三條都由既有的塔回答 ──
	#
	# 這一批不補到 §5 內容矩陣的 12 隻。理由是本案已經記過兩次的同一條
	# （§5 的 B1.1／B2.4 註）：**一次補齊一堆沒平衡過的內容，會讓後面的校準
	# 建立在流沙上**。3 → 6 是 M1 那一欄的數字，而每一隻都有現成的剋制手段。
	#
	# 三隻**只進無盡與每日的出場池**（`endless_pool()`），戰役五關一格都不動
	# ——那五關的參考解是 `campaign_test` 431 條斷言的地基。
	"surge": {
		# ★ 迅捷：**免疫減速**。§3.5 的屬性表從 M0 就寫著這一條，
		#   而在 B3.2 之前沒有任何一隻敵人有它——於是潮鳴／霜礁的減速對全場都有效，
		#   「全押光環」是一個沒有代價的答案。剋制它的是高爆發單體（長哨、定潮）。
		#   ★ 視覺不必新增：它站在光環裡**沒有那圈青色描邊**，那就是「抓不住它」。
		"name": "潛涌", "hp": 70.0, "speed": 1.9, "armor": 0.0, "barrier": 0.0,
		#   ★ 半徑 6（熾泳是 8）：兩隻都超過 `SWIFT_SPEED` 門檻、都會拿到亮核心，
		#     只靠那一點在 fit 倍率下分不開。小一號 ＋ 菱形核心（`_draw_enemies`）
		#     才是「形狀與顏色同時不同」（RG-145 的同一條）。
		"dmg": 9.0, "value": 20, "radius": 6.0, "swift": true,
	},
	"bloom": {
		# ★ 群體：一次抽中就出 `pack` 隻。血薄、傷害低，但**擠成一團**，
		#   剋制它的是濺射（碎浪）與貫穿（稜鏡）。
		#   ★ 一次抽中 ≈ 一份壓力：24×3 = 72 血，和漂蟲的 60 同一個量級，
		#     所以它改的是壓力的**形狀**，不是總量。
		"name": "苔群", "hp": 24.0, "speed": 1.1, "armor": 0.0, "barrier": 0.0,
		"dmg": 3.0, "value": 5, "radius": 5.0, "pack": 3,
	},
	"mender": {
		# ★ 再生：每秒回復**最大血量的 4%**。寫成比例不是絕對值，
		#   所以它跟著無盡的血量曲線與難度層一起長——不然第 30 波的它等於沒有這條規則。
		#
		#   ★ 這一條直接接上全案的核心命題（§3.1 峰值電力）：塔在缺電時射速線性下降，
		#     而下降到某一點之後 **dps 追不上再生，它就永遠不會死**。
		#     「電力不足」從此不只是慢一點，而是有一個看得見的門檻。
		#   armor 刻意是 0：一隻敵人一條新規則，甲板描邊留給甲殼。
		"name": "癒殼", "hp": 150.0, "speed": 0.7, "armor": 0.0, "barrier": 0.0,
		"dmg": 12.0, "value": 34, "radius": 11.0, "regen": 0.04,
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

# ── 無盡模式（B2.1a，`10_GDD.md` §7.10）─────────────────────────────────
#
# B1.9 把這幾個公式刪掉過一次，理由是「唯一的呼叫端一直是測試自己」。
# 現在它們有真的呼叫端了，所以照 §7.6 的原文長回來——**只有這三條曲線**。
# 出場間隔刻意是常數：壓力已經由血量與隻數表達完了，再給間隔第三條曲線，
# 玩家就分不出「這波難是因為血厚還是因為密」（§7.10）。

## 每波血量倍率，乘在敵人自己的 `hp` 上。`w` 自 1 起 → 第 1 波是原始強度。
const ENDLESS_GROWTH := 1.11
## 出場間隔（秒），固定值。
const ENDLESS_GAP := 1.0
## 波次種子的錯開量。質數，讓相鄰波拿到不相干的序列。
const ENDLESS_STRIDE := 7919


static func endless_hp_mult(w: int) -> float:
	return pow(ENDLESS_GROWTH, float(maxi(1, w) - 1))


static func endless_count(w: int) -> int:
	return 4 + int(floor(float(maxi(1, w)) / 3.0))


## 第 `w` 波的敵種池。與戰役同一條登場順序（§7.9）：護甲先教、能量抗性後教。
## ★ B3.2 起一路加到六隻。**一次只多一種，每三波一階**——同一條登場順序的理由：
## 新規則要有一段只有它自己的時間，玩家才對得起來「這一波難是因為多了什麼」。
## 戰役五關不受影響（它們走自己的手作波次表，§7.9）。
static func endless_pool(w: int) -> Array[String]:
	var pool: Array[String] = ["drifter"]
	for gate: Array in [[3, "carapace"], [6, "ember"], [9, "bloom"], [12, "surge"], [15, "mender"]]:
		if w >= int(gate[0]):
			pool.append(String(gate[1]))
	return pool


## 第 `w` 波的完整出場表（`w` 自 1 起）。**同 `(s, w)` 必得同一張表**。
static func endless_schedule(s: int, w: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = s + w * ENDLESS_STRIDE
	var pool := endless_pool(w)
	var out: Array = []
	var t := 0.0
	while out.size() < endless_count(w):
		var type := pool[rng.randi_range(0, pool.size() - 1)]
		# ★ 群體（B3.2）：抽中一次就**連續佔掉 `pack` 個出場位**。
		#
		#   兩件事刻意不做：不縮短間隔、不追加額外的隻數。§7.10 的兩條
		#   「隻數 = 4 + floor(w/3)」與「間隔固定 1.0 秒」是**寫死的不變量**
		#   （後者的理由是「再給間隔一條曲線，玩家就分不出這波難是因為血厚
		#   還是因為密」）——群體改的是**同一批出場位裡出現什麼**，不是這兩條。
		#
		#   而它仍然是一團：三隻速度 1.1、間隔 1 秒 → 路徑上相距 1.1 格，
		#   三隻落在 2.2 格內，正好進得了碎浪 2.5 格的濺射半徑。
		var pack := clampi(int(of(type).get("pack", 1)), 1, endless_count(w) - out.size())
		for k in pack:
			out.append({"type": type, "at": t})
			t += ENDLESS_GAP
	return out
