extends Control
## 難度層選擇（`10_GDD.md` §3.11、§7.16；B2.6）。**無盡模式的入口。**
##
## 這個畫面要回答的問題只有三個，一張卡各一段：
##   ① **這一層改了什麼規則**（逐條列出來——難度層的全部價值就是規則差異，
##      藏起來的話它就只是一個讓數字變大的滑桿）
##   ② **我在這一層打到哪了**（逐層各一筆紀錄，`SaveService` sv3）
##   ③ 鎖著的話**要做什麼才開得了**，不是一個沒有下文的灰色方塊
##
## ★ 為什麼無盡要多這一層畫面：難度層是**選擇**，而選擇必須在開局前發生。
##   塞進主選單那顆鈕（按一下換一層）的話，規則卡就沒有地方放，
##   而「按下去會得到什麼規則」正是這個選擇唯一的內容。

const Difficulty := preload("res://data/Difficulty.gd")

## 卡片尺寸。四張 ＋ 三道間距要放進 1280 的設計基準。
## 高度只是**下限**：規則列一層比一層多，卡片自己長高，而「出擊」那一排靠
## 一個會撐開的空白物推到底——四顆鈕不對齊的話，這一排看起來像四張沒對好的紙。
const CARD := Vector2(272, 208)


## 回上一層（標題）。由呼叫端指派；沒指派就不畫返回鈕。
var on_exit: Callable = Callable()

## 每張卡上那顆「出擊」鈕（與層序同索引），供自檢按。
var _enter_buttons: Array[Button] = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# `and Hooks.panel == "tiers"`：本畫面也會被標題畫面的自檢掛起來，
	# 少了這一條會把別人的自檢從中間打斷（`Campaign.gd` 的同一課）。
	if Hooks.click_test and Hooks.panel == "tiers":
		Hooks.run_selftest(self)


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


func _build() -> void:
	UiKit.clear(self)
	AudioBus.music("menu")
	_enter_buttons.clear()

	var col := UiKit.screen(self, 14)
	col.add_child(UiKit.label("無盡", 32, Palette.ORDER_BRIGHT, false))
	col.add_child(UiKit.label(
		"程序生成的地圖，波次無限。難度層改的是規則，紀錄逐層各記一筆。", 15,
		Palette.TEXT_SECONDARY, false
	))
	var nav := UiKit.back_row("返回標題", on_exit)
	if nav != null:
		col.add_child(nav)

	var row := UiKit.hbox(12)
	col.add_child(row)
	for i in Difficulty.count():
		row.add_child(_card(i))


func _card(tier: int) -> Control:
	var why := Difficulty.why_locked(GameState.data, tier)
	var open := why == ""
	var best := Difficulty.best(GameState.data, tier)

	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 卡片裡有按鈕
	# 鎖住的卡整張變暗，但內容仍然讀得到：它是路線圖，先看見後面有什麼
	# 才知道要往哪走（`screens/Campaign.gd` 的同一條）。
	if not open:
		box.modulate = Palette.MOD_LOCKED
	var col := UiKit.vbox(6)
	box.add_child(col)

	col.add_child(UiKit.label(
		Difficulty.name_of(tier), 20,
		Palette.TEXT_PRIMARY if open else Palette.TEXT_DISABLED, false
	))
	# 規則列在資料表裡是空的（`data/Difficulty.gd`：`rules` 的長度就是疊了幾條），
	# 「沒有額外規則」這句話由畫面補——空白的卡片說不出它是刻意空的。
	var rules: Array = Difficulty.rules_of(tier)
	if rules.is_empty():
		col.add_child(UiKit.label("沒有額外規則", 13, Palette.TEXT_SECONDARY, false))
	for rule: String in rules:
		col.add_child(UiKit.label("・%s" % rule, 13, Palette.WARN_ORANGE, false))

	col.add_child(UiKit.label(
		"個人最佳　%s" % (
			"尚無紀錄" if int(best["wave"]) <= 0
			else "%d 波・產能 %.1f" % [int(best["wave"]), float(best["output"])]
		), 13, Palette.ENERGY_AMBER if int(best["wave"]) > 0 else Palette.TEXT_DISABLED, false
	))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var b := Button.new()
	if open:
		b.text = "出擊"
		b.pressed.connect(_enter.bind(tier))
	else:
		b.text = why
		b.disabled = true
	_enter_buttons.append(b)
	col.add_child(UiKit.touchable(b))
	return box


## 開一局。**每按一次換一張圖**，`TL_SEED` 底下則恆定（`Rng.next_seed()`，
## 同 `Main._endless()`）。指派要在 `add_child()` 之前——`Battle._ready()`
## 一進來就 `_setup_session()`。
func _enter(tier: int) -> void:
	UiKit.clear(self)
	var battle := BattleScreen.new()
	battle.endless_seed = Rng.next_seed()
	battle.difficulty = tier
	battle.on_exit = _build
	add_child(battle)
