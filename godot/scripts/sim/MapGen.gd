extends RefCounted
## 無盡模式的程序地圖生成（`10_GDD.md` §7.10）。
##
## **純函式、零副作用、零系統 RNG。** 種子由呼叫端注入，產生器在本地建立
## ——不碰 `Rng` autoload 的全域狀態（`30_TECH_DESIGN.md` §2.4）。
##
## ★ **輸出的 dict 與 `data/Maps.gd` 的手作圖同構**（`size`／`core`／`waypoints`／
## `crossings`／`ore`／`start_ore`／`prep_time`）。這是這支檔案最重要的一個決定：
## 渲染、建造、命中判定、示範佈局、截圖鉤子全部**零改動**，生成器只是換一個
## 地方生產同一種資料。`Maps.path_of()`／`to_sets()` 也照樣吃得下。

const Maps := preload("res://data/Maps.gd")

## ★ 大過一屏（B2.1b，`10_GDD.md` §7.10）。框架 1152×604 在**可讀性地板**
## （24px／格）下看得到 48×25 格 → 64×40 看得到 **75%×62% ＝ 面積的 46%**。
##
## 為什麼不是 56×32（第一版）：那個尺寸看得到 86%×79%，**小地圖上的視野框
## 幾乎和外框重疊**——「我在哪」讀不出來，兩個導引通道的價值一起被稀釋。
## 一個只是技術上大過一屏的地圖，不值得為它做導引。
##
## 為什麼**高的比寬的多加**：路徑長度 ≈ 寬度 ＋ 各段直走，而直走跨距有上限
## （`Y_MAX_JUMP`）。**加高幾乎不影響一波的時間，加寬是一比一地加**。
## 64 寬約 100 格路徑，是第 5 關（約 52 格）的 1.9 倍——一波的時間也是。
## 這是刻意接受的代價（§7.10 有記），但也是不再加寬的理由。
##
## **不參數化成 `generate(w, h)`**：只有一種尺寸，開參數是替還不存在的第二種
## 佈局預先設計。M2 真的加到 3 種佈局時再說。
const W := 64
const H := 40
## 折段數（§7.10）：少於 4 段在 56 格寬會變成一條幾乎筆直的長廊、塔隨便擺
## 都覆蓋得到；多於 6 段會擠成鋸齒，而且每多一段就多一條直走要走。
const SEG_MIN := 4
const SEG_MAX := 6
## ★ 以下四個數字在 B2.1b 全部跟著面積重算過。**放大地圖而不動它們，等於
## 悄悄把難度調高**：礦點密度掉 3 倍（6–8 個撒在 1792 格上）、每條產線的導管
## 長度變 1.7 倍而起始礦砂沒動、路徑長了一倍而橋還是兩座。
## 難度只能用玩家看得見的關卡參數表達（§7.7）——那也包括「不要用改尺寸偷改」。
const CROSS_MIN := 4
const CROSS_MAX := 6
const ORE_MIN := 20
const ORE_MAX := 26
## ★ 不必過橋就到得了核心的礦點下限（§7.10 不變量 5）。
## 手作圖能靠設計者的眼睛避開「礦砂全在對岸」，生成器只能靠這個數字。
## 跟著總數一起提高——3/26 的保證比 3/8 弱得多。
const NEAR_ORE := 7
## 第 5 關（34×18）是 1240，而這張圖的導管長度約 1.9 倍（3 礦砂/格）。
const START_ORE := 1900.0
const PREP := 45.0
## 相鄰兩段橫走之間至少要差幾列——差 1 列的兩段等於一條粗路徑，
## 中間夾不進任何東西。
const Y_APART := 3
## ★ 也**至多**差幾列（B2.1b）。H 從 18 長到 32 之後，沒有上限的話單一條
## 直走可以跨掉 27 格——路徑長度（＝一波的時間）憑種子暴增一倍，而畫面上
## 只是「這張圖比較長」。有上限之後路徑長度的變異收在可預期的範圍內。
const Y_MAX_JUMP := 14
## 相鄰兩個轉折至少要隔幾行，理由同上。
const X_APART := 3
## ★ 橫走離上下邊界至少要留幾列。**遊戲的說明面板自己寫著「塔與導管退開
## 路徑 2 格就安全」**——貼在 y=1 的橫走讓那一側做不到，玩家可用的空間
## 憑種子少掉一半。手作的五關沒有一關把路徑貼到邊上，這條是把它寫下來。
const EDGE := 2


