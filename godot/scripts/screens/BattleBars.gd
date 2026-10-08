class_name BattleBars
extends RefCounted
## 左欄建造清單、底欄、縮放鈕，以及整個 HUD 的組裝（build_ui）。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BattleController := preload("res://scripts/game/BattleController.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Score := preload("res://scripts/sim/Score.gd")

## ★ 底欄的 y（B2.4.2 常數化）。它原本是三處各寫一次的 `668`，而 A-1 那個缺陷
## 正好是「建造欄長到蓋住底欄」——兩個會互相碰撞的東西，座標必須是同一個常數。
const BAR_Y := 668.0

## 建造清單捲動區的高度。**清單再長也只會在這個區域裡捲**，模式鈕永遠釘在
## 它下面、永遠碰不到底欄。
##
## 52 ＝ 動作鈕那一塊實際佔的高度：`vbox 間隔 2 ＋ 間隔物 4 ＋ 間隔 2 ＋ 一列 44`。
## ★ B3.7.1 從 100 降到 52：升級與拆除拿掉之後只剩「藍圖」一顆，**空出來的 48px
## 直接還給節點清單**（十三種節點，捲得越少越好）。
## ⚠ 這種「差幾個像素」的東西不要用眼睛判——第一版的 96 實測差 2px（第二列的底邊
## 落在 670，底欄在 668），`TL_CLICKTEST` 的 `pinned_ok` 當場印出來。
const BUILD_LIST_H := BAR_Y - 56.0 - 52.0

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

var zoom_button: Button = null

var mode_buttons: Dictionary = {}

var build_buttons: Dictionary = {}

## 建造清單的捲動容器（B2.4.2）。模式鈕釘在它**下面**，所以清單再長也推不動它們。
var build_scroll: ScrollContainer = null

var ff_button: Button = null

var summon_button: Button = null

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func on_zoom(mult: float) -> void:
	battle.cam.zoom_by(mult, BattleCamera.FRAME.position + BattleCamera.FRAME.size * 0.5)


func on_zoom_reset() -> void:
	battle.cam.reset_view()
	refresh_zoom()
	battle.queue_redraw()


func refresh_zoom() -> void:
	if zoom_button == null:
		return
	# TL_NAKED 遮所有數值標籤；縮放倍率也是數值。
	if Hooks.naked:
		zoom_button.text = "全景"
		return
	zoom_button.text = "全景 %d%%" % roundi(battle.cam.zoom / maxf(0.0001, battle.cam.fit) * 100.0)


