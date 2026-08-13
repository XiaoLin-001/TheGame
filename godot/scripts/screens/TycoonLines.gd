extends Control
## 潮汐公司 — 產線編輯（`10_GDD.md` §3.8、§7.14；B2.5）。**兩個畫面裡的第二個。**
##
## ── 為什麼這個畫面是「指派」而不是「佈局」──────────────────────────
## §3.8 原文寫「排產線（**複用流量網路引擎**）」。B2.5 沒有照做，理由寫在
## `10_GDD.md` §7.14 的第一張表：空間式產線編輯器是**第二個 `Battle` 畫面**，
## 而且它重複塔防的核心動詞（拉線佈局）。§3.8 自己說 tycoon「刻意保持單薄」、
## 留存角色是「一兩分鐘就走」——一個五分鐘的佈局編輯器直接違反那句話。
##
## 指派仍然是**真的取捨**：接單上限比產線位多兩張（`order_cap = slots + 2`），
## 所以從廠等 1 開始，「該讓哪一張先上線」就一直是一個要回答的問題。
## 這和優先權滑桿是同一類決定（稀缺的產能要餵誰），主題上對得起來。

const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")


var on_exit: Callable = Callable()

## 供自檢用：每一顆「上線」鈕（依產線位順序，每格取第一個候選）。
var _assign_buttons: Array[Button] = []
var _back_button: Button = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


func _state() -> Dictionary:
	return GameState.data["tycoon"]


func _build() -> void:
	UiKit.clear(self)
	_assign_buttons.clear()

	var col := UiKit.screen(self, 12)
	var s := _state()
	var level := int(s["level"])
	var orders: Array = s["orders"]

	col.add_child(UiKit.label("產線編輯", 32, Palette.ORDER_BRIGHT, false))
	# ★ 這一行是整個系統的說明書：**產線位就是倉儲上限**（§7.14）。
	#   不寫的話，玩家回來看到「做完了但沒有第二張」會以為是 bug。
	# ⚠ `Label` **不解析 Markdown**——`**強調**` 會原樣印出兩排星號。
	#   B0.7.1／B0.7.3／B1.1 各犯過一次，這是第四次（截圖當場抓到）。
	#   **強調一律用「」。**
	col.add_child(UiKit.label(
		"產線位 %d 個・已接 %d 張。一個產線位一次做一張，"
		% [TycoonSim.slots(level), orders.size()]
		+ "做完就停在那裡等你收成，離線再久也不會多做。",
		13, Palette.TEXT_SECONDARY, false
	))

	var nav := UiKit.back_row("返回訂單板", on_exit)
	if nav != null:
		col.add_child(nav)
		_back_button = nav.get_child(0) as Button

	var scroll := UiKit.scroll()
	col.add_child(scroll)
	var list := UiKit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for line in TycoonSim.slots(level):
		list.add_child(_line_row(line))

	var idle := _idle_indices()
	if not idle.is_empty():
		list.add_child(UiKit.label(
			"未上線的 %d 張不會動，也不會自己排隊補上。" % idle.size(),
			13, Palette.WARN_ORANGE, false
		))


## 一格產線位。目前那張 ＋ 可以換上去的每一張。
func _line_row(line: int) -> Control:
	var s := _state()
	var orders: Array = s["orders"]
	var here := TycoonSim.order_on_line(s, line)

	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := UiKit.vbox(8)
	box.add_child(col)

	var head := "產線位 %d　" % (line + 1)
	var tone: Color = Palette.TEXT_SECONDARY
	if here >= 0:
		var order: Dictionary = orders[here]
		var tier := int(order["tier"])
		head += "%s（第 %d 階）　%d／%d" % [
			String(TycoonSim.ORDER_NAMES[tier]), tier,
			int(float(order["done"])), int(TycoonSim.work_of(tier))
		]
		if TycoonSim.is_done(order):
			head += "　已完成，到訂單板收成才空得出來"
			tone = Palette.OK_GREEN
		else:
			tone = Palette.ENERGY_AMBER
	else:
		head += "空著，沒有產出"
		tone = Palette.WARN_ORANGE
	col.add_child(UiKit.label(head, 16, tone, false))

	var row := UiKit.hbox(8)
	col.add_child(row)
	for i: int in _idle_indices():
		var order: Dictionary = orders[i]
		var tier := int(order["tier"])
		var b := Button.new()
		b.text = "上線　%s　%d／%d" % [
			String(TycoonSim.ORDER_NAMES[tier]), int(float(order["done"])),
			int(TycoonSim.work_of(tier))
		]
		b.pressed.connect(_assign.bind(i, line))
		row.add_child(UiKit.touchable(b))
		# 自檢只需要每一格的第一顆。
		if row.get_child_count() == 1:
			_assign_buttons.append(b)
	if here >= 0 and not TycoonSim.is_done(orders[here] as Dictionary):
		var off := Button.new()
		off.text = "下線（進度保留）"
		off.pressed.connect(_assign.bind(here, -1))
		row.add_child(UiKit.touchable(off))
	if row.get_child_count() == 0:
		col.add_child(UiKit.label(
			"沒有可以換上來的訂單。先到訂單板接一張。", 13, Palette.TEXT_DISABLED, false
		))
	return box


## 已接但沒上線的訂單索引。
func _idle_indices() -> Array[int]:
	var out: Array[int] = []
	var orders: Array = _state()["orders"]
	for i in orders.size():
		if int((orders[i] as Dictionary).get("line", -1)) < 0:
			out.append(i)
	return out


func _assign(index: int, line: int) -> void:
	if not TycoonSim.assign(_state(), index, line):
		return
	AudioBus.play("ui_click")
	SaveService.save_from(GameState.data)
	_build()
