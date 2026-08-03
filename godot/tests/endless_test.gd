extends SceneTree
## 無盡模式（B2.1a，`10_GDD.md` §7.10）。
##
## 這支測試守的是**「這張圖玩得動」**。手作地圖有設計者的眼睛把關，
## 生成器沒有——它每天會擲出幾千張沒有人看過的圖，所以第 5 條不變量
## （至少 3 個礦點不必過橋）不是形式檢查，是**唯一**能替代那雙眼睛的東西。
##
## 跑法：<godot> --headless --path godot --script res://tests/endless_test.gd

const T := preload("res://tests/_assert.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Maps := preload("res://data/Maps.gd")
const Enemies := preload("res://data/Enemies.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")

## 不變量掃過的種子數。**掃一個種子等於什麼都沒驗**——生成器的缺陷幾乎
## 都是「某些種子才踩得到」（`_other_y` 沒得選、核心區太小、跨越點撞入口）。
const SWEEP := 300

## ★ B2.1c 的四個門檻。**數字是實測值往回退一步訂的**，不是照著實測填的
## ——照實測填等於把「現在剛好長這樣」寫成規格，任何一點變動都會假紅。
## 實測：跨幅 min 28／死列 max 0／礦點全在帶內／孤點 12%。
const SPAN_MIN := 18
const REACH := 6
const DEAD_MAX := 6
const LONELY_MAX := 0.2


func _initialize() -> void:
	var t := T.new("endless_test")
	_determinism(t)
	_invariants(t)
	_waves(t)
	_best(t)
	quit(t.report())


# ── 不變量 1：同種子逐格相同 ────────────────────────────────────────
func _determinism(t: T) -> void:
	for s: int in [1, 42, 99991, -7]:
		var a := MapGen.generate(s)
		var b := MapGen.generate(s)
		for k: String in ["size", "core", "waypoints", "crossings", "ore", "start_ore"]:
			t.eq(a[k], b[k], "seed=%d 的 %s 逐格相同" % [s, k])
	t.ok(
		MapGen.generate(1)["waypoints"] != MapGen.generate(2)["waypoints"],
		"不同種子產生不同路徑"
	)


# ── 不變量 2–5 ─────────────────────────────────────────────────────
func _invariants(t: T) -> void:
	var self_cross := 0
	var bad_crossing := 0
	var ore_on_path := 0
	var ore_on_core := 0
	var thin_near := 0
	var worst_near := 99
	var out_of_bounds := 0
	var edge_hugging := 0
	var thin_span := 0
	var worst_span := 99
	var dead_rows := 0
	var worst_dead := 0
	var ore_off_band := 0
	var lonely := 0
	var ore_total := 0

	for i in SWEEP:
		var m := MapGen.generate(i * 7 + 1)
		var path: Array = Maps.path_of(m)
		var core: Vector2i = m["core"]
		var size: Vector2i = m["size"]

		var on_path: Dictionary = {}
		for c: Vector2i in path:
			if on_path.has(c):
				self_cross += 1
			on_path[c] = true
			if c.x < 0 or c.x >= size.x or c.y < 0 or c.y >= size.y:
				out_of_bounds += 1

		# 轉角上的橋是廢的（導管從那裡「過」會變成沿著路徑走）。索引比對，
		# 不是座標比對——同一格可能在路徑上出現在唯一位置，但轉角的判準是前後兩格。
		var corner: Dictionary = {}
		for j in range(1, path.size() - 1):
			var a: Vector2i = path[j - 1]
			var b: Vector2i = path[j + 1]
			if a.x != b.x and a.y != b.y:
				corner[path[j]] = true
		for c: Vector2i in m["crossings"]:
			if not on_path.has(c) or c == core or corner.has(c):
				bad_crossing += 1

		# 橫走離上下邊界至少 EDGE 列——說明面板寫的「退開 2 格就安全」
		# 要在每一張生成圖上都做得到。
		for p: Vector2i in m["waypoints"]:
			if p.y < MapGen.EDGE or p.y > size.y - 1 - MapGen.EDGE:
				edge_hugging += 1

		for c: Vector2i in m["ore"]:
			if on_path.has(c):
				ore_on_path += 1
			if c == core:
				ore_on_core += 1

		# ★ 不變量 6：路徑縱向跨幅（B2.1c）。舊版每段獨立抽列，走出來的是一條
		#   在窄帶裡折返的路徑——平均只跨 19.3 列、最差的種子只跨 8 列，
		#   於是整個下半區是玩家永遠不會去的死區。單調掃掠把這件事變成結構保證。
		var lo := size.y
		var hi := -1
		var rows: Dictionary = {}
		for c: Vector2i in path:
			lo = mini(lo, c.y)
			hi = maxi(hi, c.y)
			rows[c.y] = true
		var span := hi - lo + 1
		worst_span = mini(worst_span, span)
		if span < SPAN_MIN:
			thin_span += 1

		# ★ 不變量 7：死列——離任何路徑列超過 REACH 列的列。塔的射程與產線的
		#   合理長度都在這個尺度上，所以死列＝畫面上有、玩法上沒有的空間。
		var dead := 0
		for y in size.y:
			var near_row := false
			for ry: int in rows.keys():
				if absi(ry - y) <= REACH:
					near_row = true
					break
			if not near_row:
				dead += 1
		dead_rows += dead
		worst_dead = maxi(worst_dead, dead)

		# ★ 不變量 8：礦點離路徑落在容許帶內（B2.1c）。下限是 walk-by 打不到，
		#   上限是「這顆礦值不值得拉一條導管過去」。舊版 50% 的礦點超出上限。
		var ore: Array = m["ore"]
		var dist := _dist_to_path(on_path, ore)
		ore_total += ore.size()
		for c: Vector2i in ore:
			var d := int(dist.get(c, -1))
			if d < MapGen.OFF_MIN or d > MapGen.OFF_MAX:
				ore_off_band += 1
		# ★ 不變量 9：礦點成脈，不是撒點。孤點＝最近的另一顆礦在 VEIN_STEP
		#   的兩倍之外，也就是收不進同一條幹線。舊版 72% 是孤點。
		for a: Vector2i in ore:
			var nb := 9999
			for b: Vector2i in ore:
				if a != b:
					nb = mini(nb, absi(a.x - b.x) + absi(a.y - b.y))
			if nb > MapGen.VEIN_STEP * 2:
				lonely += 1

		# 「不必過橋」＝ 從核心的自由鄰格出發、只走非路徑格的四連通泛洪能到。
		# ★ 這裡**刻意重寫一次泛洪**，不呼叫 `MapGen._core_region()`——
		#   用生成器自己的函式驗生成器，測的是它跟自己一致，不是它對。
		var region := _flood(on_path, core, size)
		var near := 0
		for c: Vector2i in m["ore"]:
			if region.has(c):
				near += 1
		worst_near = mini(worst_near, near)
		if near < MapGen.NEAR_ORE:
			thin_near += 1

	t.eq(self_cross, 0, "%d 張圖：路徑一次都沒有自交" % SWEEP)
	t.eq(out_of_bounds, 0, "%d 張圖：路徑格全部在界內" % SWEEP)
	t.eq(bad_crossing, 0, "%d 張圖：跨越點全在路徑的直線段上（不是核心、不是轉角）" % SWEEP)
	t.eq(
		edge_hugging, 0,
		"%d 張圖：路徑沒有貼到上下邊界 %d 列以內（塔退得開 2 格）" % [SWEEP, MapGen.EDGE]
	)
	t.eq(ore_on_path, 0, "%d 張圖：礦點沒有一個落在路徑格上" % SWEEP)
	t.eq(ore_on_core, 0, "%d 張圖：礦點沒有一個壓在核心上" % SWEEP)
	t.eq(
		thin_near, 0,
		"%d 張圖：全部至少 %d 個礦點不必過橋（最差的一張有 %d 個）"
			% [SWEEP, MapGen.NEAR_ORE, worst_near]
	)

	t.eq(
		thin_span, 0,
		"%d 張圖：路徑縱向跨幅全部 ≥ %d 列（最窄的一張 %d 列，全高 %d）"
			% [SWEEP, SPAN_MIN, worst_span, MapGen.H]
	)
	t.ok(
		worst_dead <= DEAD_MAX,
		"%d 張圖：死列最多 %d 列（實測最差 %d，平均 %.1f）"
			% [SWEEP, DEAD_MAX, worst_dead, float(dead_rows) / float(SWEEP)]
	)
	t.eq(
		ore_off_band, 0,
		"%d 張圖：礦點全部離路徑 %d–%d 格（walk-by 打不到，又值得拉線過去）"
			% [SWEEP, MapGen.OFF_MIN, MapGen.OFF_MAX]
	)
	t.ok(
		float(lonely) / float(ore_total) <= LONELY_MAX,
		"%d 張圖：孤點 %.0f%% ≤ %.0f%%（礦點成脈，一條幹線收得完）"
			% [SWEEP, float(lonely) / float(ore_total) * 100.0, LONELY_MAX * 100.0]
	)

	# 數量落在宣告的範圍內（§7.10 的參數表）。
	var m0 := MapGen.generate(12345)
	t.ok(
		m0["ore"].size() >= MapGen.ORE_MIN and m0["ore"].size() <= MapGen.ORE_MAX,
		"礦點數在 %d–%d" % [MapGen.ORE_MIN, MapGen.ORE_MAX]
	)
	t.ok(
		m0["crossings"].size() >= MapGen.CROSS_MIN
			and m0["crossings"].size() <= MapGen.CROSS_MAX,
		"跨越點數在 %d–%d" % [MapGen.CROSS_MIN, MapGen.CROSS_MAX]
	)
	t.eq(m0["size"], Vector2i(MapGen.W, MapGen.H), "B2.1a 的尺寸仍是一屏可見")
	t.ok(bool(m0.get("endless", false)), "生成圖帶著 endless 旗標")
	t.eq(Maps.waves_of(m0), [], "生成圖沒有波次表——波次由公式長出來")


## 與 `MapGen._dist_to_path()` 各寫一份的距離場（理由同泛洪）。
## 這一份刻意用**最笨的寫法**：每格對全路徑取最小曼哈頓距離。生成器那份是
## 多源 BFS——兩種算法在路徑轉角處是會分岔的，所以這不只是抄一遍。
## 只算礦點那幾格——全格盤是 64×40×94×300 次，跑起來比整支測試還久。
func _dist_to_path(on_path: Dictionary, cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in cells:
		var best := 9999
		for p: Vector2i in on_path.keys():
			best = mini(best, absi(p.x - c.x) + absi(p.y - c.y))
		out[c] = best
	return out


## 與 `MapGen._core_region()` 各寫一份的泛洪（理由見上）。
func _flood(on_path: Dictionary, core: Vector2i, size: Vector2i) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for d: Vector2i in dirs:
		var c := core + d
		if _open(c, on_path, size):
			seen[c] = true
			queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d: Vector2i in dirs:
			var nb := c + d
			if _open(nb, on_path, size) and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	return seen


func _open(c: Vector2i, on_path: Dictionary, size: Vector2i) -> bool:
	return c.x >= 0 and c.x < size.x and c.y >= 0 and c.y < size.y and not on_path.has(c)


# ── 波次公式（§7.6／§7.10）──────────────────────────────────────────
func _waves(t: T) -> void:
	t.near(Enemies.endless_hp_mult(1), 1.0, "第 1 波是原始強度（倍率 1.0）")
	t.near(Enemies.endless_hp_mult(2), 1.11, "第 2 波 ×1.11")
	t.near(Enemies.endless_hp_mult(11), pow(1.11, 10.0), "第 11 波 ×1.11^10")

	t.eq(Enemies.endless_count(1), 4, "第 1 波 4 隻")
	t.eq(Enemies.endless_count(3), 5, "第 3 波 5 隻")
	t.eq(Enemies.endless_count(30), 14, "第 30 波 14 隻")

	# 敵種池：與戰役同一條登場順序（護甲先教、能量抗性後教）。
	t.eq(Enemies.endless_pool(1), ["drifter"], "前兩波只出漂蟲")
	t.ok(Enemies.endless_pool(3).has("carapace"), "第 3 波起有甲殼")
	t.ok(not Enemies.endless_pool(5).has("ember"), "第 5 波還沒有熾泳")
	t.ok(Enemies.endless_pool(6).has("ember"), "第 6 波起有熾泳")

	# 出場表：同 (seed, wave) 必得同一張；不同波必不同流。
	t.eq(
		Enemies.endless_schedule(42, 9), Enemies.endless_schedule(42, 9),
		"同 (seed, wave) 得到同一張出場表"
	)
	var w9: Array = Enemies.endless_schedule(42, 9)
	t.eq(w9.size(), Enemies.endless_count(9), "出場表長度＝該波隻數")
	t.near(float(w9[0]["at"]), 0.0, "第一隻在 0 秒出場")
	t.near(
		float(w9[w9.size() - 1]["at"]),
		Enemies.ENDLESS_GAP * float(w9.size() - 1),
		"間隔是固定的 %.1f 秒（不另給第三條曲線）" % Enemies.ENDLESS_GAP
	)
	# 池外的敵種一隻都不該出現——池的意義就在這裡。
	var leaked := 0
	for w in range(1, 3):
		for e: Dictionary in Enemies.endless_schedule(42, w):
			if not Enemies.endless_pool(w).has(String(e["type"])):
				leaked += 1
	t.eq(leaked, 0, "出場表不會排出當波敵種池以外的敵人")


# ── 個人最佳（§7.10）───────────────────────────────────────────────
func _best(t: T) -> void:
	# 舊存檔（沒有 endless 鍵）讀進來自動長出 0/0——這是「沒有 bump
	# SAVE_VERSION」那個決定的實質斷言。
	var old := SaveService.normalize({"sv": 2, "tech": {"unlocked": [], "data": 5}})
	t.eq(int((old["endless"] as Dictionary)["best_wave"]), 0, "舊存檔補出 best_wave=0")
	t.eq(float(old["tech"]["data"]), 5.0, "補鍵不會動到玩家原有的資料")

	var d := SaveService.defaults()
	var r1 := SaveService.apply_endless(d, 12, 0.8)
	t.ok(bool(r1["wave"]) and bool(r1["output"]), "第一局兩欄都是新紀錄")
	t.eq(int(d["endless"]["best_wave"]), 12, "波次寫進去了")

	# ★ 兩欄各自取最大值：波次更高但產能更差的一局，**不得**洗掉產能紀錄。
	var r2 := SaveService.apply_endless(d, 13, 0.3)
	t.ok(bool(r2["wave"]), "波次破紀錄")
	t.ok(not bool(r2["output"]), "產能沒破紀錄")
	t.eq(int(d["endless"]["best_wave"]), 13, "波次更新為 13")
	t.near(float(d["endless"]["best_output"]), 0.8, "產能紀錄保住 0.8，沒被更差的一局洗掉")

	var r3 := SaveService.apply_endless(d, 5, 0.2)
	t.ok(not bool(r3["wave"]) and not bool(r3["output"]), "更差的一局兩欄都不破")
	t.eq(int(d["endless"]["best_wave"]), 13, "更差的一局不會讓紀錄倒退")

	# 存檔往返：normalize 之後數字還在（JSON 會把 int 讀成 float，這裡釘住口徑）。
	var back := SaveService.normalize(d)
	t.eq(int(back["endless"]["best_wave"]), 13, "normalize 往返後 best_wave 不變")
	t.near(float(back["endless"]["best_output"]), 0.8, "normalize 往返後 best_output 不變")