func build_ui() -> void:
	# ★ 頂欄三階 ＋ 固定寬度（B2.4.4）。舊版是七個 15px（**階外**）的 Label 直接
	#   丟進 HBox——11 個數字同一階，而且寬度隨數值變。規格見 `TOP_CELLS`。
	battle.topbar.top = UiKit.hbox(8)
	battle.topbar.top.position = Vector2(120, 12)
	battle.add_child(battle.topbar.top)
	battle.topbar.top_values.clear()
	battle.topbar.top_notes.clear()
	for spec: Dictionary in BattleTopbar.TOP_CELLS:
		var cell := UiKit.hbox(4)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(spec["tag"]) != "":
			cell.add_child(UiKit.label(String(spec["tag"]), 13, Palette.TEXT_SECONDARY, false))
		var v := UiKit.label("", int(spec["vs"]), Palette.TEXT_PRIMARY, false)
		v.custom_minimum_size.x = float(spec["vw"])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		battle.topbar.top_values.append(v)
		var n := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		n.custom_minimum_size.x = float(spec["nw"])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(n)
		battle.topbar.top_notes.append(n)
		battle.topbar.top.add_child(cell)

	# ★ 選單（B1.4.1）。ESC 是快捷，**不是唯一的路**（P3：操作不得只靠鍵盤）。
	#   放左上角 x<120、y<56 那塊角落——頂欄從 x=120 起、建造欄從 y=56 起，
	#   全畫面只剩這裡是空的，而它也正好是選單的慣例位置。
	var menu_bar := UiKit.hbox(0)
	menu_bar.position = Vector2(8, 6)
	battle.add_child(menu_bar)
	battle.menu.menu_button = Button.new()
	battle.menu.menu_button.text = "選單"
	battle.menu.menu_button.custom_minimum_size.x = 104
	battle.menu.menu_button.pressed.connect(battle.menu.toggle_menu)
	menu_bar.add_child(UiKit.touchable(battle.menu.menu_button))

	# ★ 縮放（B1.2.2）。放在頂欄右端那片空白——建造欄與底欄都已經滿了，
	#   而地圖右上角是縮放控制的慣例位置。**三顆鈕都是可點的**：滾輪只是
	#   桌面的便利，手機移植預留條款 P3 不許任何操作只有滾輪／右鍵一條路。
	var zoom_bar := UiKit.hbox(6)
	zoom_bar.position = Vector2(1072, 6)
	battle.add_child(zoom_bar)
	for pair: Array in [["−", 1.0 / BattleCamera.ZOOM_STEP], ["＋", BattleCamera.ZOOM_STEP]]:
		var zb := Button.new()
		zb.text = String(pair[0])
		zb.pressed.connect(on_zoom.bind(float(pair[1])))
		zoom_bar.add_child(UiKit.touchable(zb))
	zoom_button = Button.new()
	# 倍率印在「全景」鈕上，不另給一個標籤——底欄與建造欄都沒有空位了，
	# 而「現在幾倍」與「回到全景」本來就是同一件事的兩面。
	zoom_button.pressed.connect(on_zoom_reset)
	zoom_bar.add_child(UiKit.touchable(zoom_button))
	refresh_zoom()

	# 間距 2 而不是 4：B1.1 起建造欄有 10 種節點＋3 個模式鈕，44px 的觸控高度
	# （手機移植前提，不能縮）乘 13 已經吃掉 572px，只剩間距可以讓。
	#
	# ★ B2.4.2：那句話在 B2.4 加了三隻角色之後**就不夠了**——13 種把「加粗／拆除」
	#   推到和底欄疊在一起，「藍圖」整顆掉出畫面（RG-139），而**全收集的玩家打無盡
	#   就是 13 種**。所以建造清單改裝進捲動容器，模式鈕釘在它下面。
	#
	#   為什麼是捲動而不是「壓矮一點」或「排兩欄」：44px 是手機移植的硬底線
	#   （P2，不能縮），兩欄在 112px 欄寬裡塞不下「回收者」三個字。而真正的理由是
	#   **這條清單還要再長一倍**——`10_GDD.md` §5 的 M3 內容矩陣是 24 隻角色，
	#   加 5 種生產節點就是 29 顆鈕。任何「剛好排得下」的方案都只是把同一個 bug
	#   往後推一批。
	var col := UiKit.vbox(2)
	col.position = Vector2(8, 56)
	# 112 ＝ 剛好貼到地圖原點 x=120（`ORIGIN`）而不蓋住它。
	# 最長的一顆是「碎浪 140+60合」。
	col.custom_minimum_size = Vector2(112, 0)
	battle.add_child(col)

	# ★ 全部 11 個鈕共用一個 `ButtonGroup`：任一時刻**恰好一個**是按下狀態，
	#   而那正好就是這個 UI 的真相（選了建造類型就是離開連線模式）。
	#   用 Godot 內建的 toggle 群組，不自己維護一套「哪個被選中」的高亮。
	#   B0.6 之前完全沒有選中指示——玩家只能從提示列的文字推自己在哪個模式。
	var group := ButtonGroup.new()
	# ★ B3.7.1：允許「按一下選、再按一下取消」（使用者指定）。`ButtonGroup` 預設
	#   永遠有一顆是按下的——那對模式是對的（總得在某個模式裡），對「手上拿著誰」
	#   不對：玩家常常只是想看一下地圖，而不是隨時都握著一種節點。
	group.allow_unpress = true
	# ★ 只列**這一關解鎖的**（`10_GDD.md` §7.9）。第 1 關給四顆鈕不是十顆——
	#   十顆對一個還不知道「電是流率」的人來說不是自由，是雜訊。
	#   一局之內這份清單不會變，所以鈕的位置仍然是固定的（R-15 的同一條理由）。
	build_scroll = ScrollContainer.new()
	build_scroll.custom_minimum_size = Vector2(112, BUILD_LIST_H)
	build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(build_scroll)
	var list := UiKit.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_scroll.add_child(list)

	# ★ 生產／防線分段（B2.4.2）。**兩段不是排版，是這一欄的整句話**——
	#   優先權面板為了同一件事特地做了雙欄（`NodeDefs.PRIORITY_SPLIT`），
	#   而建造欄是玩家做**同一個決定**的地方（這 40 礦砂餵產線還是餵防線）。
	#   分段同時讓捲動清單找得到東西：29 顆一模一樣的鈕捲起來是找不到路的。
	# ★ **自己排序，不假設 `_buildable()` 已經是生產在前**（B2.4.2 code review 抓到）。
	#   那份清單是各關在 `data/Campaign.gd` 手寫的，目前碰巧都是生產在前——
	#   而「碰巧」不是不變量。有一關把塔寫在採集器前面時，那顆採集器會安靜地
	#   歸到「防線」那一段，畫面看起來完全正常。
	var ordered: Array[String] = []
	for pass_towers: bool in [false, true]:
		for type: String in battle.buildable():
			if bool(NodeDefs.of(type).get("tower", false)) == pass_towers:
				ordered.append(type)
	var seen_tower := false
	for type: String in ordered:
		var is_tower: bool = bool(NodeDefs.of(type).get("tower", false))
		if not seen_tower and is_tower:
			seen_tower = true
			list.add_child(_section_label("防線"))
		elif not seen_tower and list.get_child_count() == 0:
			list.add_child(_section_label("生產"))
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := _tool_button(group, NodeDefs.label(type))
		# ★ B3.7.1：接 `toggled` 不是 `pressed`（使用者指定「再按一下就是取消選擇」）。
		#   `pressed` 收不到「這一顆剛被放開」——那正是取消選擇要聽的事件。
		b.toggled.connect(_on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(battle.codex.on_codex_show.bind(type, b))
		b.mouse_exited.connect(battle.codex.on_codex_hide)
		build_buttons[type] = b
		list.add_child(UiKit.touchable(b))
	# ★ B3.7.1：`_build_type` 可以是空字串（手上什麼都沒拿），而空字串沒有對應的鈕。
	#   索引不到會丟執行期錯誤 → **中止整支 `_build_ui()`**，症狀是「半個畫面沒建出來」
	#   而不是報錯（RG-164 的形狀）。
	if build_buttons.has(battle.build_type):
		(build_buttons[battle.build_type] as Button).button_pressed = true

	col.add_child(spacer(4))
	# ★ 動作鈕只剩一顆（B3.7.1，使用者指定）。歷次拿掉的理由是同一條：
	#   **一個模式鈕如果只是「同一件事的比較慢的做法」，它就該消失。**
	#   「連線」B1.6.2 被拖曳取代；「移動」B1.3.1 改中鍵拖；
	#   「升級」「拆除」B3.7 被檢視面板上的鈕取代——切模式 → 點目標 → 切回建造，
	#   三步裡有兩步不是決定。
	#   藍圖留著：它不是動詞，是**手上拿著的東西**，沒有別的地方表達得了。
	var bp_btn_mode := _tool_button(group, "藍圖")
	bp_btn_mode.toggled.connect(_on_mode.bind(BattleScreen.Mode.BLUEPRINT))
	mode_buttons[BattleScreen.Mode.BLUEPRINT] = bp_btn_mode
	col.add_child(UiKit.touchable(bp_btn_mode))

	# 建造欄放不下八種節點再加動作鈕（8×44 已經吃掉 380px），
	# 所以時間流與面板開關搬到地圖下緣那條 56px 的空帶——那裡本來就空著。
	# ★ 三群（B2.4.4，§7.2 B-5）：**時間流｜浮層開關｜說明**。
	#   群間 24、群內 8（§1.3 間距階），**不加分隔線**——七顆同權重的鈕裡有一顆
	#   是不可逆的，而視覺重量要對應後果的重量。
	var bar := UiKit.hbox(24)
	bar.position = Vector2(8, BAR_Y)
	battle.add_child(bar)
	var g_time := UiKit.hbox(8)
	var g_panels := UiKit.hbox(8)
	var g_help := UiKit.hbox(8)
	bar.add_child(g_time)
	bar.add_child(g_panels)
	bar.add_child(g_help)
	ff_button = Button.new()
	ff_button.text = "快進 4×"
	ff_button.pressed.connect(_on_fast_forward)
	g_time.add_child(UiKit.touchable(ff_button))
	summon_button = Button.new()
	summon_button.pressed.connect(_on_summon_now)
	# ★ **全底欄唯一一顆不可逆的鈕**：按下去這一波就提早來，獎勵倍率也定了。
	#   §7.2 B-5 原本開的處方是 `energy.amber` 描邊——**那違反 §1.1 配色紀律 2**
	#   （琥珀專屬於能量，而提前召喚跟耗能無關）。改用 `warn.orange`：紀律 1 說
	#   橙／品紅專屬於「敵人與危險狀態」，而這顆鈕做的事**就是把敵潮叫過來**，
	#   它是玩家自己選的危險。同一條紀律，剛好也是更強的編碼。
	summon_button.add_theme_color_override("font_color", Palette.WARN_ORANGE)
	summon_button.add_theme_color_override("font_hover_color", Palette.WARN_ORANGE)
	g_time.add_child(UiKit.touchable(summon_button))
	# 抽屜開關本來就是一個開關：做成 toggle，按下狀態才**真的**等於「抽屜開著」。
	# 之前是普通按鈕，它拿到焦點時的外框看起來就像被選中，玩家會以為抽屜開了。
	var prio := Button.new()
	prio.text = "優先權"  # 底欄六個鈕，字都壓到最短——提示列要留得下兩行字

	prio.toggle_mode = true
	prio.toggled.connect(battle.prio.on_toggle_priority)
	g_panels.add_child(UiKit.touchable(prio))
	# ★ 藍圖庫（B2.3）。放底欄抽屜而不是左欄：左欄的八種節點加動作鈕已經
	#   吃掉 380px，而藍圖是**每局用一兩次**的東西，不該和每秒都在點的建造欄搶位置。
	var bp_btn := Button.new()
	bp_btn.text = "藍圖"
	bp_btn.toggle_mode = true
	bp_btn.toggled.connect(battle.bp.on_toggle_blueprint)
	g_panels.add_child(UiKit.touchable(bp_btn))
	battle.help.help_button = Button.new()
	battle.help.help_button.text = "說明"
	battle.help.help_button.toggle_mode = true
	battle.help.help_button.toggled.connect(battle.help.on_toggle_help)

	battle.energy.energy_button = Button.new()
	battle.energy.energy_button.text = "能量"
	battle.energy.energy_button.toggle_mode = true
	battle.energy.energy_button.toggled.connect(battle.energy.on_toggle_energy)
	g_panels.add_child(UiKit.touchable(battle.energy.energy_button))
	battle.codex.codex_button = Button.new()
	battle.codex.codex_button.text = "圖鑑"
	battle.codex.codex_button.toggle_mode = true
	battle.codex.codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	battle.codex.codex_button.toggled.connect(func(on: bool) -> void: battle.codex.codex_on = on)
	g_panels.add_child(UiKit.touchable(battle.codex.codex_button))
	# 說明自己一群：它是唯一一顆**跟局面無關**的鈕（不改狀態、不開資料浮層）。
	g_help.add_child(UiKit.touchable(battle.help.help_button))

	battle.prio.build_priority_panel()
	battle.bp.build_blueprint_panel()
	battle.energy.build_energy_panel()
	battle.codex.build_codex_panel()
	battle.inspect.build_inspect_panel()
	battle.help.build_help_panel()

	# 兩行：上行「下一步」、下行當下動作的細節。
	#
	# ★ x **跟著底欄實際的右緣走**，不是一個寫死的 520（B2.9）。原本是寫死的，
	#   而 B2.9 給按鈕套上美術 token（`content_margin` 12/8）之後每一顆鈕都變寬了
	#   ——七顆鈕加起來超過 520，提示文字當場被壓在「說明」那顆鈕上面。
	#   寫死的座標就是這樣壞的：它記的是**當時**那七顆鈕有多寬。
	#   （這也是手機預留條款 P1「不硬編碼像素位置」在這一行的兌現。）
	battle.hints.label = UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
	battle.hints.label.position = Vector2(520, 666)
	battle.hints.label.size = Vector2(755, 50)
	battle.add_child(battle.hints.label)
	bar.resized.connect(_place_hint.bind(bar))
	_place_hint.call_deferred(bar)
	battle.hints.refresh_hint()


## 提示文字擺在底欄右邊 24px（§1.3 間距階的群間距，同底欄自己的三群）。
## 底欄是容器，它的寬度要到版面跑完才知道——所以走 `resized` 而不是算一次。
func _place_hint(bar: Control) -> void:
	if battle.hints.label == null or not is_instance_valid(bar):
		return
	battle.hints.label.position.x = bar.position.x + bar.size.x + 24.0
	battle.hints.label.size.x = maxf(120.0, float(battle.size.x) - battle.hints.label.position.x - 8.0)


## 左欄的工具鈕。`toggle_mode` ＋ 共用群組 ＝ 內建的「選中」外觀，
## 不必自己塗顏色（`20_ART_DIRECTION.md`：能用主題就別硬編碼色值）。
func _tool_button(group: ButtonGroup, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	return b


func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 建造欄的段標題（B2.4.2）。`text.xs` ＋ `text.secondary`——它是分界不是內容，
## 不該和鈕搶注意力。**不畫線**：兩段之間本來就有 2px 間距 ＋ 一個矮標題，
## 再加一條線就是同一個分界講兩次（§4.3b「同一個位置上的兩個訊息」的同一條）。
func _section_label(text: String) -> Control:
	var l := UiKit.label(text, 11, Palette.TEXT_SECONDARY, false)
	l.custom_minimum_size = Vector2(0, 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## ★ B3.7.1：建造鈕改成**開關**（使用者指定「按一下選擇，再按一下取消選擇」）。
##
## 手上什麼都沒拿的時候，左鍵就純粹是檢視——點節點看節點、點導管看導管、
## 點空地什麼都不做。那也是**在有導管經過的格子上蓋東西**之外，另一個
## 「我只是想看一下」的正常需求。
##
## ⚠ 放開那一支要**確認自己還是當前那一個才清空**。同一個 `ButtonGroup` 換鈕時
##   會先後送出「舊的 false」與「新的 true」兩個事件，而兩者的順序不是這裡能
##   假設的——沒有這個守衛，換鈕有一半的機率把剛選好的那一個清掉。
func _on_build_type(pressed: bool, type: String) -> void:
	if not pressed:
		if battle.build_type == type:
			battle.build_type = ""
			battle.message = ""
			battle.hints.refresh_hint()
		return
	battle.mode = BattleScreen.Mode.BUILD
	battle.build_type = type
	battle.drag_from = Vector2i(-1, -1)
	battle.message = ""
	battle.hints.refresh_hint()


## 藍圖鈕。同建造鈕，`toggled` ＋ 再按一次回到建造（B3.7.1）。
func _on_mode(pressed: bool, which: int) -> void:
	if not pressed:
		if battle.mode == which:
			battle.mode = BattleScreen.Mode.BUILD
			battle.message = ""
			battle.hints.refresh_hint()
		return
	battle.mode = which
	# 換模式就放下手上的藍圖：拿著它的時候左鍵是「展開」，而玩家切走
	# 是為了做別的事——留著會讓下一次左鍵做出他沒想要的事。
	if battle.bp_index >= 0:
		battle.bp_index = -1
		battle.bp.refresh_blueprints()
	battle.drag_from = Vector2i(-1, -1)
	battle.message = ""
	battle.hints.refresh_hint()


## 快進只在準備期能按（`10_GDD.md` B5：可跳過等待，戰鬥期不可加速也不可減速）。
func _on_fast_forward() -> void:
	if battle.s.phase != "prep":
		return
	battle.s.speed_mult = 1 if battle.s.speed_mult > 1 else FAST_FORWARD_RATE
	battle.topbar.refresh_top()


## ★ 提前召喚：**按鈕常駐顯示當前獎勵倍率**（`10_GDD.md` §6.2 硬性要求 3）——
## 下注的誘惑要一直在眼前，而不是按下去才知道賭到多少。
## 倍率隨倒數每 tick 縮水，所以這個字串每幀重算。
func refresh_summon() -> void:
	if summon_button == null:
		return
	var can: bool = battle.s.phase == "prep"
	summon_button.disabled = not can
	if Hooks.naked or not can:
		summon_button.text = "提前召喚"
		return
	var bonus := Score.summon_bonus(maxf(0.0, battle.s.prep_time() - battle.s.phase_time), battle.s.prep_time())
	summon_button.text = "提前召喚 +%d%%" % roundi((bonus - 1.0) * 100.0)


func _on_summon_now() -> void:
	BattleController.start_wave(battle.s)
	battle.topbar.refresh_top()
