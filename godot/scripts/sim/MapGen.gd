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
## ★ 上限留了補洞的餘裕（B2.1c 第三輪）。網格本身最多給 25 顆，補洞最多再加
## 幾顆——**上限貼著網格訂會讓補洞在半路被卡住**：實測有一張圖補完第一個
## 空區就撞到 26，第二個空區於是被跳過（`seed=106`，那一區還有 187 格可用）。
const ORE_MAX := 28
## ★ 面積分層用的區塊網格（B2.1c 第三輪）。**礦點數 ＝ 區塊數**，一塊恰好一顆
## ——「平均」因此是構造出來的，不是撒完再檢查。
##
## 為什麼是一張表而不是由 `n` 反推：反推出來的區塊數常常比 `n` 多一兩塊，
## 多出來的那幾塊就得**被跳過**，而被跳過的那一塊在畫面上就是「這一區沒有礦」
## （實測 300 張圖有 181 個大區是空的）。先選網格、再讓數量跟著網格走，
## 這個缺口就不存在。
##
## 五組的長寬比都讓區塊接近正方形（`64/cols` : `40/rows` 落在 0.6–1.6），
## 數量落在 `ORE_MIN..ORE_MAX` 內。
const ORE_GRIDS: Array[Vector2i] = [
	Vector2i(5, 4),   # 20 顆，區塊 12.8×10
	Vector2i(7, 3),   # 21 顆，區塊 9.1×13.3
	Vector2i(6, 4),   # 24 顆，區塊 10.7×10
	Vector2i(8, 3),   # 24 顆，區塊 8×13.3
	Vector2i(5, 5),   # 25 顆，區塊 12.8×8
]
## ★ 礦點**平均鋪滿整張圖**（B2.1c 第三輪，使用者指定）。
##
## 三輪的演進：均勻撒點（結塊）→ 隨機錨點長脈（還是結塊）→ 沿**路徑**分層
## （沿路線均勻了，但**只長在路邊**）。使用者的原話是「我不喜歡這種都只生在
## 道路旁邊，然後其他區域都沒有的，我希望是平均分配」。
##
## 所以分層的座標系從「路徑索引」換成「**地圖面積**」：整張圖切成
## `rows×cols` 個區塊、一塊放一顆。這同時解掉了原本記在 §7.10 的
## 「死區面積 45%」——礦點鋪滿全圖之後，離路徑遠的地方不再是空的，
## 而是「安全、但要拉長線」的取捨。
##
## **礦脈（共線成群）已移除。** 那是我從手作圖歸納出來的規則，不是使用者要的。
## 兩顆礦最少隔幾格——同一個區塊內不會有兩顆，這條守的是**相鄰區塊的邊界**：
## 兩顆各自貼著共同邊界就會又擠在一起。
const ORE_APART := 4
## ★ 「平均分配」的**規格**：把整張圖切成 `4×3` 個大區，每一區都必須有礦。
##
## 這是使用者的要求本身，不是實作細節，所以寫成常數放在這裡、由生成器負責
## 保證（`_ore()` 末尾的補洞），`endless_test` 再**獨立**驗一次。
##
## 為什麼還需要補洞：放置用的區塊網格（`ORE_GRIDS`）和這個大區網格**不對齊**
## ——5 欄的區塊放進 4 欄的大區，區塊邊界上的礦可能落到隔壁大區去。
## 實測 300 張圖有 21 個大區因此空著（0.6%），補洞把它變成 0。
const AREA_COLS := 4
const AREA_ROWS := 3
## ★ 礦點離路徑的**下限**。敵人每 tick 傷害相鄰 1 格內的建築（§3.5），
## 貼著路徑的礦點蓋下去就是送死，等於不是礦點。
##
## **上限已於第三輪移除**（原本是 7）。那條上限正是「只長在路邊」的成因：
## 它把礦點鎖在路徑兩側各 7 格的帶子裡，全圖其他地方一顆都不會有。
const OFF_MIN := 2
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
	var path := Maps.path_of({"waypoints": waypoints})
	var on_path: Dictionary = {}
	for c: Vector2i in path:
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
		"crossings": _crossings(rng, path),
		"ore": _ore(rng, path, on_path, core),
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

	var ys := _sweep_ys(rng, segs)
	var pts: Array[Vector2i] = [Vector2i(0, ys[0])]
	for i in xs.size():
		pts.append(Vector2i(xs[i], ys[i]))
		if i < xs.size() - 1:
			pts.append(Vector2i(xs[i], ys[i + 1]))
	return pts


