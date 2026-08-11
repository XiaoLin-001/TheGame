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
const BattleScreen := preload("res://scripts/screens/Battle.gd")

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
		_click_selftest.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tiers`）。
##
## 存檔在有鉤子時是零進度 → 戰役一關都沒過 → **只有第 0 層是開的**。
## 所以自檢自己先把戰役塞成滿星、再塞一筆第 1 層的紀錄，逐段驗解鎖階梯
## 真的往前走（**不寫檔**——`SaveService.persist=false`）。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var cards: bool = _enter_buttons.size() == Difficulty.count()
	var first_open: bool = cards and not _enter_buttons[0].disabled
	var rest_locked: bool = cards and _enter_buttons[1].disabled
	var says_why: bool = cards and _enter_buttons[1].text.contains("戰役")

	# 戰役全通 → 第 1 層開，第 2 層仍鎖著（它要的是第 1 層的波數）。
	var stars: Dictionary = (GameState.data["campaign"] as Dictionary)["stars"]
	for id: String in preload("res://data/Campaign.gd").ids():
		stars[id] = 3
	_build()
	await get_tree().process_frame
	var tier1_open: bool = not _enter_buttons[1].disabled
	var tier2_locked: bool = _enter_buttons[2].disabled
	var says_wave: bool = _enter_buttons[2].text.contains("波")

	# 第 1 層撐過門檻 → 第 2 層開。**走 `apply_endless`**，不是直接塞欄位：
	# 要驗的是「寫紀錄的那支函式與讀解鎖的那支函式對得上」。
	SaveService.apply_endless(GameState.data, Difficulty.UNLOCK_WAVE, 1.0, 1)
	_build()
	await get_tree().process_frame
	var tier2_open: bool = not _enter_buttons[2].disabled

	# ESC 要在**進局之前**驗：進去之後 ESC 是局內選單的，而這個畫面已經被清掉了。
	var esc_back: bool = await UiKit.esc_reaches(self)

	await UiKit.click(_enter_buttons[1])
	var battle: Node = null
	for c: Node in get_children():
		if c.get_script() == BattleScreen:
			battle = c
	# ★ 問的是**局面真的用了生成圖、而且真的帶著那一層的倍率**
	#   ——「畫面開起來了」在 B2.1a 是一個假綠燈（開的是淺灘測試圖）。
	var entered: bool = battle != null
	var generated: bool = entered and bool((battle.s.map as Dictionary).get("endless", false))
	var carried: bool = entered and int(battle.s.difficulty) == 1
	var scaled: bool = entered and is_equal_approx(
		float(battle.s.mods["enemy_hp_mult"]), float(Difficulty.of(1)["enemy_hp"])
	)

	var ok: bool = (
		cards and first_open and rest_locked and says_why and tier1_open and tier2_locked
		and says_wave and tier2_open and esc_back and entered and generated and carried and scaled
	)
	print("[TL_CLICKTEST/tiers] cards=%s(%d) t0_open=%s locked=%s says_why=%s t1_open=%s t2_locked=%s says_wave=%s t2_open=%s esc_back=%s entered=%s gen=%s tier=%s hp_mult=%s → %s" % [
		cards, _enter_buttons.size(), first_open, rest_locked, says_why, tier1_open,
		tier2_locked, says_wave, tier2_open, esc_back, entered, generated, carried, scaled,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


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
