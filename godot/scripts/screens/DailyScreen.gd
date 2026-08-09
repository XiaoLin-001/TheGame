extends Control
## 每日挑戰（`10_GDD.md` §3.10、§7.11；B2.2）。
##
## 這個畫面要回答三個問題，版面就只長成這三個問題的形狀：
##   ① **今天打的是哪一張圖？**（日期 ＋ 種子，種子要看得見——它是「大家同一張圖」
##      這句話唯一可以自己驗證的東西）
##   ② **兩張榜分別是什麼、我今天各打到多少？**
##   ③ **我以前打得怎樣？**（最近幾天的歷史）
##
## ★ **誠實註記是規格的一部分**（§3.10 明文）：第一版純離線，兩榜是兩個本機數字，
##   沒有排名也沒有對手。畫面上要寫出來——「不要在文案中宣稱一個尚未存在的競技場」。
##   這不是自謙，是不要騙玩家。

const Daily := preload("res://scripts/sim/Daily.gd")

const CARD := Vector2(360, 150)

## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()
## 開始一局。由呼叫端指派：`func(board: String, date: String, seed: int)`。
var on_start: Callable = Callable()

## 兩顆開始鈕（自檢要按得到），與 `Daily.BOARDS` 同索引。
var _buttons: Array[Button] = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test and Hooks.panel == "daily":
		_click_selftest.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


## 今天是幾號。**系統時鐘只在這一支出現**——`sim/Daily.gd` 是純函式，
## 日期一律由呼叫端傳進去（否則「同一天同一張圖」會取決於測試在幾點跑）。
##
## `TL_*` 底下固定回 2026-01-01：截圖與自檢不能因為今天是幾號而長不一樣
## （RG-61 的同一條紀律——同參數在任何機器上、任何一天拍出同一張圖）。
static func today() -> Dictionary:
	if Env.any_hook():
		return {"year": 2026, "month": 1, "day": 1}
	return Time.get_date_dict_from_system()


