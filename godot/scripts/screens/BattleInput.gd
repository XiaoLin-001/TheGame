class_name BattleInput
extends RefCounted
## 滑鼠輸入：點擊、拖曳拉線、滾輪、框選。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Build := preload("res://scripts/sim/Build.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")

## ★ 「點在導管上」的命中半徑，單位是格（B3.7）。
##
## **刻意比 `conduit_near()` 的預設 0.5 窄。** 導管的中心線正好穿過它經過的每一格
## 的**格心**，所以 0.5 等於「整格都算在線上」——那會讓建造模式下再也蓋不出
## 「線從旁邊經過而不接它」的那種節點，而那是流量網路裡一個真的戰術選擇
## （`Build.can_connect()` 的原註寫著這條規則刻意不禁止穿過節點）。
##
## 0.3 讓線佔住格心那一條帶，格的四周仍然蓋得下去。代價是這條帶在 fit 倍率下
## 只有十幾個像素寬——低於 P3 的 44px 觸控門檻，所以手機移植時要靠放大操作。
## 已登記在 `40_PRODUCTION_PLAN.md` 的移植風險表。
const WIRE_PICK := 0.3

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ **必須是 `_gui_input`，不能是 `_unhandled_input`。**
##
## 本畫面是一個滿版的 `Control`，而 `Control.mouse_filter` 預設是 `STOP`：
## 它在 `_gui_input` 那一層就把滑鼠事件吃掉並標記為已處理，`_unhandled_input`
## **永遠不會被呼叫**。B0.3 到 B0.7.1 這條路徑一次都沒通過——
## 左欄的按鈕能按（它們是各自獨立的子 Control），但**地圖完全點不動**。
##
## 為什麼拖了五批才發現：所有自動化驗證走的都是 `TL_SIM`（不開視窗）與
## `TL_PANEL`＋示範佈局（用程式呼叫 `BuildController`，不經過輸入層），
## 而「絕不在沒有鉤子的情況下開視窗」這條紀律讓我也沒有手動點過。
## **整個輸入層在這之前是零覆蓋。** 對策：`TL_CLICKTEST=1`（見 `_click_selftest()`）。
func on_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# ★ 平移：**按住滑鼠中鍵拖**（B1.3.1，使用者指定）。
		#   ⚠ 手機移植預留條款 P3：觸控沒有中鍵，移植時要補一個雙指拖曳手勢
		#   （已登記在 `40_PRODUCTION_PLAN.md` 的風險表）。放大只由底欄的
		#   ＋／−／全景三顆鈕與滾輪進入，而 fit 倍率下平移恆被夾成 0，
		#   所以在桌面版之外「完全平移不了」不會發生。
		#
		#   判斷用**自己記的 `_panning`，不讀 `mm.button_mask`**：那個位元是
		#   Input 單例從實體滑鼠狀態填的，合成事件填進去的值不保證留得住——
		#   驗不到的輸入路徑就是遲早會壞掉的輸入路徑（B0.7.2 的教訓）。
		if battle.panning:
			battle.cam.pan_to(battle.cam.pan + mm.relative, true)
			battle.queue_redraw()
			return
		# ★ 小地圖按住拖曳（B2.1d，使用者指定）：按住不放，視野持續跟著游標走。
		#   走 `_pan_goal` → 畫面是**平滑**追過去的，不是一格一格跳。
		if battle.guide.mini_drag:
			battle.guide.mini_seek(mm.position)
			return
		# 浮點座標每次都更新（不只格變的時候）：命中導管靠的是它，
		# 而「壓在線上」與「在同一格但離線遠」是同一格裡的兩件事。
		battle.hover_p = battle.cam.point_at(mm.position)
		var c := battle.cam.cell_at(mm.position)
		if c != battle.hover:
			battle.hover = c
			battle.hints.refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		battle.panning = mb.pressed
		return
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and battle.guide.mini_drag:
			# 小地圖上放開：**不可以掉進 `_release()`**，否則等於在小地圖
			# 底下那一格結束一次拉線。
			battle.guide.mini_drag = false
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_release(mb.position)
		return
	# 滾輪縮放是桌面的便利，不是唯一的路：底欄有 ＋／−／全景 三顆鈕（P3）。
	#
	# ★ **只有游標在地圖框架裡才縮放**（B2.4.7，使用者實玩回報）。
	#   `ScrollContainer` 只在**捲得動的時候**吃掉滾輪事件；捲到頂還往上滾，
	#   事件就落回這裡——於是「建造欄滑到最上面再滑一下，地圖就放大了」。
	#   這條守衛同時擋掉底欄與頂欄上的滾輪，那本來也不該縮放地圖。
	#   ⚠ 不要改成「捲動容器把事件標記為已處理」——那要它在邊界也吞掉事件，
	#     而那會讓「滑到底之後想捲外層」這個標準行為壞掉。**限制範圍才是對的層級。**
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not BattleCamera.FRAME.has_point(mb.position):
			return
		battle.cam.zoom_by(BattleCamera.ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / BattleCamera.ZOOM_STEP,
			mb.position)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# ★ 導引要先問（B2.1b）。小地圖蓋在地圖上面，不先攔的話點它會**在它底下
	#   那一格蓋出東西來**——而且玩家看不出為什麼，因為節點生在畫面外。
	if battle.guide.guide_click(mb.position):
		return
	# ★ 從節點上按下先不動作，等放開才決定（B1.6.2）：放開在同一格＝一次普通點擊，
	#   放開在另一個節點上＝拉一條導管。這樣「蓋一個 → 接一條 → 蓋一個 → 接一條」
	#   不用每一步都往返左欄切模式——第 1 關的參考解就是 6 蓋 6 接交替，
	#   舊路徑要切 10 次模式，而那 10 次沒有任何一次是決策。
	var c := battle.cam.cell_at(mb.position)
	# ★ 藍圖框選（B2.3）：按下記起點，放開才成框。
	if battle.mode == BattleScreen.Mode.BLUEPRINT:
		battle.bp_from = c
		battle.queue_redraw()
		return
	if battle.mode == BattleScreen.Mode.BUILD and not battle.s.node_at(c).is_empty():
		battle.drag_from = c
		battle.queue_redraw()
		battle.hints.refresh_hint()
		return
	var p := battle.cam.point_at(mb.position)
	# ★ **點在導管上＝檢視那條線**（B3.7，使用者提出）。
	#
	#   放在建造模式裡而不是另開一個模式，理由和 B3.6 選節點同一條：玩家的意圖是
	#   「這條線我要看一下、要動它」，那不該先去底欄按一顆鈕再回來。
	#
	#   ⚠ 節點優先——上面那條已經 return 了，和 `demolish()` 的判斷順序一致。
	#   ⚠ 拿著藍圖時不攔：那時左鍵是「把它放在這裡」，一個明確得多的意圖。
	#   命中帶刻意窄（`WIRE_PICK`），格的其他地方照舊蓋得下去——理由見那個常數。
	if battle.mode == BattleScreen.Mode.BUILD and battle.bp_index < 0:
		var wi: int = battle.s.conduit_near(p, WIRE_PICK)
		if wi >= 0:
			battle.inspect.select_wire(int((battle.s.conduits[wi])["id"]))
			battle.hints.refresh_hint()
			battle.queue_redraw()
			return
	_act(c)
	battle.hints.refresh_hint()


