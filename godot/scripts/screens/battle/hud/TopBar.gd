extends Node
## 頂欄與時間流：能量／礦砂／合金／波次／核心五欄，加上底欄左群的「快進」「提前召喚」。
##
## 兩者放在一起是因為它們講同一件事——**這一分鐘的時間怎麼走**：頂欄顯示它走到哪，
## 快進與提前召喚改變它走多快（`10_GDD.md` §3.4、§7.1、§7.6）。
## 欄位的版面（`TOP_CELLS`）是 `20_ART_DIRECTION.md` §7.2 B-2 的三階字級＋固定寬度。

const BattleController := preload("res://scripts/game/BattleController.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Score := preload("res://scripts/sim/Score.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const Motion := preload("res://scripts/render/Motion.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null


## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## 頂欄六欄的版面（B2.4.4，§7.2 的 B-2 ＋ B-3）。
##
## 每一欄 ＝ `[標籤 sm] [數值 vs 級·固定寬·右對齊] [註腳 sm·固定寬·右對齊]`。
##
## **三階不是為了好看，是為了回答不同的問題**（§7.2 B-2）：
##   · 主（22 ＝ `text.lg`）＝**能量／波次／核心**——「我現在會不會輸」的全部答案
##   · 次（16 ＝ `text.base`）＝礦砂、合金——「我買不買得起」
##   · 附屬（13 ＝ `text.sm`）＝`▲/秒`、儲槽、交戰、擊殺——上面那幾個的**註腳**
##
## **固定寬度是 §3 那條硬性要求的正解**（「資源數字跳動時不得左右位移」）。
## ⚠ 原稿說要開 OpenType `tnum`——**量過之後那是修一個不存在的問題**：微軟正黑體
## 的數字本來就等寬，同位數換數字（1111→8888）本來就不位移。真正會位移的是
## **跨位數**（999→1000），而 `tnum` 對它無效，只有固定寬度擋得住。
## 量測留在 `_topbar_selftest()`，兩種情況各一條斷言。
##
## 寬度是**猜的，然後由 `bar_clear` 驗**（頂欄不得長到撞上縮放鈕）。固定寬度讓
## 那條斷言從「這一刻的數值排得下」升級成「任何數值都排得下」。
##
## ★ **從七欄縮成五欄**：三階字級排不下 11 個數字（第一版實測超出 166px），
##   而 §2 反模式清單自己就寫著「每個畫面最多 4 個『主要數字』」。
##   **搬家不是刪除**（B-2 說資訊完備性不能砍）：
##     · 儲槽存量 → 能量面板（它是「充放電」那兩列的分母），地圖上每顆儲槽
##       身上還有一圈琥珀弧，「哪一顆滿了」讀得到
##     · 交戰座數 → 併進能量那一格的註腳（它就是能量需求的解釋）
##     · 擊殺 → 併進波次那一格的註腳（兩個都在講「這一波打得怎樣」）
const TOP_CELLS := [
	{"tag": "礦砂", "vw": 64, "vs": 16, "nw": 48},
	{"tag": "合金", "vw": 56, "vs": 16, "nw": 48},
	{"tag": "能量", "vw": 88, "vs": 22, "nw": 72},
	{"tag": "",     "vw": 144, "vs": 22, "nw": 120},
	{"tag": "核心", "vw": 116, "vs": 22, "nw": 0},
]

var top: HBoxContainer = null

## 頂欄每一欄的數值／註腳標籤。**存參照而不是每次 `get_child(i).get_child(j)`**
## ——那種索引在版面改一次就會安靜地指到別格（RG-134 是同一個錯法的按鈕版）。
var top_values: Array[Label] = []

var top_notes: Array[Label] = []

var ff_button: Button = null

var summon_button: Button = null


## ★ 頂欄五欄（B2.4.4）。**加入順序就是繪圖順序**——由 `Battle._build_ui()` 照順序叫。
func build_top() -> void:
	# ★ 頂欄三階 ＋ 固定寬度（B2.4.4）。舊版是七個 15px（**階外**）的 Label 直接
	#   丟進 HBox——11 個數字同一階，而且寬度隨數值變。規格見 `TOP_CELLS`。
	top = UiKit.hbox(8)
	top.position = Vector2(120, 12)
	scr.add_child(top)
	top_values.clear()
	top_notes.clear()
	for spec: Dictionary in TOP_CELLS:
		var cell := UiKit.hbox(4)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(spec["tag"]) != "":
			cell.add_child(UiKit.label(String(spec["tag"]), 13, Palette.TEXT_SECONDARY, false))
		var v := UiKit.label("", int(spec["vs"]), Palette.TEXT_PRIMARY, false)
		v.custom_minimum_size.x = float(spec["vw"])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		top_values.append(v)
		var n := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		n.custom_minimum_size.x = float(spec["nw"])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(n)
		top_notes.append(n)
		top.add_child(cell)


## 底欄左群：快進、提前召喚（`group` 是 `Battle._build_ui()` 排好的那個 HBox）。
func build_time_controls(group: Control) -> void:
	ff_button = Button.new()
	ff_button.text = "快進 4×"
	ff_button.pressed.connect(on_fast_forward)
	group.add_child(UiKit.touchable(ff_button))
	summon_button = Button.new()
	summon_button.pressed.connect(on_summon_now)
	# ★ **全底欄唯一一顆不可逆的鈕**：按下去這一波就提早來，獎勵倍率也定了。
	#   §7.2 B-5 原本開的處方是 `energy.amber` 描邊——**那違反 §1.1 配色紀律 2**
	#   （琥珀專屬於能量，而提前召喚跟耗能無關）。改用 `warn.orange`：紀律 1 說
	#   橙／品紅專屬於「敵人與危險狀態」，而這顆鈕做的事**就是把敵潮叫過來**，
	#   它是玩家自己選的危險。同一條紀律，剛好也是更強的編碼。
	summon_button.add_theme_color_override("font_color", Palette.WARN_ORANGE)
	summon_button.add_theme_color_override("font_hover_color", Palette.WARN_ORANGE)
	group.add_child(UiKit.touchable(summon_button))


func refresh_top() -> void:
	_refresh_summon()
	# ★ 快進鈕自己講自己開沒開（B2.4.4）。它不是 toggle（按下去只是切換 tick 倍率），
	#   所以在此之前**畫面上唯一的指示是頂欄那段「▶4×」**——因在底欄、果在頂欄。
	if ff_button != null:
		ff_button.text = "▶ 快進中 4×" if s.speed_mult > 1 else "快進 4×"
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	# **能量條不在此列**——它是圖形，長度即資訊（§6.2 硬性要求 1），畫在 `_draw()`。
	if Hooks.naked:
		top.visible = false
		return
	var r: Dictionary = s.rates
	var core_full := NodeDefs.hp("core")
	var core_col: Color = (
		Palette.WARN_ORANGE if s.core_hp() < core_full else Palette.ORDER_BRIGHT
	)
	# 一欄一列：[數值, 註腳, 顏色]。順序與 `TOP_CELLS` 一致。
	# 合金緊貼礦砂：**兩個都是造價貨幣**，玩家看的是同一個問題（我買得起嗎）。
	# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束），
	# 所以它掛在能量那一格旁邊當註腳，不是一個獨立的數字。
	var texts := [
		[UiKit.commas(int(s.ore)), "▲%.1f/秒" % r["ore_in"], Palette.ORDER_CYAN],
		[UiKit.commas(int(s.alloy)), "▲%.1f/秒" % r["alloy_in"], Palette.ALLOY_VIOLET],
		[
			"%.0f/%.0f" % [r["power_supply"], r["power_demand"]],
			"交戰 %d 座" % int(r["engaged"]),
			Palette.ENERGY_AMBER,
		],
		# ★ 擊殺數**不在頂欄**（B2.4.4）：它是計分不是決策輸入——沒有任何一個
		#   當下的操作取決於它，而頂欄的每一格都要為「我現在該做什麼」服務。
		#   它在局末結算裡；回收者換到的能量在能量面板有專屬一列。
		[
			_phase_parts()[0], _phase_parts()[1],
			Palette.TIDE_MAGENTA if s.phase == "wave" else Palette.TEXT_SECONDARY,
		],
		["%.0f/%.0f" % [maxf(0.0, s.core_hp()), core_full], "", core_col],
	]
	for i in texts.size():
		var col: Color = texts[i][2]
		top_values[i].text = String(texts[i][0])
		top_values[i].add_theme_color_override("font_color", col)
		top_notes[i].text = String(texts[i][1])
		# 註腳走同一個色相但降一階字級：**顏色維持分群，層級交給字級**
		# （§7.2 B-2：顏色分群是這一批做對的事，要留著）。
		top_notes[i].add_theme_color_override("font_color", Palette.alpha(col, 0.7))
	# ★ 倒數最後 10 秒脈動（`20_ART_DIRECTION.md` §4.3「一定要動」清單，B1.6）。
	#   **它動的是階段那一格**，不是整條頂欄——脈動要指向「時間快到了」這一件事。
	#   週期用 `dur.slow`：比環境呼吸急、又不到讓人分心的程度。
	var phase_label := top_values[3]
	var urgent: bool = s.phase == "prep" and s.prep_time() - s.phase_time <= 10.0
	phase_label.modulate = Palette.MOD_FULL
	if urgent:
		phase_label.add_theme_color_override("font_color", Palette.WARN_ORANGE)
		phase_label.modulate = Palette.mod_alpha(Motion.pulse01(s.tick_count, Motion.SLOW, 0.45))


## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
##
## ★ 回傳 `[主, 附屬]` 兩段（B2.4.4）：主的是「我還有多少時間／現在第幾波」
## （`text.lg`），附屬的是波號、快進倍率、殘敵（`text.sm`）。
## **原本是一整串塞在同一個 22px 的標籤裡**，量到那一格 299px、把整條頂欄
## 撐出畫面 —— 而它裡面本來就有兩階資訊。
func _phase_parts() -> Array:
	# ★ 難度層掛在附屬那一段（B2.6）。**只在第 1 層以上出現**：第 0 層寫「標準」
	#   等於在每一局的頂欄佔一格去講「沒有任何額外規則」。
	var tier := "　%s" % Difficulty.of(s.difficulty)["name"] if s.difficulty > 0 else ""
	match s.phase:
		"prep":
			var left: float = maxf(0.0, s.prep_time() - s.phase_time)
			# ★ 快進倍率**不在這裡**（B2.4.4）：它原本同時出現在頂欄與底欄那顆
			#   「快進 4×」鈕上，而那顆鈕自己**看不出開沒開**（它不是 toggle）。
			#   指示搬到按鈕上——因與果放在同一個地方，頂欄也省下一段會變長的字。
			# 駐足在核心的敵人不會隨波次結束而消失（§3.5）。不講的話，
			# 玩家會看到核心在準備期掉血卻找不到原因。
			var left_over := "　殘敵 %d" % s.enemies.size() if not s.enemies.is_empty() else ""
			return ["準備期 %0.1fs" % left, "下一波 %d%s%s" % [s.wave_index + 1, left_over, tier]]
		"wave":
			return ["第 %d 波" % s.wave_index, "敵人 %d%s" % [s.enemies.size(), tier]]
		"won":
			return ["通關", ""]
		_:
			return ["核心已毀", ""]


## 快進只在準備期能按（`10_GDD.md` B5：可跳過等待，戰鬥期不可加速也不可減速）。
func on_fast_forward() -> void:
	if s.phase != "prep":
		return
	s.speed_mult = 1 if s.speed_mult > 1 else FAST_FORWARD_RATE
	refresh_top()


## ★ 提前召喚：**按鈕常駐顯示當前獎勵倍率**（`10_GDD.md` §6.2 硬性要求 3）——
## 下注的誘惑要一直在眼前，而不是按下去才知道賭到多少。
## 倍率隨倒數每 tick 縮水，所以這個字串每幀重算。
func _refresh_summon() -> void:
	if summon_button == null:
		return
	var can: bool = s.phase == "prep"
	summon_button.disabled = not can
	if Hooks.naked or not can:
		summon_button.text = "提前召喚"
		return
	var bonus := Score.summon_bonus(maxf(0.0, s.prep_time() - s.phase_time), s.prep_time())
	summon_button.text = "提前召喚 +%d%%" % roundi((bonus - 1.0) * 100.0)


func on_summon_now() -> void:
	BattleController.start_wave(s)
	refresh_top()