## 各段橫走的列。**單調掃掠**（由上而下或由下而上，不折返）。
##
## ★ 這是 B2.1c 的核心修正。舊版每段獨立抽一列（`_other_y`），走出來的是一條
## **在窄帶裡來回折返**的路徑：實測平均花掉 34 格的直走travel，只換到 19.3 列
## 的縱向跨幅（H＝40），於是 **26% 的列離路徑超過 6 格 ＝ 玩家永遠不會去的死區**。
## 使用者的原話是「東西都集中在路線上半區，下半區很空」。
##
## 關鍵是**跨越全高的代價只付一次**：單調序列的直走總長恆等於
## `y[末] − y[首]`，折返則是白花的。所以改成單調之後，
## **路徑長度不增反減**（95.9 → 實測見 §7.10），跨幅卻拿滿。
## 這一點很要緊——`Tide.advance()` 是 `progress += speed * TICK`，
## **路徑格數就是一波的秒數**，加長路徑等於直接加長每一波。
##
## 列的來源是**分層抽樣**：把 `[EDGE, H-1-EDGE]` 切成 `segs` 條等寬帶，
## 一帶抽一列。這保證首尾各落在最外側的帶裡（跨幅有下限），
## 而帶內的自由度仍然給得出不同的圖。
static func _sweep_ys(rng: RandomNumberGenerator, segs: int) -> Array[int]:
	var lo := EDGE
	var hi := H - 1 - EDGE
	var band := float(hi - lo + 1) / float(segs)
	var ys: Array[int] = []
	var prev := -H
	for i in segs:
		var b_lo := lo + int(floor(band * float(i)))
		var b_hi := lo + int(floor(band * float(i + 1))) - 1
		# ★ 頭尾兩帶只取**外側半邊**。跨幅的下限完全由這兩帶決定：不收窄的話
		#   `segs=4` 的最差情況是頭取 10、尾取 29 ＝ 只跨 19 列，兩端各留下
		#   一片死區（實測有種子出現 8 列死列）。收窄後最差跨 27 列、死列 ≤ 1。
		if i == 0:
			b_hi = b_lo + (b_hi - b_lo) / 2
		elif i == segs - 1:
			b_lo = b_hi - (b_hi - b_lo) / 2
		# 帶寬（≥6，因為 segs ≤ 6）永遠容得下 Y_APART，所以這個下界不會越過 b_hi。
		var pick_lo := maxi(b_lo, prev + Y_APART)
		var y := rng.randi_range(pick_lo, maxi(pick_lo, b_hi))
		ys.append(y)
		prev = y
	# 由下而上的圖和由上而下的一樣多——核心因此不是每局都在同一角。
	if rng.randi_range(0, 1) == 1:
		ys.reverse()
	return ys


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


## 礦點。**沿地圖面積分層**：整張圖切成 `rows×cols` 個區塊，一塊放一顆。
##
## ★ B2.1c 第三輪（使用者指定「平均分配」）。前兩輪分別敗在：均勻**隨機**
## 必然結塊；沿**路徑索引**分層雖然沿路線均勻，卻把礦點鎖死在路邊的帶子裡。
## 換成面積分層之後，「均勻」是**構造出來的**：每個區塊恰好一顆，
## 所以既不會結塊、也不會有整片沒有礦的區域。
##
## 區塊數依地圖長寬比切，讓區塊接近正方形——64×40 放 24 顆是 6×4，
## 一塊約 10×10 格。
static func _ore(
	rng: RandomNumberGenerator, path: Array, on_path: Dictionary, core: Vector2i
) -> Array[Vector2i]:
	var dist := _dist_to_path(on_path)
	var grid: Vector2i = ORE_GRIDS[rng.randi_range(0, ORE_GRIDS.size() - 1)]
	var cols := grid.x
	var rows := grid.y
	var out: Array[Vector2i] = []
	var used: Dictionary = {}
	# **每一塊都放，一塊都不跳過**——礦點數就是區塊數。
	for idx in cols * rows:
		var c := _pick_in(rng, idx % cols, idx / cols, cols, rows, dist, used)
		if c.x >= 0:
			used[c] = true
			out.append(c)

	# ★ 補洞：大區網格上任何一區沒有礦，就在那一區補一顆（見 `AREA_COLS`）。
	for gx in AREA_COLS:
		for gy in AREA_ROWS:
			var x0 := W * gx / AREA_COLS
			var x1 := W * (gx + 1) / AREA_COLS - 1
			var y0 := H * gy / AREA_ROWS
			var y1 := H * (gy + 1) / AREA_ROWS - 1
			var any := false
			for c: Vector2i in out:
				if c.x >= x0 and c.x <= x1 and c.y >= y0 and c.y <= y1:
					any = true
					break
			if any or out.size() >= ORE_MAX:
				continue
			var fill := _scan(rng, x0, x1, y0, y1, dist, used)
			if fill.x < 0:
				# ★ 補洞失敗時**放寬間距再試一次**：這一區有礦是規格，
				#   兩顆離得開只是好看。實測 3600 個大區裡有 1 個會走到這裡。
				fill = _scan(rng, x0, x1, y0, y1, dist, used, 1)
			if fill.x >= 0:
				used[fill] = true
				out.append(fill)

	# 不變量 5 的保底：核心那一側至少 `NEAR_ORE` 顆。面積分層通常自然滿足
	# （路徑把圖切兩半，各佔一半區塊），但路徑貼近某一角時那一側會偏少。
	var region: Dictionary = {}
	for c: Vector2i in _core_region(on_path, core):
		region[c] = true
	var near := 0
	for c: Vector2i in out:
		if region.has(c):
			near += 1
	if near < NEAR_ORE:
		_singles(rng, _near_pool(dist, region), NEAR_ORE - near, used, out)
	return out