## 左鍵放開。只有「按下時停在某個節點上」的那條路徑會走到這裡。
func _release(pos: Vector2) -> void:
	if battle.bp_from.x >= 0:
		var from_bp := battle.bp_from
		battle.bp_from = Vector2i(-1, -1)
		battle.bp.save_blueprint(from_bp, battle.cam.cell_at(pos))
		battle.hints.refresh_hint()
		battle.queue_redraw()
		return
	if battle.drag_from.x < 0:
		return
	var from := battle.drag_from
	battle.drag_from = Vector2i(-1, -1)
	var to := battle.cam.cell_at(pos)
	if to != from and not battle.s.node_at(to).is_empty():
		var code := BuildController.lay_conduit(battle.s, from, to)
		if code == Build.OK:
			AudioBus.play("build_wire")
		battle.message = text_of(code)
	else:
		# ★ **在既有節點上點一下＝檢視它**（B3.6，使用者提出）。
		#
		#   這個手勢原本只回一句「從這個節點按住往另一個節點拖」——一句教學，
		#   而玩家蓋到第三座塔之後就不需要它了，那之後這個手勢什麼都不做。
		#   換成選取之後，「點一下那座塔」給出射程、數據、當下耗能，
		#   以及**是誰在餵它電**。拖曳那句話改掛在提示列（`_refresh_hint()`）。
		#
		#   ⚠ 這一段**必須放在這裡，不是 `_act()` 的 BUILD 分支**：
		#   點在既有節點上會先進入「準備拉導管」的按下路徑，放開時走到這裡，
		#   根本到不了 `_act()`。第一版寫在那邊，於是面板永遠不開而斷言說
		#   「檢視=false」——輸入路徑的形狀只有真的送事件才看得出來。
		#
		#   不另開「檢視模式」：模式鈕在 B2.4.2 已經因為十三種節點擠過一次；
		#   也不綁右鍵——P3「操作不得只靠 hover／右鍵／鍵盤」。
		#
		#   ★ B3.7：再點一次同一座就取消選取（使用者提出）。選取是**開關**——
		#   沒有取消的路的話，面板一開就再也關不掉，而它蓋著地圖右半邊。
		battle.selected = Vector2i(-1, -1) if battle.selected == from else from
		battle.sel_wire = -1
		battle.inspect.refresh_inspect()
		battle.message = "" if battle.selected.x >= 0 else "從這個節點按住往另一個節點拖，就能拉一條導管。"
	battle.hints.refresh_hint()
	battle.queue_redraw()