## 生成一張圖。**同一個 `s` 必得逐格相同的結果**（§7.10 不變量 1）。
static func generate(s: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var waypoints := _waypoints(rng)
	var core: Vector2i = waypoints[waypoints.size() - 1]
	var on_path: Dictionary = {}
	for c: Vector2i in Maps.path_of({"waypoints": waypoints}):
		on_path[c] = true
	return {
		"id": "endless_%d" % s,
		"name": "潮汐迴廊",
		"size": Vector2i(W, H),
		"core": core,
		"waypoints": waypoints,
		# 無盡沒有波次表——波次由公式長出來（`Enemies.endless_schedule`）。
		# 這個旗標就是 `BattleController` 分岔的地方。
		"waves": [],
		"endless": true,
		"seed": s,
		"start_ore": START_ORE,
		"prep_time": PREP,
		"crossings": _crossings(rng, Maps.path_of({"waypoints": waypoints})),
		"ore": _ore(rng, on_path, core),
	}


## 正交蛇行的轉折點。最後一點必為核心（`Maps.path_of()` 的約定）。
##
## ★ **不自交是結構保證，不是重擲出來的**（§7.10 不變量 2）：轉折的 x 嚴格遞增，
## 所以每一段橫走各佔一段互不重疊的 x 區間、每一段直走各在不同的 x 上。
## 兩段橫走就算落在同一列也碰不到彼此。
static func _waypoints(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var segs := rng.randi_range(SEG_MIN, SEG_MAX)
	var core_x := W - 2
	var xs: Array[int] = []
	for i in range(1, segs + 1):
		if i == segs:
			xs.append(core_x)
			continue
		var lo := (xs[xs.size() - 1] + X_APART) if not xs.is_empty() else X_APART
		var base := int(round(float(core_x) * float(i) / float(segs)))
		# 剩下的段數還要各佔 X_APART 行，所以上界要留給它們。
		var hi := core_x - X_APART * (segs - i)
		xs.append(clampi(base + rng.randi_range(-2, 2), lo, maxi(lo, hi)))

	var y := rng.randi_range(EDGE, H - 1 - EDGE)
	var pts: Array[Vector2i] = [Vector2i(0, y)]
	for i in xs.size():
		pts.append(Vector2i(xs[i], y))
		if i < xs.size() - 1:
			y = _other_y(rng, y)
			pts.append(Vector2i(xs[i], y))
	return pts


## 下一段橫走的列。**從合格的列裡直接抽**，不是抽了再檢查重擲——
## 重擲迴圈的執行次數會跟著種子跑，那種東西在確定性測試裡很難看。
static func _other_y(rng: RandomNumberGenerator, y: int) -> int:
	var picks: Array[int] = []
	for v in range(EDGE, H - EDGE):
		if absi(v - y) >= Y_APART and absi(v - y) <= Y_MAX_JUMP:
			picks.append(v)
	return picks[rng.randi_range(0, picks.size() - 1)]


## 跨越點：把候選均分成 n+1 段，各段中央附近挑一格。均分保證它們散得開。
##
## ★ **候選只有直線段中間的格，轉角不算**：轉角上的橋是廢的——導管從那裡
## 「過去」會變成沿著路徑走，而不是跨過去。一張圖只有 2–3 座橋，浪費一座
## 就是三分之一的空間預算。判準是前後兩格共線（轉角的前後兩格兩軸都不同）。
## 頭尾也自然被排除（入口與核心沒有前／後格）。
static func _crossings(rng: RandomNumberGenerator, path: Array) -> Array[Vector2i]:
	var straight: Array[int] = []
	for i in range(1, path.size() - 1):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i + 1]
		if a.x == b.x or a.y == b.y:
			straight.append(i)
	var n := rng.randi_range(CROSS_MIN, CROSS_MAX)
	var seg := straight.size() / (n + 1)
	var out: Array[Vector2i] = []
	for i in range(1, n + 1):
		var mid := i * seg
		var jitter := seg / 3
		var at := clampi(rng.randi_range(mid - jitter, mid + jitter), 0, straight.size() - 1)
		out.append(path[straight[at]])
	return out


## 礦點。**先把「核心這一側」的配額塞滿，剩下的才自由撒**——
## 這是不變量 5 的實作方式：構造出來的，不是撒完再檢查。
static func _ore(rng: RandomNumberGenerator, on_path: Dictionary, core: Vector2i) -> Array[Vector2i]:
	var n := rng.randi_range(ORE_MIN, ORE_MAX)
	var out: Array[Vector2i] = []
	var used: Dictionary = {}
	_take(rng, _core_region(on_path, core), NEAR_ORE, used, out)
	_take(rng, _free_cells(on_path), n - out.size(), used, out)
	return out


## 從候選裡抽 k 個相異格。候選不足就抽多少算多少——
## 真的不足時該紅的是 `endless_test` 的不變量斷言，不是這裡靜默補一格假的。
static func _take(
	rng: RandomNumberGenerator, pool: Array[Vector2i], k: int,
	used: Dictionary, out: Array[Vector2i]
) -> void:
	var avail: Array[Vector2i] = []
	for c: Vector2i in pool:
		if not used.has(c):
			avail.append(c)
	for i in k:
		if avail.is_empty():
			return
		var at := rng.randi_range(0, avail.size() - 1)
		var c: Vector2i = avail[at]
		avail.remove_at(at)
		used[c] = true
		out.append(c)


## ★ 「不必過橋就到得了核心」的可執行定義：從核心的自由鄰格出發、
## 只走非路徑格的四連通泛洪。路徑格是牆——導管只能經由跨越點通過（§3.2），
## 所以泛洪到不了的地方，字面意義上就是「要過橋」。
static func _core_region(on_path: Dictionary, core: Vector2i) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c := core + d
		if _free(c, on_path) and not seen.has(c):
			seen[c] = true
			queue.append(c)
	var out: Array[Vector2i] = []
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		out.append(c)
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb := c + d
			if _free(nb, on_path) and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	return out


static func _free_cells(on_path: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			if _free(c, on_path):
				out.append(c)
	return out


static func _free(c: Vector2i, on_path: Dictionary) -> bool:
	return c.x >= 0 and c.x < W and c.y >= 0 and c.y < H and not on_path.has(c)