## 在第 `(cx, cy)` 個區塊裡挑一格。**掃過整個區塊**（隨機起點、繞一圈），
## 不是抽一格就放棄——抽到路徑格或太靠近鄰居就跳過，區塊真的塞不下才回 −1。
## 掃描次數由區塊大小決定，與種子無關（確定性）。
static func _pick_in(
	rng: RandomNumberGenerator, cx: int, cy: int, cols: int, rows: int,
	dist: Dictionary, used: Dictionary
) -> Vector2i:
	var x0 := int(float(W) * float(cx) / float(cols))
	var x1 := int(float(W) * float(cx + 1) / float(cols)) - 1
	var y0 := int(float(H) * float(cy) / float(rows))
	var y1 := int(float(H) * float(cy + 1) / float(rows)) - 1
	# ★ **整塊都可以放，不往中央擠。** 曾經試過各邊內縮 1/4（為了讓相鄰兩塊的
	#   礦不要各自貼在共同邊界上），代價是**地圖最上緣與最下緣整片沒有礦**
	#   ——3 條橫帶各內縮 3 列，第 0–2 列與第 36–39 列就再也不會被選到。
	#   改回整塊均勻，邊界相鄰的問題交給 `ORE_APART`，大區的覆蓋交給補洞。
	return _scan(rng, x0, x1, y0, y1, dist, used)


## 在一個矩形內掃出第一個合格的格（隨機起點、繞一圈）。
static func _scan(
	rng: RandomNumberGenerator, x0: int, x1: int, y0: int, y1: int,
	dist: Dictionary, used: Dictionary, apart: int = ORE_APART
) -> Vector2i:
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var cnt := w * h
	if cnt <= 0:
		return Vector2i(-1, -1)
	var start := rng.randi_range(0, cnt - 1)
	for k in cnt:
		var i := (start + k) % cnt
		var c := Vector2i(x0 + i % w, y0 + i / w)
		# `dist` 的鍵集就是「自由格」——不在界外、不在路徑上。
		if int(dist.get(c, -1)) < OFF_MIN or used.has(c):
			continue
		var clear := true
		for o: Vector2i in used.keys():
			if absi(o.x - c.x) + absi(o.y - c.y) < apart:
				clear = false
				break
		if clear:
			return c
	return Vector2i(-1, -1)


## 核心那一側、離路徑夠遠的自由格。保底補顆用。
static func _near_pool(dist: Dictionary, region: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in dist.keys():
		if int(dist[c]) >= OFF_MIN and region.has(c):
			out.append(c)
	return out


## 補單顆。候選不足就補多少算多少——真的不足時該紅的是 `endless_test`
## 的不變量斷言，不是這裡靜默補一格假的。
static func _singles(
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



## 每個自由格到最近路徑格的距離（多源 BFS，路徑格是源但不可通行）。
## **鍵集本身就是「自由格」的定義**——`has()` 同時涵蓋了界內與不在路徑上。
static func _dist_to_path(on_path: Dictionary) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = []
	for c: Vector2i in on_path.keys():
		queue.append(c)
	var head := 0
	var cur: Dictionary = {}
	for c: Vector2i in on_path.keys():
		cur[c] = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d := int(cur[c]) + 1
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb := c + dir
			if nb.x < 0 or nb.x >= W or nb.y < 0 or nb.y >= H:
				continue
			if on_path.has(nb) or cur.has(nb):
				continue
			cur[nb] = d
			dist[nb] = d
			queue.append(nb)
	return dist


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


static func _free(c: Vector2i, on_path: Dictionary) -> bool:
	return c.x >= 0 and c.x < W and c.y >= 0 and c.y < H and not on_path.has(c)
