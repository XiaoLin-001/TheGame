extends Control
## 戰役關卡選擇（`10_GDD.md` §6.2 畫面流、§7.9）。
##
## 一關一張卡，橫排五張。每張卡上有四件事，缺一不可：
##   ① 星等（拿到的與沒拿到的都畫出來——沒拿到的那幾顆才是回來的理由）
##   ② **這一關新解鎖什麼**，因為那就是它要教的機制（§7.9 難度階梯）
##   ③ 一句話講它考什麼
##   ④ 鎖住時**說清楚要先過哪一關**，不是一個沒有下文的灰色方塊

const CampaignData := preload("res://data/Campaign.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const TechScreen := preload("res://scripts/screens/Tech.gd")
const Glyphs := preload("res://scripts/render/Glyphs.gd")

## 卡片寬度。五張 ＋ 四道間距要放進 1280 的設計基準。
const CARD := Vector2(228, 300)
## 關卡縮圖的寬（px）＝卡片內寬。高由地圖的長寬比決定（`Glyphs.MapView`）。
const THUMB_W := CARD.x - 24.0
## 一列擺幾張。四欄 ＝ 4×228 ＋ 3×12 ＝ 948px，在 1280 的視窗裡留得住左右邊距。
const COLUMNS := 4


## 回上一層（標題）。由呼叫端指派；沒指派就不畫返回鈕。
var on_exit: Callable = Callable()

## 卡片上那顆「出擊」鈕，供自檢按（與關卡序同索引）。
var _enter_buttons: Array[Button] = []
var _scroll: ScrollContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# ★ `and Hooks.panel == "campaign"`（B1.9）：本畫面也會被**標題畫面的自檢**
	#   掛起來。少了這一條，那支自檢一按「戰役」就會跑到這裡的 `get_tree().quit()`，
	#   把別人的自檢從中間打斷（`Settings` 早就踩過同一個坑）。
	if Hooks.click_test and Hooks.panel == "campaign" and Hooks.level <= 0:
		Hooks.run_selftest(self)


## ESC ＝ 返回上一層（B1.4.1）。已經進了關卡（`Battle` 掛在底下）時不處理——
## 那時 ESC 是局內選單的，`Battle` 自己會消費掉。
func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


## `queue_free()` 要到影格末才生效，中間那一幀舊畫面還在畫——
## 先 `remove_child()` 讓它當場離開樹，關卡選擇才不會疊在戰場上。
func _build() -> void:
	UiKit.clear(self)
	# 從局內回來時要換回選單曲（B1.5）。局內／選單是兩首，不是兩層。
	AudioBus.music("menu")

	var col := UiKit.vbox(14)
	col.position = Vector2(24, 40)
	add_child(col)
	col.add_child(UiKit.label("戰役", 32, Palette.ORDER_BRIGHT, false))
	col.add_child(UiKit.label(
		"前五關每關解鎖一種建造選項；之後每關多一種敵人。", 15,
		Palette.TEXT_SECONDARY, false
	))
	var data := int(float((GameState.data.get("tech", {}) as Dictionary).get("data", 0)))
	col.add_child(UiKit.label(
		"研究數據 %s" % UiKit.commas(data), 16, Palette.ENERGY_AMBER, false
	))
	var back_row := UiKit.hbox(8)
	col.add_child(back_row)
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "返回標題"
		back.pressed.connect(on_exit)
		back_row.add_child(UiKit.touchable(back))
	# ★ 研究數據是在這個畫面上賺到的，花掉它的地方就該在同一個畫面上到得了（B1.3）。
	var tech := Button.new()
	tech.text = "科技樹"
	tech.pressed.connect(_enter_tech)
	back_row.add_child(UiKit.touchable(tech))

	# ★ 卡片放進**捲動容器裡的格線**（B3.3）。
	#
	# ⚠ 第一版是一條 `hbox`，五關的時候剛好排得下——第二幕加到八關的當下，
	#   第 6 關被切一半、第 7／8 關整個在畫面外。**而十個 clicktest 全綠**：
	#   它們問的是「鈕點得到嗎」，而畫面外的鈕照樣點得到（`UiKit.click()` 是
	#   合成事件，不管可見性）。這是 RG-139／RG-149 的第三次現身，
	#   本案的結論一字未改：**按得到不等於看得到。**
	#
	# 四欄的格線而不是加寬視窗：§5 的 M3 目標是 25 關，一條橫列在那時要 5700px。
	# 格線 ＋ 捲動這個組合是既有的（科技樹、成就都是），不新發明一套。
	var scroll := UiKit.scroll()
	# 高度吃掉標頭以下的全部空間，**不寫死**：寫 `CARD.y + 24` 的話視窗裡會留
	# 180px 的空白，而第二列只露出一個邊——看起來像壞掉而不是像可以捲。
	# 下限一張卡：再小就變成「捲動一張卡」那種沒有人看得懂的東西。
	scroll.custom_minimum_size = Vector2(0, maxf(CARD.y + 24.0, float(size.y) - 250.0))
	col.add_child(scroll)
	_scroll = scroll

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	_enter_buttons.clear()
	for i in CampaignData.count():
		grid.add_child(_card(i))


## 這一關解鎖了嗎？規則在 `CampaignData.open_count()`——**名冊讀的是同一條**
## （B2.4）：「這張卡能不能點」與「這幾隻角色是不是我的」是同一個事實。
func _unlocked(index: int) -> bool:
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	return index < CampaignData.open_count(best)


func _stars(index: int) -> int:
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	return int(best.get(CampaignData.id_at(index), 0))


func _card(index: int) -> Control:
	var lv: Dictionary = CampaignData.at(index)
	var m: Dictionary = lv["map"]
	var open := _unlocked(index)
	var stars := _stars(index)

	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 卡片裡有按鈕，不能整張不吃滑鼠
	# 鎖住的卡整張變暗。**只暗標題會看起來像壞掉**，而不是像「還沒到」。
	# 內容仍然讀得到：它是路線圖，先看見後面有什麼才知道要往哪走。
	if not open:
		box.modulate = Palette.MOD_LOCKED
	var col := UiKit.vbox(6)
	box.add_child(col)

	col.add_child(UiKit.label(
		"第 %d 關　%s" % [index + 1, m["name"]], 20,
		Palette.TEXT_PRIMARY if open else Palette.TEXT_DISABLED, false
	))
	col.add_child(UiKit.label(
		"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 20,
		Palette.ENERGY_AMBER if stars > 0 else Palette.TEXT_DISABLED, false
	))
	# ★ 關卡縮圖（B3.11）：路徑、暈、橋、礦點、核心，和主畫面同一套編碼。
	#   「橋 2 座」那一行字說得出數量，說不出**在哪裡**——而擺位的決定全看在哪裡。
	#   縮圖也是每一關的臉：十關的卡片在這之前只差標題與數字。
	col.add_child(Glyphs.MapView.new(m, THUMB_W))

	var lesson := UiKit.label(String(lv["lesson"]), 13, Palette.TEXT_SECONDARY, false)
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson.custom_minimum_size = Vector2(CARD.x - 24, 0)
	col.add_child(lesson)

	col.add_child(UiKit.label(_new_row(index), 13, Palette.ORDER_CYAN, false))
	col.add_child(UiKit.label(
		"%d 波　橋 %d 座　準備期 %d 秒" % [
			(m["waves"] as Array).size(), (m["crossings"] as Array).size(),
			int(m["prep_time"])
		], 13, Palette.TEXT_SECONDARY, false
	))
	col.add_child(UiKit.label(
		"獎勵　每顆星 %d 研究數據" % int(lv["reward"]), 13, Palette.TEXT_SECONDARY, false
	))

	var b := Button.new()
	if open:
		b.text = "出擊"
		b.pressed.connect(_enter.bind(index))
	else:
		# 鎖住要說清楚條件。一個沒有下文的灰色方塊會讓玩家以為是壞掉了。
		b.text = "先通過第 %d 關" % index
		b.disabled = true
	_enter_buttons.append(b)
	col.add_child(UiKit.touchable(b))
	return box


## ★ 這一關比上一關新增了什麼——**兩根軸各回各的**（B3.3）。
##
## 第一幕的階梯是建造欄（§7.9），第二幕是敵人規則（第 5 關已經全解鎖）。
## 只問建造欄的話，第 6–8 關的卡片上會是一行「新解鎖　」後面空白
## ——一個有標題沒有內容的欄位，讀的人只會以為是壞掉了。
##
## 兩者都是**推導**的（比對相鄰兩關的資料表），不另外在關卡上加一個
## 「這一關教什麼」的欄位——那會是同一件事的第二份副本，而副本會漂。
func _new_row(index: int) -> String:
	var builds := _new_of(index, "unlocked", func(t: String) -> String: return NodeDefs.label(t))
	if not builds.is_empty():
		return "新解鎖　%s" % "・".join(builds)
	var foes := _new_enemies(index)
	if not foes.is_empty():
		return "新規則　%s" % "・".join(foes)
	return ""


func _new_of(index: int, key: String, label: Callable) -> Array[String]:
	var now: Array = (CampaignData.at(index) as Dictionary)[key]
	var prev: Array = [] if index <= 0 else (CampaignData.at(index - 1) as Dictionary)[key]
	var names: Array[String] = []
	for type: String in now:
		if not prev.has(type):
			names.append(String(label.call(type)))
	return names


## 這一關第一次出現的敵種（跟**前面每一關**比，不只跟上一關）。
func _new_enemies(index: int) -> Array[String]:
	var seen: Dictionary = {}
	for i in index:
		for type: String in _types_in(i):
			seen[type] = true
	var out: Array[String] = []
	for type: String in _types_in(index):
		if not seen.has(type):
			out.append(String(Enemies.of(type).get("name", type)))
			seen[type] = true
	return out


func _types_in(index: int) -> Array[String]:
	var out: Array[String] = []
	var m: Dictionary = (CampaignData.at(index) as Dictionary)["map"]
	for wave: Dictionary in m["waves"]:
		for g: Dictionary in wave["groups"]:
			out.append(String(g["type"]))
	return out


func _enter_tech() -> void:
	UiKit.clear(self)
	var screen := TechScreen.new()
	screen.on_exit = _build
	add_child(screen)


func _enter(index: int) -> void:
	UiKit.clear(self)
	var battle := BattleScreen.new()
	# ★ 指派要在 `add_child()` **之前**——`_ready()` 一進來就會讀 `level`。
	battle.level = CampaignData.at(index)
	battle.on_exit = _build
	add_child(battle)
