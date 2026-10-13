extends Node
## 建造欄（左欄）：這一關可蓋的節點清單，以及「藍圖」那顆手上拿著的東西。
##
## 清單裝在捲動容器裡、模式鈕釘在它下面——十三種節點（M3 會到 29 種）再長也只在區域內捲，
## 永遠碰不到底欄（B2.4.2）。「這一局蓋得出哪些」由 `buildable()` 回答。

const NodeDefs := preload("res://data/NodeDefs.gd")
const BlueprintPanel := preload("res://scripts/screens/battle/hud/BlueprintPanel.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組。
var bppanel: BlueprintPanel = null
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