## ★ B3.7.1 起這裡只剩建造一種語意。
##
## 加粗與拆除本來在這裡各佔一支分支，並且各自需要**格為單位的浮點座標**才點得準
## （好幾條線擠在同一個節點上時，格解析度分不出玩家指的是哪一條，B1.2.1）。
## 兩個動詞搬到檢視面板之後，那個參數與它的兩支分支一起消失——**面板已經知道
## 玩家選的是哪一個東西，不必再用座標猜一次。**
func _act(cell: Vector2i) -> void:
	# 音效只在**真的做成了**的時候響（`Build.OK` ＝ 空字串）。失敗有提示列說原因，
	# 再配一個音只是把「你做錯了」講兩次。
	match battle.mode:
		BattleScreen.Mode.BUILD:
			# ★ 拿著藍圖時，左鍵是「把它放在這裡」而不是蓋一個節點（B2.3）。
			if battle.bp_index >= 0:
				battle.bp.expand_blueprint(cell)
				return
			# 蓋在空地上就取消選取：選取講的是「這一座」，而畫面已經換人了。
			battle.selected = Vector2i(-1, -1)
			battle.sel_wire = -1
			battle.inspect.refresh_inspect()
			# ★ B3.7.1：手上什麼都沒拿（再按一次建造鈕就會這樣）＝點空地什麼都不做。
			#   不報錯——「我只是想收起面板」和「我蓋錯地方了」不是同一件事，
			#   對前者丟一句 ✕ 是把一個正常操作講成失敗。
			if battle.build_type == "":
				battle.message = ""
				return
			var code_b := BuildController.place(battle.s, battle.build_type, cell)
			if code_b == Build.OK:
				AudioBus.play("build_place")
			battle.message = text_of(code_b)


func text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)

