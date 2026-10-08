class_name BattleTopbar
extends RefCounted
## 頂欄：資源／能量／階段／核心血量的逐欄顯示。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Motion := preload("res://scripts/render/Motion.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Readout := preload("res://scripts/game/Readout.gd")

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

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func refresh_top() -> void:
	battle.bars.refresh_summon()
	# ★ 快進鈕自己講自己開沒開（B2.4.4）。它不是 toggle（按下去只是切換 tick 倍率），
	#   所以在此之前**畫面上唯一的指示是頂欄那段「▶4×」**——因在底欄、果在頂欄。
	if battle.bars.ff_button != null:
		battle.bars.ff_button.text = "▶ 快進中 4×" if battle.s.speed_mult > 1 else "快進 4×"
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	# **能量條不在此列**——它是圖形，長度即資訊（§6.2 硬性要求 1），畫在 `_draw()`。
	if Hooks.naked:
		top.visible = false
		return
	var r: Dictionary = battle.s.rates
	var core_full := NodeDefs.hp("core")
	var core_col: Color = (
		Palette.WARN_ORANGE if battle.s.core_hp() < core_full else Palette.ORDER_BRIGHT
	)
	# 一欄一列：[數值, 註腳, 顏色]。順序與 `TOP_CELLS` 一致。
	# 合金緊貼礦砂：**兩個都是造價貨幣**，玩家看的是同一個問題（我買得起嗎）。
	# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束），
	# 所以它掛在能量那一格旁邊當註腳，不是一個獨立的數字。
	var texts := [
		[UiKit.commas(int(battle.s.ore)), "▲%.1f/秒" % r["ore_in"], Palette.ORDER_CYAN],
		[UiKit.commas(int(battle.s.alloy)), "▲%.1f/秒" % r["alloy_in"], Palette.ALLOY_VIOLET],
		[
			"%.0f/%.0f" % [r["power_supply"], r["power_demand"]],
			"交戰 %d 座" % int(r["engaged"]),
			Palette.ENERGY_AMBER,
		],
		# ★ 擊殺數**不在頂欄**（B2.4.4）：它是計分不是決策輸入——沒有任何一個
		#   當下的操作取決於它，而頂欄的每一格都要為「我現在該做什麼」服務。
		#   它在局末結算裡；回收者換到的能量在能量面板有專屬一列。
		[
			Readout.phase_parts(battle.s)[0], Readout.phase_parts(battle.s)[1],
			Palette.TIDE_MAGENTA if battle.s.phase == "wave" else Palette.TEXT_SECONDARY,
		],
		["%.0f/%.0f" % [maxf(0.0, battle.s.core_hp()), core_full], "", core_col],
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
	var urgent: bool = battle.s.phase == "prep" and battle.s.prep_time() - battle.s.phase_time <= 10.0
	phase_label.modulate = Palette.MOD_FULL
	if urgent:
		phase_label.add_theme_color_override("font_color", Palette.WARN_ORANGE)
		phase_label.modulate = Palette.mod_alpha(Motion.pulse01(battle.s.tick_count, Motion.SLOW, 0.45))