func _build() -> void:
	UiKit.clear(self)
	var d := today()
	var date := Daily.date_key(d["year"], d["month"], d["day"])
	var seed_v := Daily.seed_of(d["year"], d["month"], d["day"])

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UiKit.vbox(12)
	center.add_child(col)

	col.add_child(UiKit.label("每日挑戰", 32, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label(
		"%s　　地圖種子 %d" % [date, seed_v], 16, Palette.ORDER_CYAN
	))
	# ★ 誠實註記（§3.10）。放在標題底下而不是塞在角落——它修正的是
	#   「排行榜」這三個字會讓人產生的預期，晚一秒看到就晚一秒修正。
	col.add_child(UiKit.label(
		"離線版：兩張榜都是你自己的本機紀錄，還沒有對手。",
		14, Palette.TEXT_SECONDARY
	))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)

	var day: Dictionary = GameState.data.get("daily", {})
	var stale: bool = Daily.rolled_over(String(day.get("date", "")), date)
	var today_best: Dictionary = day.get("today", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	_buttons.clear()
	for i in Daily.BOARDS.size():
		row.add_child(_card(Daily.BOARDS[i], date, seed_v, today_best, stale))

	col.add_child(_history(day.get("history", [])))

	# ★ 走 `UiKit.back_row()`（B2.7.2）。這一顆原本直接丟進 `VBox`，
	#   於是被拉成整欄寬——全案八顆返回鈕裡唯一沒包 `HBox` 的那一顆（RG-152）。
	var nav := UiKit.back_row("返回標題", on_exit)
	if nav != null:
		col.add_child(nav)


## 一張榜的卡。
##
## 兩張卡**用同一支函式生**：它們在規格上只差起始配置（§3.10「不得拆成兩套邏輯」），
## 畫面上也就不該長成兩塊各自維護的版面。
func _card(
	board: String, date: String, seed_v: int, today_best: Dictionary, stale: bool
) -> Control:
	var uniform: bool = board == Daily.UNIFORM
	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	var col := UiKit.vbox(6)
	box.add_child(col)
	col.add_child(UiKit.label(
		"統一配置榜" if uniform else "自由配置榜", 22,
		Palette.OK_GREEN if uniform else Palette.ENERGY_AMBER
	))
	col.add_child(UiKit.label(
		"固定配置，不吃你的科技與課金" if uniform else "你的完整戰力（科技全開）",
		14, Palette.TEXT_SECONDARY, false
	))
	# 換日之後昨天的數字還躺在存檔裡，但它是**另一張圖**上打出來的——
	# 顯示成今天的成績等於說謊。開一局就會被 `apply_daily()` 推進歷史。
	var slot: Dictionary = {} if stale else today_best.get(board, {})
	var wave := int(slot.get("wave", 0))
	col.add_child(UiKit.label(
		"今日最佳　尚未挑戰" if wave <= 0 else "今日最佳　%d 波　產能 %.1f" % [
			wave, float(slot.get("output", 0.0))
		], 16, Palette.TEXT_PRIMARY, false
	))
	var btn := Button.new()
	btn.text = "開始（統一配置）" if uniform else "開始（自由配置）"
	btn.pressed.connect(func() -> void:
		if on_start.is_valid():
			on_start.call(board, date, seed_v)
	)
	_buttons.append(btn)
	col.add_child(UiKit.touchable(btn))
	return box


func _history(rows: Array) -> Control:
	var box := UiKit.panel()
	var col := UiKit.vbox(4)
	box.add_child(col)
	col.add_child(UiKit.label("歷史紀錄", 16, Palette.TEXT_PRIMARY))
	if rows.is_empty():
		# 「尚無紀錄」而不是一張空表或一排 0——0 波看起來像一個很爛的成績，
		# 而事實是還沒玩過（主選單的無盡那一顆同一條理由）。
		col.add_child(UiKit.label("尚無紀錄", 13, Palette.TEXT_SECONDARY, false))
		return box
	for i in mini(rows.size(), 8):
		var r: Dictionary = rows[i]
		col.add_child(UiKit.label("%s　%s　%d 波　產能 %.1f" % [
			String(r.get("date", "")),
			"統一" if String(r.get("board", "")) == Daily.UNIFORM else "自由",
			int(r.get("wave", 0)), float(r.get("output", 0.0)),
		], 13, Palette.TEXT_SECONDARY, false))
	return box


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=daily`）。
##
## 這個畫面的價值就是「兩顆鈕點得到，而且點下去進的是**今天那張圖**」，
## 所以斷言看的是實際開出來的局面，不是回呼有沒有被叫到（B2.1a 的假綠燈：
## 印 `endless=true` 而遊戲開的是淺灘）。
func _click_selftest() -> void:
	await get_tree().process_frame
	var two: bool = _buttons.size() == 2
	var d := today()
	var want_seed := Daily.seed_of(d["year"], d["month"], d["day"])
	# 誠實註記真的在畫面上——它是規格的一部分（§3.10），不是可有可無的裝飾。
	var honest := false
	for node: Node in find_children("*", "Label", true, false):
		if (node as Label).text.contains("還沒有對手"):
			honest = true
	# ⚠ **GDScript 的 lambda 對區域變數是傳值捕捉**：在裡面寫 `started = {...}`
	#   改的是它自己那一份副本，外面永遠讀到空字典（斷言會恆為 false）。
	#   一律**變更同一個字典**，中間清空也要用 `clear()` 而不是重新賦值。
	var started: Dictionary = {}
	on_start = func(board: String, date: String, sd: int) -> void:
		started["board"] = board
		started["date"] = date
		started["seed"] = sd
	if two:
		_buttons[0].emit_signal("pressed")
	await get_tree().process_frame
	var uniform_ok: bool = (
		String(started.get("board", "")) == Daily.UNIFORM
		and int(started.get("seed", 0)) == want_seed
	)
	started.clear()
	if two:
		_buttons[1].emit_signal("pressed")
	await get_tree().process_frame
	var free_ok: bool = String(started.get("board", "")) == Daily.FREE
	var ok: bool = two and honest and uniform_ok and free_ok
	print("[TL_CLICKTEST/daily] two=%s honest=%s uniform=%s(seed=%d) free=%s → %s" % [
		two, honest, uniform_ok, want_seed, free_ok, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)
