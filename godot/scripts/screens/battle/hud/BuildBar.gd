extends Node
## 建造欄（左欄）：這一關可蓋的節點清單，以及「藍圖」那顆手上拿著的東西。
##
## 清單裝在捲動容器裡、模式鈕釘在它下面——十三種節點（M3 會到 29 種）再長也只在區域內捲，
## 永遠碰不到底欄（B2.4.2）。「這一局蓋得出哪些」由 `buildable()` 回答。

const NodeDefs := preload("res://data/NodeDefs.gd")
const BlueprintPanel := preload("res://scripts/screens/battle/hud/BlueprintPanel.gd")
const CodexPanel := preload("res://scripts/screens/battle/hud/CodexPanel.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組。
var bppanel: BlueprintPanel = null
## 同伴模組（角色簡介：滑鼠停在鈕上就浮出來）。
var codexpanel: CodexPanel = null
## 同伴模組（互相引用，不能用型別標註）。
var hintbar: Node = null


var mode_buttons: Dictionary = {}

var build_buttons: Dictionary = {}

## 建造清單的捲動容器（B2.4.2）。模式鈕釘在它**下面**，所以清單再長也推不動它們。
var build_scroll: ScrollContainer = null


## 這一局蓋得出哪些節點。**空的 `unlocked` ＝ 全部**（測試圖與沙盤）。
##
## ★ B2.4 之後「全部」包含招募專屬的三隻，而測試圖與沙盤**刻意不吃名冊**：
## 那兩張圖是開發用的（主選單上寫著「測試圖」），要驗的是節點本身而不是進度。
## 真正的入口各自明講自己要什麼——戰役問關卡（§7.9）、無盡與自由榜問名冊、
## 統一榜走 `Daily.UNIFORM_BUILD`。**沒有一條路是靠這個預設值決定的。**
func buildable() -> Array:
	var unlocked: Array = s.sets.get("unlocked", [])
	return NodeDefs.BUILDABLE if unlocked.is_empty() else unlocked


## 左欄的工具鈕。`toggle_mode` ＋ 共用群組 ＝ 內建的「選中」外觀，
## 不必自己塗顏色（`20_ART_DIRECTION.md`：能用主題就別硬編碼色值）。
func tool_button(group: ButtonGroup, text: String) -> Button:
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
func section_label(text: String) -> Control:
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
## 左欄：建造清單（捲動）＋ 釘在它下面的「藍圖」鈕。
func build() -> void:
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
	scr.add_child(col)

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
	build_scroll.custom_minimum_size = Vector2(112, scr.BUILD_LIST_H)
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
		for type: String in buildable():
			if bool(NodeDefs.of(type).get("tower", false)) == pass_towers:
				ordered.append(type)
	var seen_tower := false
	for type: String in ordered:
		var is_tower: bool = bool(NodeDefs.of(type).get("tower", false))
		if not seen_tower and is_tower:
			seen_tower = true
			list.add_child(section_label("防線"))
		elif not seen_tower and list.get_child_count() == 0:
			list.add_child(section_label("生產"))
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := tool_button(group, NodeDefs.label(type))
		# ★ B3.7.1：接 `toggled` 不是 `pressed`（使用者指定「再按一下就是取消選擇」）。
		#   `pressed` 收不到「這一顆剛被放開」——那正是取消選擇要聽的事件。
		b.toggled.connect(on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(codexpanel.on_codex_show.bind(type, b))
		b.mouse_exited.connect(codexpanel.on_codex_hide)
		build_buttons[type] = b
		list.add_child(UiKit.touchable(b))
	# ★ B3.7.1：`_build_type` 可以是空字串（手上什麼都沒拿），而空字串沒有對應的鈕。
	#   索引不到會丟執行期錯誤 → **中止整支 `_build_ui()`**，症狀是「半個畫面沒建出來」
	#   而不是報錯（RG-164 的形狀）。
	if build_buttons.has(scr.build_type):
		(build_buttons[scr.build_type] as Button).button_pressed = true

	col.add_child(spacer(4))
	# ★ 動作鈕只剩一顆（B3.7.1，使用者指定）。歷次拿掉的理由是同一條：
	#   **一個模式鈕如果只是「同一件事的比較慢的做法」，它就該消失。**
	#   「連線」B1.6.2 被拖曳取代；「移動」B1.3.1 改中鍵拖；
	#   「升級」「拆除」B3.7 被檢視面板上的鈕取代——切模式 → 點目標 → 切回建造，
	#   三步裡有兩步不是決定。
	#   藍圖留著：它不是動詞，是**手上拿著的東西**，沒有別的地方表達得了。
	var bp_btn_mode := tool_button(group, "藍圖")
	bp_btn_mode.toggled.connect(on_mode.bind(scr.Mode.BLUEPRINT))
	mode_buttons[scr.Mode.BLUEPRINT] = bp_btn_mode
	col.add_child(UiKit.touchable(bp_btn_mode))


func on_build_type(pressed: bool, type: String) -> void:
	if not pressed:
		if scr.build_type == type:
			scr.build_type = ""
			scr.message = ""
			hintbar.refresh_hint()
		return
	scr.mode = scr.Mode.BUILD
	scr.build_type = type
	scr.drag_from = Vector2i(-1, -1)
	scr.message = ""
	hintbar.refresh_hint()


## 藍圖鈕。同建造鈕，`toggled` ＋ 再按一次回到建造（B3.7.1）。
func on_mode(pressed: bool, new_mode: int) -> void:
	if not pressed:
		if scr.mode == new_mode:
			scr.mode = scr.Mode.BUILD
			scr.message = ""
			hintbar.refresh_hint()
		return
	scr.mode = new_mode
	# 換模式就放下手上的藍圖：拿著它的時候左鍵是「展開」，而玩家切走
	# 是為了做別的事——留著會讓下一次左鍵做出他沒想要的事。
	if scr.bp_index >= 0:
		scr.bp_index = -1
		bppanel.refresh_blueprints()
	scr.drag_from = Vector2i(-1, -1)
	scr.message = ""
	hintbar.refresh_hint()
