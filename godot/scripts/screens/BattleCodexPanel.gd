class_name BattleCodexPanel
extends RefCounted
## 角色簡介浮層（滑鼠停在建造鈕上時出現）。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Readout := preload("res://scripts/game/Readout.gd")

var codex_button: Button = null

var codex_panel: Control = null

var codex_label: Label = null

var codex_on: bool = true

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ 角色簡介浮層（使用者要求）。滑鼠停在左欄的建造鈕上就浮出來、移開就收，
## 底欄「圖鑑」可整個關掉。**半透明**：它蓋在地圖上，要讓人看得見底下是什麼。
##
## 內容一律**從 `data/NodeDefs.gd` 現算**，不另外寫一份文案表——
## 兩份會漂移，而漂移的那一份剛好就是玩家讀到的那一份。
func build_codex_panel() -> void:
	# 角色簡介刻意半透明：它浮在地圖上，要讓人看得見底下是什麼（使用者指定）。
	var box := UiKit.panel(0.88)
	box.visible = false
	codex_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 不設寬度的話它會長到最長那一行那麼寬（熔爐那一行 850px），
	#   從 x=124 一路蓋掉 x=870 的能量面板——兩個浮層同時開就疊在一起。
	codex_label.custom_minimum_size.x = 640.0
	codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(codex_label)
	battle.add_child(box)
	codex_panel = box


func on_codex_show(type: String, from: Button) -> void:
	if not codex_on or Hooks.naked:
		return
	codex_label.text = "\n".join(Readout.codex_lines(type))
	codex_panel.visible = true
	# 貼著那顆鈕的右側浮出來，垂直對齊它——視線不必離開來源。
	codex_panel.position = Vector2(124.0, clampf(from.global_position.y - 8.0, 56.0, 470.0))


func on_codex_hide() -> void:
	codex_panel.visible = false

