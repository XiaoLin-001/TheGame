extends Node
## 局內畫面的測試鉤子執行者（`TL_CLICKTEST`／`TL_STRESS`／示範佈局）。
##
## 這個檔案**只在有 `TL_*` 鉤子時才有事做**，一般遊玩時它整支閒置。拆出來是因為它是
## 局內畫面裡最大的一塊（約 1200 行），而且全是葉節點：沒有任何遊戲邏輯呼叫它。
##
## ★ 輸入層自檢（`TL_CLICKTEST=1`）**用合成的滑鼠事件真的走一次 Godot 的輸入路由**——
## 不是直接呼叫 `_act()`，那樣測不到 `mouse_filter` 這一層，而 B0.7.2 的缺陷正好就在那一層
## （滿版 `Control` 預設 `STOP`，把事件吃掉，地圖五批都點不動）。
## ⚠ **必須開真視窗跑，`--headless` 過不了**：dummy display server 不做 GUI 滑鼠命中測試。
## 它是唯一一個不能 headless 的檢查——也正是它抓得到別的檢查都抓不到的東西。
##   `TL_CLICKTEST=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3`
## 約 1 秒後自己退出（0 ＝ PASS）。

## 自檢的探針與斷言會讀寫畫面層的私有狀態，所以這個模組是畫面層的「友軍」：
## 它直接用 `scr._xxx` 的原名，不要求那些成員公開。

