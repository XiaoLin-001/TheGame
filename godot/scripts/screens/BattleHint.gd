class_name BattleHint
extends RefCounted
## 提示列：下一步與當下動作的細節。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BuildController := preload("res://scripts/game/BuildController.gd")
const HintRules := preload("res://scripts/game/HintRules.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

var label: Label = null

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func refresh_hint() -> void:
	# ⚠ **UI 還沒建完就可能被呼叫**（B3.7.1）：`_build_ui()` 裡設建造鈕的
	#   `button_pressed = true` 會當場送出 `toggled`，而那時提示列還沒建出來。
	#   少了這道守衛的症狀不是報錯，是 `_build_ui()` **從那一行起整支中止**
	#   ——半個畫面沒建出來，而畫面自己不會抱怨（RG-164 的形狀）。
	if label == null:
		return
	if Hooks.naked:
		label.visible = false
		return
	# ★ 兩行：**上行永遠是「下一步」，下行才是當下這個動作的細節。**
	# B0.7 原本讓預覽「取代」下一步，於是玩家把滑鼠移到地圖上——正是最需要
	# 指引的那一刻——指引就消失了。使用者實玩後的第一句話是「你沒教我怎麼操作」。
	var parts: Array[String] = []
	# 拖曳中就只講這一條線連不連得成——這時玩家問的問題只有那一個。
	if battle.drag_from.x >= 0:
		label.text = "▶ %s\n%s" % [
			"放開在另一個節點上就拉出一條導管；放開在空地／原地則取消。",
			HintRules.connect_hint(battle.s, battle.drag_from, battle.hover) if battle.cam.in_map(battle.hover) else "",
		]
		return
	match battle.mode:
		BattleScreen.Mode.BUILD:
			# ★ 游標壓在導管上時，落點提示是**錯的**——點下去不會蓋東西（B3.7）。
			#   順便把逃生門講出來：想在這一格蓋，就避開線，往格子邊緣點。
			if battle.bp_index < 0 and battle.s.conduit_near(battle.hover_p, BattleInput.WIRE_PICK) >= 0:
				parts.append("這條導管：左鍵點一下就檢視它，面板上可以加粗或拆除。想在這一格蓋東西，避開線往格子邊緣點。")
			elif battle.build_type == "" and battle.bp_index < 0:
				# ★ B3.7.1：手上什麼都沒拿。**要講得出「現在能做什麼」**，
				#   不然這個狀態讀起來會像「怎麼點都沒反應」。
				parts.append("目前沒有拿著任何節點。左鍵點一座建築或一條導管＝檢視它，面板上就能升級、加粗或拆除。要蓋東西就在左欄點一種。")
			elif battle.cam.in_map(battle.hover):
				parts.append_array(BuildController.preview_place(battle.s, battle.build_type, battle.hover)["lines"])
			else:
				parts.append("建造 %s：左鍵點一格放下；從既有節點按住拖到另一個節點＝拉導管。" % NodeDefs.label(battle.build_type))
	if battle.message != "":
		parts.append(battle.message)
	label.text = "▶ %s\n%s" % [HintRules.next_step(battle.s, battle.buildable()), "　".join(parts)]