const Stage2D := preload("res://scripts/screens/battle/Stage2D.gd")
const Overlay2D := preload("res://scripts/screens/battle/Overlay2D.gd")
const Feedback := preload("res://scripts/screens/battle/Feedback.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組（Feedback）。
var feedback: Feedback = null
## 同伴模組（Overlay2D）。
var overlay: Overlay2D = null
## 同伴模組（Stage2D）。
var stage: Stage2D = null


## `TL_STRESS`：丟掉的暖身幀數與實際量測幀數。
const STRESS_WARMUP := 30

const STRESS_FRAMES := 240

## `TL_STRESS` 的量測狀態。
var _stress_frames: int = 0

var _stress_total: float = 0.0

var _stress_worst: float = 0.0


## ★ 輸入層自檢（`TL_CLICKTEST=1`）。**用合成的滑鼠事件真的走一次 Godot 的
## 輸入路由**——不是直接呼叫 `_act()`，那樣測不到 `mouse_filter` 這一層，
## 而 B0.7.2 的缺陷正好就在那一層（滿版 `Control` 預設 `STOP`，把事件吃掉，
## `_unhandled_input` 從來沒被呼叫過，地圖五批都點不動）。
##
## 這支自檢存在的意義就是「那個缺陷不會再發生一次而沒人知道」。
##
## ⚠ **必須開真視窗跑，`--headless` 過不了**：dummy display server 不做 GUI
## 滑鼠命中測試，`_gui_input` 完全不會被呼叫。它是唯一一個不能 headless 的
## 檢查——這也正是它抓得到的東西別的檢查都抓不到的原因。
##   `TL_CLICKTEST=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3`
## 約 1 秒後自己退出（0 ＝ PASS）。
## ★ 每一種可建造節點都要畫得出一個圖形（B2.4.6）。
##
## **這一條是使用者用眼睛抓到的**（「長哨沒有模型顯示」），而 B2.4 當批
## 1290 條斷言全綠——因為十五支測試驗的是數值與流量，**沒有一支看畫面**。
## 三隻招募塔的資料表、戰鬥、耗電、存檔、招募全部正確，只是在地圖上是透明的。
##
## 手法：把每一種 `BUILDABLE` 直接塞進 `s.nodes`（`add_node` 不走成本與放置規則），
## 逼 `_draw_nodes()` 跑過每一個分支，再看 `_no_glyph` 有沒有東西。測完立刻移除，
## 所以它對後面每一條斷言都是不可見的。
##
## 探針格 `(-9, -9)` 在地圖外：任何實際格都可能被後面的建造斷言用到。
func _glyph_selftest() -> void:
	var before: int = s.nodes.size()   # `s.nodes` 未標型別 → `:=` 推不出來，會編譯錯
	# ★ 同時給 `TL_SHOT` 時排成一列**留在畫面上**：斷言只證明「有畫東西」，
	#   證明不了「一眼分得出是哪一隻」。後者只有人眼判得了，而那張圖沒有這個
	#   鉤子就拍不到——招募塔要有券才蓋得出來，零進度存檔永遠擺不出這一排。
	var gallery: bool = Hooks.shot_path != ""
	for i in NodeDefs.BUILDABLE.size():
		var ty := String(NodeDefs.BUILDABLE[i])
		s.add_node(ty, Vector2i(4 + i * 2, 14) if gallery else Vector2i(-9, -9))
	# ★ 敵人也排一列（B3.2）。**六隻在同一張圖上才判得出「一眼分得開嗎」**——
	#   而 M3 的三隻只在無盡第 9／12／15 波之後才出場，沒有這個鉤子就要打二十分鐘
	#   才拍得到一張合照。斷言只證明「畫得出東西」，分不分得開仍然是人眼判的。
	if gallery:
		var types: Array = Enemies.DEFS.keys()
		for i in types.size():
			var id: int = s.add_enemy(String(types[i]))
			for e: Dictionary in s.enemies:
				if int(e["id"]) == id:
					e["progress"] = float(4 + i * 3)
	# ★ 合照裡順便排出**升級級數的階梯**（B3.5，★ B3.9 改寫）：
	#   **同一種塔的 0..5 級排成第二列**。
	#
	#   B3.8 之前這個階梯是設在上面那一列的第 2..6 座上，而那是採集器、發電機、
	#   熔爐、中繼、儲槽——**五種不同的形狀，而且五級全都是「出力」**。
	#   於是這張照片答不了它唯一要答的兩個問題：一級和五級**大小**分得出來嗎
	#   （不同型別本來就不一樣大）、零件的**形狀**分得出來嗎（全是出力，只長托架）。
	#   換成一排錨之後兩個都答得了：它的階梯是 出力 → 射速 → 射程 → 出力 → 射速，
	#   四種形狀裡出現三種，而六座並排的塔身只差在級數。
	#   直接設欄位不走 `upgrade_node()`：這是**畫面**的驗收，不是規則的
	#   （規則由 `combat_test` 顧）。
	if gallery:
		for k in Build.NODE_MAX_LEVEL + 1:
			# `s` 未標型別 → `:=` 推不出來，會編譯錯（CLAUDE.md 的嚴格型別地雷）
			var id: int = s.add_node("anchor", Vector2i(4 + k * 2, 17))
			for n: Dictionary in s.nodes:
				if int(n["id"]) == id:
					n["level"] = k
	# ★ **擺放預覽也留在同一張圖上**（B3.4）。它擺在那一排真節點的正上方，
	#   所以這張圖同時回答兩件事：預覽畫的是不是那隻角色的形狀、
	#   以及它和真的蓋出來那一個長不長得一樣。
	#   預覽只在「選了一種節點 ＋ 滑鼠在圖上」的那一刻存在——那是純互動狀態，
	#   沒有這個鉤子就拍不到，於是那句「有預覽了」只能用宣稱的。
	#   選碎浪：四角爆散星是最不像方框的一個，證明力最強。
	if gallery:
		scr.mode = scr.Mode.BUILD
		scr.build_type = "breaker"
		scr.hover = Vector2i(10, 11)
		# ★ 順便把**檢視**留在畫面上（B3.6）：選一座塔，射程圈、數據面板與
		#   「誰在餵它電」的高亮都只有在選取狀態下存在，那也是純互動狀態。
		#   選錨（合照那一排的第 6 個）——它有射程，圈畫得出來。
		# 挑一座**真的接了線**的塔：合照那一排是憑空長出來的，沒有任何導管，
		# 而「誰在餵它電」正是要靠導管才答得出來的問題。
		# ★ B3.7：`TL_PICK=wire` 改成選一條導管——導管面板同樣是純互動狀態。
		#   挑**這一刻真的有東西在流**的那一條：面板上「流量 x / cap」與「已滿載」
		#   是這一批要看的東西，選一條靜止的線只證明得了版面。
		if Hooks.pick == "wire" and not s.conduits.is_empty():
			var flows: Dictionary = s.rates["conduit_flow"]
			var best := 0
			for i in s.conduits.size():
				if float(flows.get((s.conduits[i])["id"], 0.0)) > float(
					flows.get((s.conduits[best])["id"], 0.0)
				):
					best = i
			scr._select_wire(int((s.conduits[best])["id"]))
		for n: Dictionary in s.nodes:
			if scr._sel_wire >= 0:
				break
			var ty := String(n["type"])
			if float(NodeDefs.of(ty).get("range", 0.0)) <= 0.0:
				continue
			# 跳過自己會發電的那兩種（回收者／儲槽）：它們的「供電」欄位講的是
			# 另一件事，而合照要示範的是最常見的情況——一座塔、幾台發電機。
			if ty in ["reclaimer", "silo"]:
				continue
			var wired := false
			for c: Dictionary in s.conduits:
				if c["a"] == n["cell"] or c["b"] == n["cell"]:
					wired = true
					break
			if not wired:
				continue
			# **優先挑正在交戰的那一座**：不交戰就不吃電，不吃電就沒有電流，
			# 而「誰在餵它電」正是要有電流才看得到的東西。挑錯的話合照上
			# 只會有一個射程圈，證明不了這一批真正做的那件事。
			scr.selected = n["cell"]
			if bool(stage.engaged.get(int(n["id"]), false)):
				break
	stage._no_glyph.clear()
	scr.redraw()
	await _frames(2)
	var missing := PackedStringArray()
	for ty: Variant in stage._no_glyph:
		missing.append(String(ty))
	missing.sort()
	if not gallery:
		s.nodes.resize(before)
	stage._no_glyph.clear()
	scr.redraw()
	# ★ 圖鑑說明是**同一個缺陷的另一半**：`_codex_lines()` 也是一張以 type 為鍵的
	#   表，`.get(type, "")` 漏掉時的症狀是「說明那一行是空白的」——一樣不會報錯。
	#   兩件事一起驗，因為它們是同一個錯法。
	var blank := PackedStringArray()
	for ty: String in NodeDefs.BUILDABLE:
		if scr._codex_lines(ty).size() < 2 or String(scr._codex_lines(ty)[1]).strip_edges() == "":
			blank.append(ty)
	blank.sort()
	var ok: bool = missing.is_empty() and blank.is_empty()
	print("[TL_CLICKTEST/glyph] %d 種節點｜畫不出來的：%s｜圖鑑沒說明的：%s → %s" % [
		NodeDefs.BUILDABLE.size(),
		"（無）" if missing.is_empty() else ",".join(missing),
		"（無）" if blank.is_empty() else ",".join(blank),
		"PASS" if ok else "FAIL",
	])
	# 隱形的塔是完整缺陷，不併進後面那個 `ok` ——直接擋掉。
	if not ok and Hooks.shot_path == "":
		get_tree().quit(1)


## ★ 頂欄的版面不得隨數值變動（§3 硬性要求：「資源數字跳動時不得左右位移」，B-3）。
##
## **這一條原本是用 grep 推的**（`tabular|FontVariation|monospace` 零命中 → 宣稱
## 「每秒橫向抖十次」），而 A-3 已經教過一次：沒有量過的宣稱只是一個願望（RG-141）。
## 所以先有這支量測，再談要不要修。
##
## 量兩件事，因為它們的難度不同：
##   ① **同位數不同數字**（1111 → 8888）：等寬數字（tabular figures）就擋得住。
##   ② **不同位數**（1111 → 99）：等寬數字擋不住，只有固定寬度容器擋得住。
## §3 的正文要的是②（「數字跳動時不得左右位移」沒有限定位數），備案也是②。
func _topbar_selftest() -> void:
	var ore_before: float = s.ore
	var xs := func() -> PackedFloat32Array:
		var out := PackedFloat32Array()
		for c: Node in scr._top.get_children():
			out.append((c as Control).global_position.x)
		return out
	var same := func(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
		if a.size() != b.size():
			return false
		for i in a.size():
			if absf(a[i] - b[i]) > 0.5:
				return false
		return true
	s.ore = 1111.0
	scr._refresh_top()
	await get_tree().process_frame
	var base: PackedFloat32Array = xs.call()
	s.ore = 8888.0
	scr._refresh_top()
	await get_tree().process_frame
	var digits_ok: bool = same.call(base, xs.call())
	s.ore = 99.0
	scr._refresh_top()
	await get_tree().process_frame
	var width_ok: bool = same.call(base, xs.call())
	s.ore = ore_before
	scr._refresh_top()
	print("[TL_CLICKTEST/topbar] 同位數不位移=%s 任意位數不位移=%s → %s" % [
		digits_ok, width_ok, "PASS" if (digits_ok and width_ok) else "FAIL",
	])


func click_selftest() -> void:
	# ★★ **看門狗**（B3.6）。自檢裡的任何一個執行期錯誤都會**中止這支函式**，
	#   於是最後那行 `quit()` 跑不到——視窗就一直開著，而 `CLAUDE.md` 鐵律 3 是
	#   「絕不在沒有測試鉤子的情況下開遊戲視窗」。有鉤子卻不會關，等於同一件事。
	#   （B3.6 當場踩到：索引了一個不存在的模式鈕，測試掛住 5 分鐘。）
	#   `TL_SHOT` 在場時不設——那條路徑本來就是要把畫面留著給截圖。
	if Hooks.shot_path == "":
		_watchdog()
	await get_tree().process_frame
	await get_tree().process_frame
	await _glyph_selftest()
	await _topbar_selftest()
	if Hooks.panel == "endless":
		await _guide_selftest()
		return
	# 有示範佈局在場時只驗浮層：地圖上的格子被佔走了，建造斷言本來就不成立。
	if s.nodes.size() > 1:
		scr._energy_button.button_pressed = true
		scr._on_codex_show("prism", scr._build_buttons["prism"])
		print("[TL_CLICKTEST] 示範佈局在場，只開浮層（建造斷言略過）")
		return
	var ore: Vector2i = (s.map["ore"] as Array)[0]
	var on_path: Vector2i = s.path[10]
	var before: int = s.nodes.size()

	_click(ore)
	await _frames(3)
	var placed: bool = s.nodes.size() == before + 1

	_click(on_path)          # 路徑格禁節點 → 要被擋下且**說明原因**
	await _frames(3)
	var rejected: bool = s.nodes.size() == before + 1 and scr._message.begins_with("✕")

	# ★ 45° 導管（使用者回報「沒辦法 45 度放置管道」）：在礦點的正斜角放一個
	#   中繼，再從一端拖到另一端。整條路徑都走真實輸入——包含按鈕。
	_press(scr._build_buttons["relay"])
	var from := Vector2i(10, 10)
	var to := Vector2i(13, 13)     # 正斜角，且遠離路徑（路徑走 y=4 與 x=30）
	_click(from)
	_click(to)
	await _frames(3)
	var diag_placed: bool = s.nodes.size() == before + 3
	_drag(from, to)
	await _frames(3)
	var wired: bool = s.conduits.size() == 1

	# ★ 使用者回報：「45 度的線似乎沒辦法加粗」（B1.2.1）。一格長的 45°——
	#   兩個對角相鄰的節點之間——連一個中間格都沒有，舊的格子命中判定必然落空。
	#   ★ B3.7.1：升級模式沒有了，這條改走**選取 → 面板加粗**的新路徑。
	#     驗的仍然是同一件事：**那個像素點命不命中得到這條線**，那才是當年壞掉的地方。
	_press(scr._build_buttons["relay"])
	_click(Vector2i(6, 12))
	_click(Vector2i(7, 13))
	await _frames(3)
	_drag(Vector2i(6, 12), Vector2i(7, 13))
	await _frames(3)
	_click_at(stage.to_screen((stage.center(Vector2i(6, 12)) + stage.center(Vector2i(7, 13))) * 0.5))
	await _frames(3)
	var short_diag: int = s.conduit_near(Vector2(6.5, 12.5))
	var picked_diag: bool = short_diag >= 0 and scr._sel_wire == int((s.conduits[short_diag])["id"])
	if picked_diag:
		_click_button(scr._inspect_up)
		await _frames(3)
	short_diag = s.conduit_near(Vector2(6.5, 12.5))
	var upgraded: bool = (
		picked_diag and short_diag >= 0 and int((s.conduits[short_diag])["level"]) == 1
	)

	# ★ 局內臨時升級一座**建築**（§4.3、B3.5）。★ B3.7.1 改走面板上那顆鈕。
	#   斷言三件事：級數真的加了、礦砂**真的扣了**、而且扣的是那個價
	#   （只驗級數的話，一個免費升級的實作照樣全綠）。
	var lvl_cell := Vector2i(6, 12)
	_click(lvl_cell)
	await _frames(3)
	var ore_before: float = s.ore
	var price := Build.node_upgrade_cost(NodeDefs.cost("relay"), 0)
	_click_button(scr._inspect_up)
	await _frames(3)
	var node_lvl: bool = int(s.node_at(lvl_cell).get("level", 0)) == 1
	var node_paid: bool = is_equal_approx(s.ore, ore_before - float(price))
	# ★ **鈕不得在按下之後跑掉**（B3.9.1，使用者回報「點了升級之後，滑鼠會位移到
	#   一個很奇怪的位置」）。位移的不是游標是面板——見 `_place_inspect` 那段。
	var btn_at: Vector2 = scr._inspect_up.global_position
	var btn_drift := 0.0
	# 上限是規則：連按八次也只到 5 級（B3.9；滿級之後那顆鈕自己會關掉）。
	for _i in 8:
		_click_button(scr._inspect_up)
		await get_tree().process_frame
		btn_drift = maxf(btn_drift, btn_at.distance_to(scr._inspect_up.global_position))
	var node_cap: bool = int(s.node_at(lvl_cell).get("level", 0)) == Build.NODE_MAX_LEVEL
	# ⚠ 上面那一條只量得到「這一輪的字剛好有沒有變長」——**在舊程式碼下它照樣是
	#   綠的**（中繼那一格升五級，最長的一行沒變）。所以再直接量**規矩本身**：
	#   同一個選取餵兩份長短差很多的內容進去，x 與**底邊**必須一樣
	#   （頂邊本來就該隨內容上下長）。
	# 型別陣列字面量經過動態呼叫會退化成 untyped `Array`，所以先明寫型別再傳。
	var short_lines: Array[String] = ["短"]
	scr._place_inspect(short_lines)
	await get_tree().process_frame
	var box_short := Rect2(scr._inspect_panel.position, scr._inspect_panel.size)
	var long_lines: Array[String] = []
	for _i in 12:
		long_lines.append("這一行刻意寫得很長很長很長很長很長很長很長很長很長很長")
	scr._place_inspect(long_lines)
	await get_tree().process_frame
	var box_long := Rect2(scr._inspect_panel.position, scr._inspect_panel.size)
	var pos_stable: bool = (
		absf(box_short.position.x - box_long.position.x) < 0.5
		and absf(box_short.end.y - box_long.end.y) < 0.5
	)
	# ⚠ 量完要**把尺寸也收掉**，不只是內容：面板是直接掛在畫面上的自由 Control，
	#   而 Godot 只讓這種 Control 長到最小尺寸、**不會自己縮回去**。留著那 12 行
	#   撐出來的 552px 高度，後面那條中鍵平移就拖不動了（當場紅了一次）。
	scr._inspect_panel.size = Vector2.ZERO
	scr._refresh_inspect()
	var btn_still: bool = btn_drift < 0.5 and pos_stable
	# 收起來，交給下一段從零開始驗「點一下就開」。
	_click(lvl_cell)
	await _frames(3)

	# ★ 點一下建築＝檢視它（§B3.6）。走完整輸入路徑，因為這是一個**新的點擊語意**
	#   （舊行為是「這一格已經有東西了」）。三條斷言：面板真的開了、
	#   上面寫的是那一座、再點一次會收起來（選取是**開關**不是單向）。
	# ⚠ **不要索引一個不存在的模式鈕**——B3.7.1 之後底欄只剩「藍圖」一顆。
	#   索引不存在的鍵會丟執行期錯誤，而那會**中止整支自檢**：`quit()` 跑不到，
	#   視窗就一直開著（RG-164 的同一個形狀，B3.6 當場踩過）。
	_click(lvl_cell)
	await _frames(3)
	var sel_open: bool = scr.selected == lvl_cell and scr._inspect_panel != null and scr._inspect_panel.visible
	var sel_says: bool = sel_open and scr._inspect_label.text.contains(NodeDefs.label("relay"))
	# ★ 面板要**整個在畫面內**（RG-139／RG-149／RG-170 的同一句話第四次）。
	var sel_inside: bool = sel_open and (
		scr._inspect_panel.position.x >= 0.0
		and scr._inspect_panel.position.y >= 0.0
		and scr._inspect_panel.position.x + scr._inspect_panel.size.x <= float(scr.size.x) + 0.5
		and scr._inspect_panel.position.y + scr._inspect_panel.size.y <= float(scr.size.y) + 0.5
	)
	# ★ 和右上的能量面板**不得相交**（RG-162 那條，套在新的浮層上）。
	#   兩個都開著才驗得到，所以先確定能量面板是開的。
	var sel_clear := true
	if scr._energy_panel != null and scr._energy_panel.visible and scr._inspect_panel.visible:
		sel_clear = not Rect2(scr._energy_panel.position, scr._energy_panel.size).intersects(
			Rect2(scr._inspect_panel.position, scr._inspect_panel.size)
		)
	_click(lvl_cell)
	await _frames(3)
	var sel_toggles: bool = scr.selected.x < 0 and not scr._inspect_panel.visible

	# ★ 拖曳拉線（B1.6.2）：**全程停在建造模式**。會壞的地方有兩個——按下時
	#   沒把起點記起來、放開的事件沒被路由到——而兩個都只有真的送出
	#   「按下 → 移動 → 放開」三顆事件才驗得出來。
	_press(scr._build_buttons["relay"])
	_click(Vector2i(3, 8))
	_click(Vector2i(3, 11))
	await _frames(3)
	var wires_before: int = s.conduits.size()
	_drag(Vector2i(3, 8), Vector2i(3, 11))
	await _frames(3)
	var dragged: bool = s.conduits.size() == wires_before + 1 and scr.mode == scr.Mode.BUILD

	# ★ 點一條導管＝檢視它，動詞在面板上（B3.7，使用者提出）。
	#   剛拉出來那一條 (3,8)–(3,11) 是垂直三格，兩端點的中點正壓在線上。
	#   走完整輸入路徑：這是**建造模式下的一個新點擊語意**（舊行為是在那一格蓋東西），
	#   而「按下那一刻走哪一條分支」只有真的送事件才驗得出來（B3.6 的教訓）。
	# ⚠ **先把能量面板打開**。版面那一條要驗的正是「讓不讓得開鄰居」，而面板關著時
	#   檢視面板貼在 y=56、離能量面板和小地圖都有幾百像素——那樣的斷言是**恆真**的。
	#   （量了才知道：關著時它在 y 56–230，小地圖在 525–648。）
	scr._energy_button.button_pressed = true
	await get_tree().process_frame
	var wire_mid := stage.to_screen((stage.center(Vector2i(3, 8)) + stage.center(Vector2i(3, 11))) * 0.5)
	var wire_id: int = int((s.conduits[s.conduits.size() - 1])["id"])
	_click_at(wire_mid)
	await _frames(3)
	var wire_sel: bool = (
		scr._sel_wire == wire_id and scr._inspect_panel != null and scr._inspect_panel.visible
		and scr._inspect_label.text.contains("導管") and scr.selected.x < 0
	)
	# 再點一次＝取消（選取是開關；沒有這條的話面板一開就關不掉，而它蓋著右半邊）。
	_click_at(wire_mid)
	await _frames(3)
	var wire_toggle: bool = scr._sel_wire < 0 and not scr._inspect_panel.visible
	_click_at(wire_mid)
	await _frames(3)
	# ★ 版面規則對**兩種選取都要成立**（RG-139／149／162／170 的同一句話）：
	#   整個在畫面內、不疊能量面板、不疊小地圖那一角。導管面板比節點面板更高
	#   （多一行「加粗後」），所以它才是會先掉出去的那一個。
	var wire_rect := Rect2(scr._inspect_panel.position, scr._inspect_panel.size)
	var wire_fits: bool = (
		scr._inspect_panel.visible
		and wire_rect.position.x >= 0.0 and wire_rect.position.y >= 0.0
		and wire_rect.end.x <= float(scr.size.x) + 0.5 and wire_rect.end.y <= float(scr.size.y) + 0.5
		and not wire_rect.intersects(overlay.minimap_rect())
		and not (
			scr._energy_panel != null and scr._energy_panel.visible
			and Rect2(scr._energy_panel.position, scr._energy_panel.size).intersects(wire_rect)
		)
	)
	# 加粗鈕：級數真的加了、礦砂**真的扣了**、而且扣的是那個價
	#   （只驗級數的話，一個免費加粗的實作照樣全綠——B3.5 那條的同一句話）。
	var w_ore0: float = s.ore
	var w_price := Build.upgrade_cost(0)
	_click_button(scr._inspect_up)
	await _frames(3)
	var wi_now: int = scr.sel_wire_index()
	var wire_up: bool = wi_now >= 0 and int((s.conduits[wi_now])["level"]) == 1 and (
		is_equal_approx(s.ore, w_ore0 - float(w_price))
	)
	# 拆除鈕：線真的少一條、退款進帳、而且**選取跟著收掉**（拆掉的東西不能繼續選著）。
	var w_ore1: float = s.ore
	var w_refund := BuildController.conduit_refund(s.conduits[maxi(wi_now, 0)])
	var wires_now: int = s.conduits.size()
	_click_button(scr._inspect_del)
	await _frames(3)
	var wire_del: bool = (
		s.conduits.size() == wires_now - 1 and scr._sel_wire < 0
		and not scr._inspect_panel.visible and is_equal_approx(s.ore, w_ore1 + float(w_refund.x))
	)

	# ★ 同兩顆鈕的**節點**那一半：選一座建築，升級與拆除都在面板上。
	#   上一段驗的是加粗（導管），這一段是同兩顆鈕的另一半（建築）。
	var nd_cell := Vector2i(3, 11)
	_click(nd_cell)
	await _frames(3)
	var n_ore0: float = s.ore
	var n_price := Build.node_upgrade_cost(NodeDefs.cost("relay"), 0)
	_click_button(scr._inspect_up)
	await _frames(3)
	var node_btn_up: bool = int(s.node_at(nd_cell).get("level", 0)) == 1 and (
		is_equal_approx(s.ore, n_ore0 - float(n_price))
	)
	var n_ore1: float = s.ore
	var n_refund := BuildController.node_refund("relay")
	_click_button(scr._inspect_del)
	await _frames(3)
	var node_btn_del: bool = (
		s.node_at(nd_cell).is_empty() and scr.selected.x < 0 and not scr._inspect_panel.visible
		and is_equal_approx(s.ore, n_ore1 + float(n_refund.x))
	)
	# ★ **核心兩顆鈕都不該在**：它升不得也拆不得，而一顆按下去保證失敗的鈕
	#   是在邀請玩家犯錯。規則層擋著（`upgrade_node()`／`demolish()`），
	#   這一條驗的是畫面沒有和規則講反話。
	var core_cell: Vector2i = s.nodes[0]["cell"]
	for n0: Dictionary in s.nodes:
		if String(n0["type"]) == "core":
			core_cell = n0["cell"]
			break
	_click(core_cell)
	await _frames(3)
	var core_verbs: bool = (
		scr.selected == core_cell and scr._inspect_panel.visible
		and not scr._inspect_up.visible and not scr._inspect_del.visible
	)
	_click(core_cell)
	await _frames(3)

	# ★ B3.8：**升級鈕要說出這一級買到的是什麼**（使用者：「每次升級有不同效果」）。
	#   規則本身由 `combat_test` 的階梯斷言顧；這裡驗的是**它有沒有走到鈕上**。
	#   用錨——它的三級是 出力 → 射速 → 射程，所以連按兩次鈕上的字必須換過。
	#   一個把鈕文字寫死成「升級」的實作在別處全綠，只有這一條抓得到。
	var step_cell := Vector2i(9, 9)
	for r2 in 10:
		var cand2 := Vector2i(9 + r2, 9)
		if stage.in_map(cand2) and String(
			BuildController.preview_place(s, "anchor", cand2)["reason"]
		) == Build.OK:
			step_cell = cand2
			break
	_press(scr._build_buttons["anchor"])
	s.ore += 500.0
	_click(step_cell)
	await _frames(3)
	_click(step_cell)          # 蓋完再點一下＝選取它
	await _frames(3)
	var step_lv0: String = scr._inspect_up.text
	_click_button(scr._inspect_up)
	await _frames(3)
	var step_lv1: String = scr._inspect_up.text
	var step_says: bool = (
		not s.node_at(step_cell).is_empty()
		and step_lv0.contains(scr._step_text(Build.STEP_POWER))
		and step_lv1.contains(scr._step_text(Build.STEP_ROF))
		and step_lv0 != step_lv1
	)

	# ★ 中鍵平移（B1.3.1）：「移動」模式鈕拿掉之後，**這是唯一的平移路徑**。
	#   先放大（fit 倍率下平移恆被夾成 0，量不到東西）。
	scr._on_zoom(stage.ZOOM_STEP * stage.ZOOM_STEP)
	var pan_before := stage.pan
	# 中鍵拖曳＝「移動」模式鈕拿掉之後唯一的平移路徑（B1.3.1），所以它得有自檢。
	_drag_px(Vector2(600, 400), Vector2(540, 360), MOUSE_BUTTON_MIDDLE)
	await _frames(3)
	var panned: bool = stage.pan != pan_before
	scr._on_zoom_reset()

	# ★ B1.1：建造欄從 8 顆長到 10 顆（＋熔爐＋碎浪），高度逼近底欄。
	#   **最後一顆鈕還點不點得到**是這件事唯一該問的問題——鈕被擠出畫面時
	#   `_draw()` 完全不會抱怨，就跟 B0.7.2 那個 size (0,0) 的 bug 一樣。
	#   最後那一顆要合金（帳上 0）→ 會被擋下，但**擋下的理由必須是「合金不夠」**，
	#   不能是「這顆鈕根本沒被按到」。
	#
	# ★ **不寫死型別名**（B2.4）：這裡原本斷言 `_build_type == "breaker"`，而
	#   B2.4 在表尾接了三隻新角色之後，「最後一顆」就不再是碎浪了——測試變紅，
	#   但壞掉的是斷言不是功能。改成問「表尾那一個是誰」，並**另外斷言它真的
	#   要合金**：少了後半句，表尾哪天換成不用合金的節點，這條會安靜地變成空操作。
	# ★★★★ **「按得到」不等於「看得到」**（B2.4.2，RG-139）。這一條原本只驗
	#   最後一顆**建造鈕**的 y，而 `_press()` 是往 `global_position + size*0.5` 送
	#   合成事件的——**一顆被底欄蓋住、甚至被推到畫面外的鈕，照樣按得到**。
	#   B2.4 把可建造類型加到 13 種，「加粗／拆除」和底欄疊在一起、「藍圖」整顆
	#   掉出畫面，而 `blueprint=true` 全程沒紅過。
	#
	#   所以判準改成**幾何的**，而且分兩種東西問——**捲出去的清單項目本來就在
	#   視窗外，那是合法的**，會害人的是被**釘住卻被擠出去**的那幾顆：
	#     ① 三顆模式鈕與捲動容器本身：永遠不得越過底欄（它們不會捲）。
	#     ② 最後一顆建造鈕：**捲到底之後**必須整顆在捲動視窗內（同科技樹 RG-47）。
	var last_type: String = String(scr._buildable()[scr._buildable().size() - 1])
	var last_button: Button = scr._build_buttons[last_type]
	var pinned_ok: bool = scr._build_scroll.global_position.y + scr._build_scroll.size.y <= scr.BAR_Y
	for b: Variant in scr._mode_buttons.values():
		var btn := b as Button
		if btn.global_position.y + btn.size.y > scr.BAR_Y:
			pinned_ok = false
	scr._build_scroll.scroll_vertical = int(scr._build_scroll.get_v_scroll_bar().max_value)
	await get_tree().process_frame
	var view := Rect2(scr._build_scroll.global_position, scr._build_scroll.size)
	var reachable: bool = (
		pinned_ok
		and last_button.size.y >= 44.0
		and view.encloses(Rect2(last_button.global_position, last_button.size))
	)
	# ★ 捲回頂端。自檢**不得留下狀態**——`TL_CLICKTEST` 與 `TL_SHOT` 可以一起下
	#   （CLAUDE.md「拍只有互動才到得了的狀態」），而捲到底的建造欄會被拍進去。
	scr._build_scroll.scroll_vertical = 0
	_press(last_button)
	# ★ 這一格要**沒有導管壓在格心**（B3.7）。原本寫死 (12,12)，而 B3.7 讓
	#   「點在導管上」變成檢視那條線——(12,12) 正好有一條線經過，於是這一條
	#   當場變紅，理由卻和合金無關（`_message` 是空的，不是「合金不夠」）。
	#   照這個檔案既有的紀律：**要一格就去找一格**，不要寫死一個會被別批動掉的座標。
	var alloy_cell := Vector2i(12, 12)
	for r in 12:
		var cand := Vector2i(12 - r, 12)
		if stage.in_map(cand) and s.node_at(cand).is_empty() and s.conduit_near(
			Vector2(cand), scr.WIRE_PICK
		) < 0 and String(BuildController.preview_place(s, last_type, cand)["reason"]) == Build.OK:
			alloy_cell = cand
			break
	_click(alloy_cell)
	await _frames(3)
	var alloy_gated: bool = (
		NodeDefs.alloy_cost(last_type) > 0
		and scr.build_type == last_type and scr._message.contains("合金")
	)
	print("[TL_CLICKTEST/select] 合金閘找到的空格 %s（要求：空地、蓋得下、格心上沒有導管）" % alloy_cell)

	# ★ B3.7.1：建造鈕是**開關**（使用者指定「按一下選擇，再按一下取消選擇」）。
	#   `ButtonGroup` 預設不准全部放開，所以這條真正驗的是 `allow_unpress`
	#   有沒有設、以及 `toggled(false)` 那一支有沒有接。
	#   ⚠ 光驗 `_build_type == ""` 不夠：**取消之後點空地不該蓋出東西**，
	#     而那是這件事唯一會咬到玩家的地方。用第一顆鈕（採集器）——最後一顆在
	#     捲動區底部，合成點擊會打到它上面蓋著的東西。
	_press(scr._build_buttons["extractor"])
	await _frames(3)
	var armed: bool = scr.build_type == "extractor"
	var nodes_before_idle: int = s.nodes.size()
	_click_button(scr._build_buttons["extractor"])
	await _frames(3)
	var disarmed: bool = armed and scr.build_type == ""
	_click(alloy_cell)
	await _frames(3)
	# 空手點空地要**安靜地什麼都不做**——不是丟一句 ✕。「我只是想收起面板」
	# 和「我蓋錯地方了」不是同一件事。
	var idle_click: bool = disarmed and s.nodes.size() == nodes_before_idle and scr._message == ""
	_press(scr._build_buttons["extractor"])
	await _frames(3)
	var rearmed: bool = scr.build_type == "extractor"

	# ★ 藍圖庫（B2.3）。走完整條路徑：框選 → 存 → 拿起來 → 放下去。
	#   **不直接呼叫 `Blueprint.capture()`**——那只驗得到純函式，而這一批
	#   會壞的地方在「拖曳有沒有真的被當成框選」和「拿著藍圖時左鍵做什麼」。
	GameState.data["blueprints"] = []
	_press(scr._mode_buttons[scr.Mode.BLUEPRINT])
	var built_cells: Array[Vector2i] = []
	for n: Dictionary in s.nodes:
		if String(n["type"]) != "core":
			built_cells.append(n["cell"])
	var lo := built_cells[0]
	var hi := built_cells[0]
	for c: Vector2i in built_cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	_drag(lo, hi)
	await _frames(2)
	var bp_saved: bool = (GameState.data["blueprints"] as Array).size() == 1
	# 存的是**真的框到的東西**，不是一張空藍圖。
	# ⚠ 前置條件要一起驗：只框到一個節點時「節點數對得上」是**恆真**的，
	#   而那樣既測不到導管、也測不到多格落點（截圖上只有一格預覽才發現）。
	var bp_has_nodes: bool = bp_saved and built_cells.size() >= 2 and (
		((GameState.data["blueprints"] as Array)[0]["nodes"] as Array).size() == built_cells.size()
	) and not ((GameState.data["blueprints"] as Array)[0]["conduits"] as Array).is_empty()
	# 找一個**真的放得下**的落點。寫死一格的話，日後動一次示範佈局或地圖
	# 就會變成「藍圖功能壞了」的假紅——玩家在真實遊玩裡做的也是這件事：
	# 移動滑鼠直到預覽變綠。
	var ore_keep: float = s.ore
	var alloy_keep: float = s.alloy
	s.ore = 99999.0
	s.alloy = 99999.0
	var spot := Vector2i(-1, -1)
	if bp_saved:
		var bp0: Dictionary = (GameState.data["blueprints"] as Array)[0]
		for y in range(1, s.map["size"].y - 4):
			for x in range(1, s.map["size"].x - 4):
				if bool(BuildController.blueprint_check(s, bp0, Vector2i(x, y))["ok"]):
					spot = Vector2i(x, y)
					break
			if spot.x >= 0:
				break
	# 拿起來 → 左鍵點那一格 → 節點數要真的變多。
	scr._on_take_blueprint(0)
	var bp_nodes_before: int = s.nodes.size()
	if spot.x >= 0:
		_click(spot)
	await _frames(2)
	var bp_expanded: bool = s.nodes.size() > bp_nodes_before and scr.bp_index < 0
	# ★ 錢不夠時要**說出缺口，而且一格都不放**（DoD 第二條）。
	#   位置沿用同一格 → 唯一的失敗理由只剩錢。
	scr._on_take_blueprint(0)
	s.ore = 0.0
	s.alloy = 0.0
	var nodes_broke: int = s.nodes.size()
	if spot.x >= 0:
		_click(spot)
	await _frames(2)
	var bp_short: bool = scr._message.contains("礦砂差") and s.nodes.size() == nodes_broke
	# ★ 把局面還原給後面的斷言用：**展開出來的節點要拆掉**、錢改回去、
	#   藍圖放下、模式回建造。
	#   少了這幾行，後面的視野／選單／局末三條會因為帳上是 0、或因為那幾格
	#   被藍圖佔住而一起紅——而紅的原因看起來完全和它們自己有關（實際踩到兩次）。
	#   `remove_node_at()` 會連帶清掉接在那一格上的導管，所以不會留下斷線。
	if spot.x >= 0 and bp_saved:
		for c: Vector2i in Blueprint.cells_at(
			(GameState.data["blueprints"] as Array)[0], spot
		):
			s.remove_node_at(c)
	s.ore = ore_keep
	s.alloy = alloy_keep
	scr.bp_index = -1
	GameState.data["blueprints"] = []
	_press(scr._build_buttons["extractor"])

	# 三個浮層也走同一條真實路徑：按鈕 → 面板出現且有內容。
	scr._energy_button.button_pressed = true
	scr._on_codex_show("smelter", scr._build_buttons["smelter"])
	scr._prio_panel.visible = true
	await get_tree().process_frame
	var energy_ok: bool = (
		scr._energy_panel.visible and (scr._energy_rows["net"] as Label).text != ""
		and scr._energy_rows.has("smelt")
	)
	# 圖鑑與能量是兩顆各自獨立的開關 → 玩家可以同時開。所以「不互相蓋掉」
	# 和優先權面板一樣是斷言，不是希望（B1.6.2 的截圖上抓到它們疊在一起）。
	var codex_ok: bool = (
		scr._codex_panel.visible and scr._codex_label.text.contains("熔爐")
		and scr._codex_panel.position.x + scr._codex_panel.size.x <= scr._energy_panel.position.x
	)
	# 藍圖抽屜也要守同一條：三張浮層可以同時開，就不得互相蓋掉。
	scr._bp_panel.visible = true
	scr._refresh_blueprints()
	await get_tree().process_frame
	var bp_fits: bool = (
		scr._bp_panel.position.x >= scr._prio_panel.position.x + scr._prio_panel.size.x
		and scr._bp_panel.position.x + scr._bp_panel.size.x <= scr._energy_panel.position.x
		and scr._bp_panel.position.y + scr._bp_panel.size.y <= 660.0
	)
	scr._bp_panel.visible = false
	# 優先權面板 9 列雙欄：整張表要留在畫面內，且不得蓋掉能量面板。
	var prio_ok: bool = (
		scr._prio_panel.size.y > 0.0
		and scr._prio_panel.position.y + scr._prio_panel.size.y <= scr.BAR_Y
		and scr._prio_panel.position.x + scr._prio_panel.size.x <= scr._energy_panel.position.x
	)

	# ★ 視野（B1.2.2）。四件事：進場就是 fit、fit 真的填滿框架、放大/全景走得通、
	#   平移夾得住。**縮放最容易壞的不是縮放本身，是命中判定跟著縮放走**——
	#   所以最後再用合成點擊蓋一個節點，確認放大後點到的還是同一格。
	var view_ok := await _view_selftest()

	# ★ 局內選單（B1.4.1）。會壞的地方有四個，每一個都只有真的送出事件才驗得到：
	#   ESC 到不到得了、遮罩擋不擋得住地圖、設定回不回得到選單、
	#   以及**左上角那顆鈕是不是同一件事**（P3：不能只有鍵盤那條路）。
	_press(scr._build_buttons["relay"])
	var free_cell := Vector2i(20, 12)
	_escape()
	await _frames(3)
	var menu_open: bool = scr._menu_layer != null and scr._menu_buttons.size() == 4
	var nodes_before: int = s.nodes.size()
	_click(free_cell)
	await _frames(3)
	var menu_blocks: bool = s.nodes.size() == nodes_before

	_press(scr._menu_buttons[2])          # 設定
	await _frames(3)
	var settings_open: bool = scr._settings_layer != null
	_escape()                          # 設定的 ESC ＝ 回選單，**不是**回戰場
	await _frames(3)
	var settings_back: bool = scr._settings_layer == null and scr._menu_layer != null
	_escape()
	await _frames(3)
	var menu_closed: bool = scr._menu_layer == null
	# 同一格在選單關掉之後蓋得起來 → 上面那個「蓋不起來」才證明得了是遮罩擋的，
	# 而不是那一格本來就不能蓋。
	_click(free_cell)
	await _frames(3)
	var buildable_after: bool = s.nodes.size() == nodes_before + 1
	_press(scr._menu_button)
	await _frames(3)
	var menu_by_button: bool = scr._menu_layer != null
	# 選單面板整個要留在畫面內。`CenterContainer` 幾乎不會出錯，但科技樹那張
	# 掉出畫面的卡片與設定畫面溢出的最後一行都是「`_draw()` 一個字都不會說」
	# 的同一類缺陷——量一次比相信便宜。
	var panel: Control = scr._menu_buttons[0].get_parent().get_parent() as Control
	var menu_fits: bool = (
		panel.global_position.y >= 0.0
		and panel.global_position.y + panel.size.y <= float(scr.size.y)
	)
	scr._close_menu()

	# ★ 音訊（B1.5）。四件事，全部只有真的跑起來才問得到：
	#   ① 準備期的 BGM **在播**，而且音量真的不是 0。
	#   ② ★ **一進入波次，音樂真的降到全靜**（B2.1f：戰鬥期沒有音樂）。
	#      第一版的自檢直接呼叫 `AudioBus` 的 API，結果下一幀就被 `_audio_tick()`
	#      從 `phase` 蓋回去——量到的是自己的呼叫，不是遊戲真正的那條路。改成推 `phase`。
	#   ③ ★ **開打時號令真的響了一次**（用 `plays` 的差值問，它是唯一的證據）。
	#   ④ 播一個音效之後真的有聲道在響（檔案讀得到、`play()` 有生效）。
	#      ⚠ 有鉤子時是**匯流排靜音**，不是不播，所以這些狀態問得到。
	var music_ok: bool = AudioBus.music_playing("base") and AudioBus.music_level() > 0.0
	var phase_before: String = s.phase
	var sting_plays: int = AudioBus.plays
	s.phase = "wave"
	# ⚠ **每一幀都要把 phase 釘回去。** 這個局面的 `spawn_queue` 是空的，
	#   所以 `_end_of_wave()` 下一個 tick 就把它打回 `prep`——音樂淡到一半又淡回來，
	#   `wave_hush` 恆為 false（實際踩到）。釘 phase 不是作弊：`_audio_tick()`
	#   本來就只從 `phase` 推導，走的仍是遊戲真正的那條路。
	#
	# ⚠ 而且要等**時間**，不是等幀數。淡出是 `LAYER_FADE`（1.2 秒）的實時，
	#   而這個視窗沒有垂直同步——120 幀可能只有 0.2 秒（實際踩到，`wave_hush`
	#   恆為 false）。「等 N 幀」在任何跟實時掛鉤的東西上都是壞的等待方式。
	var hush_t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - hush_t0 < 2000 and AudioBus.music_level() > 0.0:
		s.phase = "wave"
		await get_tree().process_frame
	var wave_hush: bool = AudioBus.music_level() <= 0.0
	var wave_sting: bool = AudioBus.plays > sting_plays
	s.phase = phase_before
	AudioBus.play("build_place")
	await get_tree().process_frame
	var voice_ok: bool = false
	for child: Node in AudioBus.get_children():
		var pl := child as AudioStreamPlayer
		if pl != null and pl.playing:
			voice_ok = true
	var audio_ok: bool = music_ok and wave_hush and wave_sting and voice_ok and AudioBus.muted

	# ★ **局結束之後不得有東西還在動**（使用者回報：「音效還在，他們也還在射擊」）。
	#   根因是 `step()` 在 won/lost 直接 return → 開火線的 `ttl` 不再遞減 →
	#   拿 `ttl` 當「剛剛才開火」的判定就每一幀都成立。這裡塞一條假的開火線，
	#   讓局結束，然後量兩件事：線有沒有被收掉、還會不會繼續發出聲音。
	# ⚠ 開火線的起點**必須是一座真的塔**，否則 `fire_<type>` 找不到檔案、
	#   `play()` 直接 return，這一段就變成一個永遠會過的空測試。
	_press(scr._build_buttons["anchor"])
	var tower_cell := Vector2i(22, 12)
	_click(tower_cell)
	await _frames(3)
	var tower_built: bool = String(s.node_at(tower_cell).get("type", "")) == "anchor"

	# ★ 潮鳴的場（B1.8）。要守的回歸是「**繪圖層真的去讀了光環**」——
	#   `Combat.auras()` 的數學已經有 `combat_test` 守著（滿電／半電／不疊加），
	#   這裡缺的那一環是 `_draw()` 有沒有把它算進 `_auras`。少了那一行，
	#   潮鳴就會安靜地退回 B1.7 之前「每秒吃 9 電、畫面上零回饋」的樣子，
	#   而 `_draw()` 對此一個字都不會說（B0.7.2 那個 size (0,0) 的同一類缺陷）。
	_press(scr._build_buttons["knell"])
	_click(Vector2i(20, 8))              # 離路徑 (20,4) 四格 → 在 5 格射程內
	await _frames(3)
	var knell: Dictionary = s.node_at(Vector2i(20, 8))
	s.add_enemy("drifter")
	(s.enemies[0] as Dictionary)["progress"] = 20.0   # 路徑上的 (20,4)
	await _frames(3)
	var field_ok: bool = (
		not knell.is_empty()
		and stage._auras.size() == s.enemies.size()         # 繪圖層每幀算了它
		and stage.engaged.get(int(knell["id"]), false)     # 而且潮鳴確實在交戰
	)
	s.enemies.clear()
	await _frames(2)

	s.phase = "won"
	await _frames(4)
	# ① 局末面板出現的那一刻，凍住的開火線與碎片要被收乾淨。
	var over_cleared: bool = s.shots.is_empty() and scr._over_panel != null
	# ② 面板已經在了（`_refresh_over` 之後不會再清一次），這時再塞一條滿 `ttl` 的
	#    開火線——**舊版會每一幀重播一次它的開火音**，新版因為 tick 沒有前進而不播。
	s.shots.append({
		"from": tower_cell, "to": Vector2i(22, 4), "ttl": BattleController.SHOT_TTL,
	})
	var plays_before: int = AudioBus.plays
	await _frames(12)
	var over_silent: bool = AudioBus.plays == plays_before
	s.shots.clear()
	s.phase = phase_before
	await _frames(3)

	# ③ ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」，所以
	#    **輸掉的那一面板上一定要有那一句**，而且整張面板要留在畫面內
	#    （多一行會換行的字，正是最容易把面板推出下緣的東西）。
	feedback._diag["wave_ticks"] = 600
	feedback._diag["starved"] = 300
	feedback._diag["leak_wave"] = 3
	s.phase = "lost"
	await _frames(4)
	var why_shown := false
	if scr._over_panel != null:
		for n: Node in scr._over_panel.find_children("*", "Label", true, false):
			if (n as Label).text.begins_with("為什麼輸"):
				why_shown = true
	var why_fits: bool = (
		scr._over_panel != null
		and scr._over_panel.position.y + scr._over_panel.size.y <= float(scr.size.y)
	)
	s.phase = phase_before
	await _frames(3)
	var over_ok: bool = (
		tower_built and over_cleared and over_silent and why_shown and why_fits
		and field_ok
	)

	# ★ 最後才留一個懸而未決的拖曳起點（按下不放開），讓八條方向導引與
	#   「連不成」的橙色預覽線入鏡——**這是玩家真的會看到的那一幀**（手指還沒鬆開）。
	#   一定要放在所有斷言之後：懸著的起點會讓下一次點擊被當成拖曳的終點。
	_press_at(stage.to_screen(stage.center(from)), true)
	scr.hover = from + Vector2i(4, 3)     # 橫 4 直 3：正好不是 45°
	scr._refresh_hint()

	var menu_ok: bool = (
		menu_open and menu_blocks and settings_open and settings_back and menu_closed
		and buildable_after and menu_by_button and menu_fits
	)

	# ★ **底欄與提示文字的矩形不得相交**（B2.9）。
	#
	#   §7.2 A-1 的結論一字未改地適用在這裡：「驗收條件要改成『鈕的矩形與底欄
	#   矩形不相交』，不是『按得到』」——被壓在字底下的鈕**照樣按得到**，
	#   所以既有的每一條斷言都是綠的，而畫面上「說明」那顆鈕和提示文字疊在一起。
	#
	#   這一格是 B2.9 給按鈕套美術 token 時當場撞到的：每顆鈕寬了 8px，
	#   七顆就把底欄推過那個寫死的 520。**寫死的座標記的是當時那七顆鈕有多寬。**
	var bar_rect := Rect2(Vector2.ZERO, Vector2.ZERO)
	for c: Node in scr.get_children():
		var box := c as HBoxContainer
		if box != null and is_equal_approx(box.position.y, scr.BAR_Y):
			bar_rect = Rect2(box.global_position, box.size)
	# ⚠ **要用提示文字真正的高度**。第一版寫成 1px 高，於是它的矩形（y 666–667）
	#   和底欄（y 668 起）永遠不相交——**斷言在它該紅的情境下是綠的**，
	#   而我是把提示推到底欄正中間去測它才發現。RG-158 的同一課：先確認尺會動。
	var hint_rect := Rect2(scr._hint.global_position, scr._hint.size)
	var bar_hint_clear: bool = bar_rect.size.x > 0.0 and not bar_rect.intersects(hint_rect)
	# 而且提示文字自己要留在視窗內（推到右邊之後才有可能掉出去）。
	var hint_inside: bool = scr._hint.global_position.x + scr._hint.size.x <= float(scr.size.x) + 0.5
	var ok: bool = (
		placed and rejected and diag_placed and wired and upgraded and dragged and panned
		and reachable and alloy_gated and energy_ok and codex_ok and prio_ok
		and view_ok and menu_ok and audio_ok and over_ok and bar_hint_clear and hint_inside
		and node_lvl and node_paid and node_cap
		and sel_open and sel_says and sel_inside and sel_toggles and sel_clear
		and wire_sel and wire_toggle and wire_fits and wire_up and wire_del
		and node_btn_up and node_btn_del and core_verbs
		and armed and disarmed and idle_click and rearmed and step_says and btn_still
		and bp_saved and bp_has_nodes and bp_expanded and bp_short and bp_fits
	)
	print("[TL_CLICKTEST] place=%s reject_path=%s diag_node=%s diag_conduit=%s diag_upgrade=%s drag_wire=%s mid_pan=%s last_btn=%s alloy_gate=%s energy=%s codex=%s prio=%s view=%s menu=%s audio=%s over=%s bar_hint=%s(底欄右緣 %.0f／提示 x %.0f) hint_in=%s node_lv=%s(付款 %s／上限 %s) 檢視=%s(說得出是誰 %s／在畫面內 %s／再點收起 %s／不疊能量面板 %s) → %s" % [
		placed, rejected, diag_placed, wired, upgraded, dragged, panned, reachable, alloy_gated,
		energy_ok, codex_ok, prio_ok, view_ok, menu_ok, audio_ok, over_ok,
		bar_hint_clear, bar_rect.end.x, scr._hint.global_position.x, hint_inside,
		node_lvl, node_paid, node_cap, sel_open, sel_says, sel_inside, sel_toggles, sel_clear,
		"PASS" if ok else "FAIL"
	])
	print("[TL_CLICKTEST/select] 導管選取=%s 再點收起=%s 版面=%s 面板加粗=%s(付款一併驗) 面板拆除=%s(退款一併驗) 建築升級鈕=%s 建築拆除鈕=%s 核心兩顆鈕都收起=%s｜建造鈕開關：選=%s 取消=%s 空手點空地無事發生=%s 選回來=%s｜升級鈕說得出這一級買什麼=%s｜升級後鈕不位移=%s" % [
		wire_sel, wire_toggle, wire_fits, wire_up, wire_del, node_btn_up, node_btn_del, core_verbs,
		armed, disarmed, idle_click, rearmed, step_says, btn_still,
	])
	print("[TL_CLICKTEST/audio] prep_music=%s wave_hush=%s wave_sting=%s voice=%s muted=%s tower=%s over_cleared=%s over_silent=%s why=%s why_fits=%s knell_field=%s" % [
		music_ok, wave_hush, wave_sting, voice_ok, AudioBus.muted, tower_built, over_cleared,
		over_silent, why_shown, why_fits, field_ok
	])
	print("[TL_CLICKTEST/blueprint] saved=%s nodes=%s(%d 格) expanded=%s shortfall=%s fits=%s" % [
		bp_saved, bp_has_nodes, built_cells.size(), bp_expanded, bp_short, bp_fits
	])
	print("[TL_CLICKTEST/menu] esc_open=%s scrim_blocks=%s settings=%s settings_back=%s esc_close=%s cell_buildable=%s button=%s fits=%s" % [
		menu_open, menu_blocks, settings_open, settings_back, menu_closed, buildable_after,
		menu_by_button, menu_fits
	])
	# ★ 重來（RG-177）。**放在最後，而且只在不拍照時跑**：它把整個 HUD 砍掉重建，
	#   之前持有的 widget 參照全部作廢，也會改掉要交給截圖鉤子的畫面。
	#   B3.13 的缺陷：`_restart()` 對 `get_children()` 全部 `queue_free()`，連地貌層一起砍掉，
	#   而換圖才會重建它——按「立刻重來」之後整張地圖的地貌消失。這條路徑在此之前零覆蓋。
	var restart_ok := true
	if Hooks.shot_path == "":
		var layer_before: Node2D = stage.terrain_layer
		scr._restart()
		await _frames(3)
		var layer_kept: bool = is_instance_valid(layer_before) and layer_before.get_parent() == stage
		var modules_kept: bool = true
		for m: Node in scr._modules():
			modules_kept = modules_kept and is_instance_valid(m) and m.get_parent() == scr
		var rebound: bool = stage.s == scr.s and overlay.s == scr.s and feedback.s == scr.s
		var hud_back: bool = scr._top != null and not scr._build_buttons.is_empty() and scr._hint != null
		restart_ok = layer_kept and modules_kept and rebound and hud_back
		print("[TL_CLICKTEST/restart] 地貌層還在=%s 四個模組還在=%s 新局已交給模組=%s HUD 重建=%s → %s" % [
			layer_kept, modules_kept, rebound, hud_back, "PASS" if restart_ok else "FAIL"
		])
	# 同時給 `TL_SHOT` 時不退出，把畫面交給截圖鉤子——**有些狀態只有互動才到得了**
	# （浮層要按鈕才會開、簡介要 hover 才會浮），沒有這條就永遠拍不到它們。
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok and restart_ok else 1)


## ★ 視野自檢（B1.2.2）。回傳全部通過與否，並**把畫面留在放大＋推到角落的
## 狀態**——那正是「遮罩有沒有真的切住框架」唯一拍得出來的畫面。
func _view_selftest() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	# ① 進場就是 fit，而且 fit 至少填滿一軸（另一軸留邊是長寬比不同，不是漏算）。
	var at_fit: bool = is_equal_approx(stage.zoom, stage.fit)
	var filled: bool = (
		is_equal_approx(px.x * stage.fit, stage.FRAME.size.x) or is_equal_approx(px.y * stage.fit, stage.FRAME.size.y)
	)
	var inside: bool = px.x * stage.fit <= stage.FRAME.size.x + 0.5 and px.y * stage.fit <= stage.FRAME.size.y + 0.5

	# ② 頂欄不能長到撞上縮放鈕（礦砂上萬之後那一排會變長）。
	var bar_clear: bool = scr._top.position.x + scr._top.size.x <= scr._zoom_button.get_parent().position.x

	# ③ 放大 → 倍率上升；「全景」→ 回到 fit 且平移歸零。
	scr._on_zoom(stage.ZOOM_STEP)
	var zoomed_in: bool = stage.zoom > stage.fit
	# ★ **以框架正中放大時，畫面中心不能跑掉**（B1.3.1）。舊版按一次「＋」就把
	#   地圖甩到左上角、pan 當場撞上夾限再也拖不動，而當時的斷言全是綠的——
	#   「倍率有變大」與「pan 夾得住」都成立，錯的是「往哪邊放大」。
	var centered: bool = stage.pan.is_equal_approx(Vector2.ZERO)
	# ★ 以滑鼠位置放大時，游標底下那一格必須還是同一格。
	scr._on_zoom_reset()
	var probe := Vector2(500.0, 300.0)
	var probe_cell := stage.cell_at(probe)
	stage.zoom_by(stage.ZOOM_STEP, probe)
	var anchored: bool = stage.cell_at(probe) == probe_cell
	scr._on_zoom_reset()
	scr._on_zoom(stage.ZOOM_STEP)
	stage.pan = Vector2(99999.0, 99999.0)
	stage._clamp_pan()
	var pan_clamped: bool = stage.pan.x <= (px.x * stage.zoom - stage.FRAME.size.x) * 0.5 + 0.5
	scr._on_zoom_reset()
	var reset_ok: bool = is_equal_approx(stage.zoom, stage.fit) and stage.pan == Vector2.ZERO
	# 下限就是 fit：再按「−」也不該縮得比框架小。
	scr._on_zoom(1.0 / stage.ZOOM_STEP)
	var floor_ok: bool = is_equal_approx(stage.zoom, stage.fit)

	# ④ ★ **放大之後命中判定還對得上**：這是縮放最容易靜靜壞掉的地方。
	#    放大兩級、把目標礦點平移到框架正中（玩家放大就是為了看某個東西），
	#    再點它——蓋出來的必須就是那一格，不是隔壁那一格。
	scr._on_zoom(stage.ZOOM_STEP * stage.ZOOM_STEP)
	_press(scr._build_buttons["extractor"])
	var target: Vector2i = (s.map["ore"] as Array)[1]
	var px_map := Vector2(s.map["size"]) * Shapes.GRID
	stage.pan = (px_map * 0.5 - stage.center(target)) * stage.zoom
	stage._clamp_pan()
	var before: int = s.nodes.size()
	_click(target)
	await _frames(3)
	var hit_ok: bool = s.nodes.size() == before + 1 and not s.node_at(target).is_empty()

	# ★ 滾輪只在地圖框架裡縮放（B2.4.7，使用者實玩回報：「選單滑到最上面，
	#   繼續滑會導致畫面放大」）。`ScrollContainer` 捲到邊界就不再吃掉滾輪事件。
	#   **兩條一起驗**：欄外不縮放 ＋ 欄內照樣縮放——只驗前者的話，把整段滾輪
	#   邏輯刪掉也會全綠。
	stage.reset_view()
	await get_tree().process_frame
	var z0 := stage.zoom
	_wheel(scr._build_scroll.global_position + Vector2(20.0, 20.0), true)
	await get_tree().process_frame
	var wheel_outside_ok: bool = is_equal_approx(stage.zoom, z0)
	_wheel(stage.FRAME.get_center(), true)
	await get_tree().process_frame
	var wheel_inside_ok: bool = stage.zoom > z0
	stage.reset_view()
	await get_tree().process_frame

	print("[TL_CLICKTEST/view] 滾輪：欄上不縮放=%s 圖上縮放=%s" % [
		wheel_outside_ok, wheel_inside_ok,
	])
	print("[TL_CLICKTEST/view] fit=%s fills=%s inside=%s bar_clear=%s zoom_in=%s centered=%s anchored=%s pan_clamp=%s reset=%s floor=%s hit_after_zoom=%s　（fit=%.3f，格 %.1f px）" % [
		at_fit, filled, inside, bar_clear, zoomed_in, centered, anchored, pan_clamped,
		reset_ok, floor_ok, hit_ok, stage.fit, Shapes.GRID * stage.fit
	])
	# ★ `bar_clear` 紅掉時要**知道差多少**才改得動 `TOP_CELLS` 的欄寬——
	#   「太寬了」這三個字修不了東西，「超出 63px」可以。
	var widths := PackedStringArray()
	for c: Node in scr._top.get_children():
		widths.append("%.0f" % (c as Control).size.x)
	print("[TL_CLICKTEST/view/bar] 頂欄 %.0f→%.0f（寬 %.0f＝%s），縮放鈕在 %.0f，餘裕 %.0f px" % [
		scr._top.position.x, scr._top.position.x + scr._top.size.x, scr._top.size.x, "+".join(widths),
		scr._zoom_button.get_parent().position.x,
		scr._zoom_button.get_parent().position.x - (scr._top.position.x + scr._top.size.x),
	])
	return (
		at_fit and filled and inside and bar_clear and zoomed_in and centered and anchored
		and pan_clamped and reset_ok and floor_ok and hit_ok
		and wheel_outside_ok and wheel_inside_ok
	)


func _press(b: Button) -> void:
	b.button_pressed = true
	b.pressed.emit()
	# ★ B3.7.1：建造鈕與藍圖鈕改接 `toggled`，而 `button_pressed = true` 在**它本來
	#   就按著**的時候一個訊號都不送。自檢裡有好幾處是「再確認一次拿的是這個」，
	#   那些呼叫會安靜地變成空操作。補送一次——處理函式對重複的 true 是冪等的。
	b.toggled.emit(true)


## ★ 用**合成滑鼠事件**按一顆鈕（B3.7），不是直接 emit。
##
## 檢視面板的容器是 `MOUSE_FILTER_IGNORE`（RG-39），而「IGNORE 的容器裡的鈕
## 收不收得到點擊」正是 B0.7.2 那一類缺陷的所在層——`_press()` 直接發訊號，
## 那一層它一條都測不到。面板上的鈕一律走這裡。
func _click_button(b: Button) -> void:
	_click_at(b.global_position + b.size * 0.5)


## 合成一次 ESC。走 `Input.parse_input_event()` 的完整輸入管線，才驗得到
## 「`ui_cancel` 這個 action 真的對得上 ESC 鍵」與「事件真的傳到 `_unhandled_key_input`」
## ——直接呼叫 `_toggle_menu()` 兩件都驗不到。
## 等 n 幀。自檢每送一次事件都要讓版面與 `_process` 跑完，而那件事本來寫成
## 兩行 ×65 次——同一個慣用語重複到那個數量，它就是一個函式。
func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _escape() -> void:
	UiKit.press_escape()


## GUI 的滑鼠路由要先有「游標在這裡」才認得出按下的是誰，所以**先送一個移動事件**。
## 走 `Input.parse_input_event()`（完整輸入管線）而不是 `Viewport.push_input()`：
## 後者繞過了一部分 GUI 狀態的建立，測不到真實玩家會走的那條路。
## ★ `_center()` 回的是**地圖座標**，合成滑鼠事件要的是**螢幕座標**——
## 中間差的就是縮放與平移那個變換（B1.2.2）。少了 `_to_screen()`，
## 這支自檢會點到旁邊那一格去，而畫面上一切看起來都正常。
func _click(cell: Vector2i) -> void:
	_click_at(stage.to_screen(stage.center(cell)))


## 合成一次拖曳：在 `a` 按下、移動到 `b`、在 `b` 放開。
func _drag(a: Vector2i, b: Vector2i) -> void:
	_drag_px(stage.to_screen(stage.center(a)), stage.to_screen(stage.center(b)), MOUSE_BUTTON_LEFT)


## 像素座標的拖曳。按下 → 移動（鍵壓著）→ 放開。
func _drag_px(a: Vector2, b: Vector2, button: int) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	_press_at(a, true, button)
	# 移動到終點時鍵是壓著的——`button_mask` 少了這一位，平移那條分支就進不去。
	var mm := InputEventMouseMotion.new()
	mm.position = b
	mm.global_position = b
	mm.relative = b - a
	mm.button_mask = mask
	Input.parse_input_event(mm)
	_press_at(b, false, button)


## 一顆按鍵事件（前面附一次移動，GUI 的滑鼠路由要先知道游標在哪）。
## `pressed=true` 而不送對應的放開，就是「手指還沒鬆開」那一幀。
func _press_at(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask if pressed else 0
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


## 合成一次滾輪。**位置是重點**：`ScrollContainer` 捲到邊界之後就不再吃掉
## 滾輪事件，於是它會落回 `_gui_input` ——而在建造欄上滾滾輪不該縮放地圖。
func _wheel(at: Vector2, up: bool) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


## 像素座標版。**加粗要點的是兩個節點「之間」**，那不是任何一格的中心。
func _click_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


## 合成一次滑鼠移動（不按鍵）。驗拖曳用——`_click_at()` 按下即放開，
## 用它驗不到「按住不放的時候會怎樣」。
func _move_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)


# ── 音訊（B1.5）────────────────────────────────────────────────────────


## ★ 渲染壓力量測（`TL_STRESS=1`，B1.7）。
##
## **模擬是凍結的**，所以這裡量到的是純粹的「畫 547 個節點 ＋ 2045 條導管 ＋
## 200 隻敵人要多久」。前 30 幀丟掉（著色器編譯與第一次配置都落在那裡），
## 之後取平均與最壞值——**最壞值才是玩家感覺得到的那一下卡頓**。
func stress_frame(delta: float) -> void:
	_stress_frames += 1
	if _stress_frames <= STRESS_WARMUP:
		return
	_stress_total += delta
	_stress_worst = maxf(_stress_worst, delta)
	var n := _stress_frames - STRESS_WARMUP
	if n < STRESS_FRAMES:
		return
	var avg := _stress_total / float(n)
	print("[TL_STRESS] 節點 %d／導管 %d／敵人 %d　→　平均 %.2f ms（%.0f FPS）／最壞 %.2f ms　量了 %d 幀" % [
		s.nodes.size(), s.conduits.size(), s.enemies.size(),
		avg * 1000.0, 1.0 / maxf(avg, 0.000001), _stress_worst * 1000.0, n
	])
	# 60 FPS ＝ 16.7ms；45 FPS（§5 的最低可接受）＝ 22.2ms。
	print("[TL_STRESS] 60FPS 目標 16.67ms／45FPS 底線 22.22ms → %s" % (
		"通過（60FPS）" if avg <= 0.01667
		else ("勉強（45FPS 以上）" if avg <= 0.02222 else "不通過")
	))
	get_tree().quit(0)


## ★ 大圖導引自檢（`TL_CLICKTEST=1 TL_PANEL=endless`，B2.1b）。
##
## 這一支驗的就是 B2.1b 的 DoD：**瓶頸節點即使不在畫面內也能在 30 秒內被找到**。
## 「30 秒」對自檢沒有意義，能驗的是它的前提——**問題在畫面外時，畫面上真的
## 有一個指得到它、而且點得到的東西**。
##
## 造問題的方式：在畫面外的礦點上蓋一座採集器、不接任何導管。它的產出推不
## 出去 → `stuck` → `滿溢`（和三態徽章同一份判定），一個節點就成立，不必
## 佈一整條產線。
func _guide_selftest() -> void:
	var big: bool = stage.oversized()

	# 找一個**開場看不到**的礦點——大圖的重點就是「畫面外」。
	var vw := stage.view_world_rect()
	var target := Vector2i(-1, -1)
	for c: Vector2i in (s.map["ore"] as Array):
		if not vw.has_point(stage.center(c)):
			target = c
			break
	var found_offscreen: bool = target.x >= 0

	if found_offscreen:
		# ★ **先把視野移過去才蓋得到**：那一格在畫面外，合成點擊落在框架外
		#   會被輸入層擋掉（第一版就是這樣紅的——而那個行為是對的，玩家也
		#   點不到看不見的格子）。蓋完再 `_reset_view()` 把它送回畫面外。
		stage.center_view_on(target, true)
		await _frames(2)
		_press(scr._build_buttons["extractor"])
		_click(target)
		await _frames(3)
		# 推幾個 tick，`node_state` 才算得出 `滿溢`。
		for _i in 6:
			BattleController.step(s)
		stage.reset_view()
		await _frames(2)
	var placed: bool = not s.node_at(target).is_empty()
	var back_offscreen: bool = placed and not stage.view_world_rect().has_point(stage.center(target))
	var flagged: bool = overlay._problem_cells().has(target)

	# 箭頭：它在畫面外，所以應該有一個指著它的箭頭。
	var arrows := overlay._arrow_hits()
	var arrow_at := Vector2(-1, -1)
	for hit: Array in arrows:
		if (hit[2] as Vector2i) == target:
			arrow_at = hit[0]
	var arrowed: bool = arrow_at.x >= 0
	# 箭頭要**在框架內**，不然它自己就在畫面外（第一版就是這樣：內縮沒算箭頭
	# 自己的半徑，尖端被邊緣切掉一半）。
	var arrow_inside: bool = arrowed and stage.FRAME.has_point(arrow_at)

	# 一鍵跳：點那個箭頭，目標要進到畫面內。
	var jumped := false
	if arrowed:
		_click_at(arrow_at)
		await _frames(2)
		# ★ 補間中途的 `_pan` 還沒到位——`_settle_view()` 把「動畫沒跑完」
		#   和「位置算錯」分開，否則這條斷言會變成在驗補間速度。
		stage._settle_view()
		jumped = stage.view_world_rect().has_point(stage.center(target))

	# ★ 推到底要真的貼到地圖的邊（RG-121）。使用者回報「小地圖滑到底不會貼邊」
	#   ——那是視野框與小地圖外框之間的內縮，肉眼在縮放過的截圖上判不準，
	#   所以這裡用數字驗：夾到底之後視野的世界矩形要對齊地圖的角。
	var msz := Vector2(s.map["size"]) * Shapes.GRID
	stage.pan_to(Vector2(99999.0, 99999.0), true)
	var tl := stage.view_world_rect().position
	stage.pan_to(Vector2(-99999.0, -99999.0), true)
	var br := stage.view_world_rect().end
	var flush: bool = (
		absf(tl.x) < 0.5 and absf(tl.y) < 0.5
		and absf(br.x - msz.x) < 0.5 and absf(br.y - msz.y) < 0.5
	)
	stage.reset_view()

	# 小地圖：點左上角，視野要往左上走（而且**不可以在那裡蓋出東西**）。
	#
	# ★ 先切成「中繼」再點：中繼哪裡都蓋得起來，所以 `mini_safe` 才是真斷言。
	#   用採集器的那一版是**假通過**——點到非礦點本來就會被擋，攔不攔截都一樣綠。
	_press(scr._build_buttons["relay"])
	var r := overlay.minimap_rect()
	var pan_before := stage.pan
	# ★ 哨兵字串，不是「節點數沒變」。節點數那一版**紅不起來**：那一格剛好
	#   不能蓋，攔不攔截都是綠的（第一版的假斷言）。`_act()` 在 BUILD 模式下
	#   **一定**會覆寫 `_message`（成功是空字串、失敗是原因），所以哨兵還在
	#   ＝ 這次點擊根本沒走到建造層。
	scr._message = "＿哨兵＿"
	# ★ 點「離目前視野最遠的那個角」，不是固定點左上角。固定左上是**看種子
	#   臉色**的斷言：前一步的箭頭跳轉若剛好把視野帶到左上，`_pan` 已經夾在
	#   (0,0)，再點左上當然不會動——測試紅掉而產品沒問題（`TL_SEED=42` 實際
	#   踩到）。確定性的閘門不可以有「某些種子才過」這種行為。
	var msize := Vector2(s.map["size"]) * Shapes.GRID
	var vcen := stage.view_world_rect().get_center() / msize
	_click_at(r.position + Vector2(
		6.0 if vcen.x > 0.5 else r.size.x - 6.0,
		6.0 if vcen.y > 0.5 else r.size.y - 6.0
	))
	await _frames(2)
	var mini_moved: bool = stage.pan_goal != pan_before
	var mini_safe: bool = scr._message == "＿哨兵＿"

	# ★ 按住拖曳（B2.1d，使用者指定）：**按住不放時視野要持續跟著游標**。
	#   ⚠ `_click_at()` 是按下**即放開**，所以要自己按住——第一版直接接在
	#   上一次點擊後面送移動事件，`drag=false`，因為那時早就放開了。
	var opp := r.position + Vector2(
		r.size.x - 6.0 if vcen.x > 0.5 else 6.0,
		r.size.y - 6.0 if vcen.y > 0.5 else 6.0
	)
	_press_at(r.position + r.size * 0.5, true)
	await _frames(2)
	var drag_from := stage.pan_goal
	_move_at(opp)
	await _frames(2)
	var dragged: bool = stage.pan_goal != drag_from
	# 放開之後再移動就**不可以**再跟著跑，否則等於滑鼠一直黏著小地圖。
	_press_at(opp, false)
	var after_release := stage.pan_goal
	_move_at(r.position + r.size * 0.5)
	await _frames(2)
	var drag_stops: bool = stage.pan_goal == after_release
	# 平滑：目標已經到了，但 `_pan` 還在路上（補間真的存在，不是瞬移）。
	var smooth: bool = not stage.pan.is_equal_approx(stage.pan_goal)
	stage._settle_view()

	# ★ 小地圖不常駐（B2.1d.1）：視野一動就在，靜止 `MINI_HOLD` 秒後退場，
	#   **退場後不得再攔截點擊**——常駐攔截等於右下角那一塊永遠蓋不了東西。
	var mini_on: bool = overlay.mini_ttl > 0.0
	overlay.mini_ttl = 0.0
	# 哨兵同前：`_act()` 在 BUILD 模式下一定會覆寫 `_message`，
	# 哨兵被蓋掉 ＝ 這一次點擊真的走到了建造層（＝小地圖沒有擋）。
	_press(scr._build_buttons["relay"])
	scr._message = "＿哨兵＿"
	_click_at(r.position + r.size * 0.5)
	await _frames(2)
	var mini_gone: bool = scr._message != "＿哨兵＿"
	# 再動一下視野，它要自己回來。
	stage.center_view_on(target)
	await _frames(2)
	var mini_back: bool = overlay.mini_ttl > 0.0
	stage._settle_view()

	# 可讀性地板：大圖的縮放下限是 24px／格，不是 fit（RG-59）。
	var floor_ok: bool = Shapes.GRID * stage.fit >= Shapes.MIN_READABLE_CELL - 0.001

	# ★ 視野框佔小地圖的比例 ＝ 看得到的比例。**這一條用肉眼判不準**
	#   （小地圖只有 232px 寬，視野框和外框差幾個像素），所以用數字。
	#   兩軸都必須 < 1（真的有看不到的部分）也都必須 > 0.3（不然是算錯了，
	#   而算錯的症狀正是「小地圖上那個框說謊」）。
	var frac := stage.view_world_rect().size / msize
	var frac_ok: bool = (
		frac.x > 0.3 and frac.x < 1.0 and frac.y > 0.3 and frac.y < 1.0
	)

	var ok: bool = (
		big and found_offscreen and placed and back_offscreen and flagged and arrowed
		and arrow_inside and jumped and mini_moved and mini_safe and floor_ok and frac_ok
		and flush and dragged and drag_stops and smooth
		and mini_on and mini_gone and mini_back
	)
	print(
		"[TL_CLICKTEST/endless] big=%s offscreen=%s placed=%s back_off=%s flagged=%s arrow=%s"
		% [big, found_offscreen, placed, back_offscreen, flagged, arrowed]
		+ " inside=%s jump=%s mini_pan=%s mini_safe=%s floor=%s（%.1f px/格）"
		% [arrow_inside, jumped, mini_moved, mini_safe, floor_ok, Shapes.GRID * stage.fit]
		+ " flush=%s drag=%s drag_stop=%s smooth=%s"
		% [flush, dragged, drag_stops, smooth]
		+ " mini_on=%s mini_gone=%s mini_back=%s view=%.0f%%×%.0f%% → %s"
		% [mini_on, mini_gone, mini_back, frac.x * 100.0, frac.y * 100.0, "PASS" if ok else "FAIL"]
	)
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## 自檢逾時就以失敗收場，不要把視窗留在使用者桌面上（見 `_click_selftest()`）。
## 60 秒遠寬於任何一支自檢的實際長度（最慢的約 3 秒）。
func _watchdog() -> void:
	var timer := get_tree().create_timer(60.0)
	timer.timeout.connect(func() -> void:
		push_error("[TL_CLICKTEST] 自檢逾時。多半是某一步丟了執行期錯誤而中止")
		get_tree().quit(1)
	)


# ── 截圖用的示範佈局（只在 TL_PANEL=battle 時建立）─────────────────────
#
# 指令表在 `data/Maps.gd`，與 `TL_SIM` 的 headless 跑局共用同一份——
# 截圖與數字看的必須是同一個局面。
func demo_layout() -> void:
	# ★ 戰役關卡用它自己的參考解（`data/Campaign.gd`），與 `campaign_test`
	#   跑的是同一份腳本——**截圖與那支測試印出來的數字保證是同一個局面**。
	#   `TL_DEMO_TICKS` 給得夠大就會跑到局末，星等面板才拍得到。
	if not scr.level.is_empty():
		var step := func(st: RefCounted) -> void: BattleController.step(st)
		for f: Dictionary in BuildController.apply_timeline(s, scr.level["demo"], step):
			push_warning("參考解第 %d 步失敗：%s" % [f["index"], f["reason"]])
		for _i in Hooks.demo_ticks:
			BattleController.step(s)
		return

	var sandbox: bool = Hooks.panel == "sandbox"
	# 沙盤的佈局全部是純礦砂造價（沒有加粗），所以那邊不發合金——
	# **合金要從畫面上那座熔爐煉出來，那正是那張圖要證明的事。**
	s.alloy = 0.0 if sandbox else MapsData.DEMO_ALLOY
	var failures := BuildController.apply_ops(
		s, MapsData.SANDBOX_DEMO if sandbox else MapsData.SHOAL_DEMO
	)
	for f: Dictionary in failures:
		push_warning("示範佈局第 %d 步失敗：%s" % [f["index"], f["reason"]])
	# 快轉到敵潮進入塔的射程。等真實時間跑 86 秒等於讓使用者的桌面開著一個
	# 視窗發呆一分半，模擬本來就不吃 delta，直接推 tick 就好。
	#
	# ★ **推的是 tick，不是階段**（B0.6 改）：讓準備期自己倒數完、波次自己開。
	# 舊寫法直接呼叫 `start_wave()` 把倒數跳過去，B0.5 還沒差別，B0.6 之後
	# 那等於一次滿額的提前召喚（倍率 1.5），截圖的掉落數字會和 `TL_SIM`
	# （自然開波）對不起來。現在 `TL_DEMO_TICKS=N` 與 `TL_SIM=N` 是同一個局面。
	for _i in Hooks.demo_ticks:
		BattleController.step(s)
