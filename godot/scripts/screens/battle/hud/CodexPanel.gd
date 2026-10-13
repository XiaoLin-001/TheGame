extends Node
## 角色簡介浮層（圖鑑）：滑鼠停在建造鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
## 半透明是刻意的——它浮在地圖上，要讓人看得見底下是什麼（使用者指定）。

const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null


var codex_button: Button = null

var codex_panel: Control = null

var codex_label: Label = null

var codex_on: bool = true


## ★ 角色簡介浮層（使用者要求）。滑鼠停在左欄的建造鈕上就浮出來、移開就收，
## 底欄「圖鑑」可整個關掉。**半透明**：它蓋在地圖上，要讓人看得見底下是什麼。
##
## 內容一律**從 `data/NodeDefs.gd` 現算**，不另外寫一份文案表——
## 兩份會漂移，而漂移的那一份剛好就是玩家讀到的那一份。
## 底欄的抽屜開關。
func make_toggle() -> Button:
	codex_button = Button.new()
	codex_button.text = "圖鑑"
	codex_button.toggle_mode = true
	codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	codex_button.toggled.connect(func(on: bool) -> void: codex_on = on)
	return codex_button


func build_panel() -> void:
	# 角色簡介刻意半透明：它浮在地圖上，要讓人看得見底下是什麼（使用者指定）。
	var box := UiKit.panel(0.88)
	box.visible = false
	codex_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 不設寬度的話它會長到最長那一行那麼寬（熔爐那一行 850px），
	#   從 x=124 一路蓋掉 x=870 的能量面板——兩個浮層同時開就疊在一起。
	codex_label.custom_minimum_size.x = 640.0
	codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(codex_label)
	scr.add_child(box)
	codex_panel = box


func on_codex_show(type: String, from: Button) -> void:
	if not codex_on or Hooks.naked:
		return
	codex_label.text = "\n".join(_codex_lines(type))
	codex_panel.visible = true
	# 貼著那顆鈕的右側浮出來，垂直對齊它——視線不必離開來源。
	codex_panel.position = Vector2(124.0, clampf(from.global_position.y - 8.0, 56.0, 470.0))


func on_codex_hide() -> void:
	codex_panel.visible = false


## 一種節點的簡介。**先講它在取捨裡的位置，再列數字**——
## 一串沒有脈絡的數值幫不了正在決定「這一分鐘要蓋什麼」的人。
## 升級階梯的一個台階講成人話（B3.8）。**四個詞的唯一翻譯處**——
## 圖鑑與檢視面板讀同一支，兩邊各寫一份的話遲早有一邊沒跟上資料表。
func step_text(step: String) -> String:
	return {
		Build.STEP_POWER: "出力 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_RANGE: "射程 +1 格",
		Build.STEP_ROF: "射速 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_SPLASH: "濺射 +1 格",
	}.get(step, step)


func _codex_lines(type: String) -> Array[String]:
	var def := NodeDefs.of(type)
	var out: Array[String] = [BuildController.price_text(type)]
	out.append({
		"extractor": "礦砂的源頭。只能蓋在礦點上，而且要接到核心才入帳。",
		"generator": "把礦砂燒成能量。全遊戲唯一的電力來源，每台吃 4 礦砂/秒。",
		"smelter": "合金的唯一來源。吃礦砂也吃電，而且待機也吃 10 能量/秒。合金要接到核心才入帳。",
		"breaker": "濺射：打中最前那一隻，順便打它周圍 2.5 格內的每一隻。單打的傷害比錨低。",
		"relay": "轉彎與分岔用。導管只能走直線與 45°，所有拐角都靠它。",
		"silo": "準備期存電、波次期放電。充放電速率受它自己那條導管的 cap 限制。",
		"anchor": "最便宜的塔，物理傷害。護甲是減法，而甲殼有護甲 8。",
		"prism": "最貴的塔，能量傷害穿透一直線。與路徑同一列時可一次貫穿整段。",
		"knell": "不開火。減速 40% ＋ 破甲 25%，多座不疊加，取最強的一座。",
		# `Label` 不解析 Markdown——`**任何**` 會原樣印出兩排星號（B0.7.1／B0.7.3
		# 各犯過一次，這裡是第三處，B1.1 一併掃掉）。強調一律用「」。
		"reclaimer": "射程內「任何」敵人死亡就回收能量，不限自己擊殺。",
		"longcall": "射程 12，一座蓋掉大圖的一個象限。每瓦傷害中等。",
		"frostreef": "不開火。減速 65%（潮鳴 40%），「沒有」破甲，射程 3，電費是潮鳴的 1.8 倍。減速與破甲各自取最大。",
		"ballast": "血量 90（其餘塔 60），每瓦傷害全場最高。造價 240 礦砂 ＋ 100 合金。",
	}.get(type, ""))
	if def.has("ore_out"):
		out.append("產出　＋%.0f 礦砂/秒" % float(def["ore_out"]))
	if def.has("ore_in"):
		out.append("燃料　−%.0f 礦砂/秒" % float(def["ore_in"]))
	if def.has("power_out"):
		out.append("產出　＋%.0f 能量/秒" % float(def["power_out"]))
	if def.has("alloy_out"):
		out.append("產出　＋%.0f 合金/秒" % float(def["alloy_out"]))
	if def.has("power_in"):
		out.append("耗能　−%.0f 能量/秒（一直吃）" % float(def["power_in"]))
	if def.has("capacity"):
		out.append("容量　%.0f 能量" % float(def["capacity"]))
	if def.has("engage_power"):
		out.append("耗能　交戰時 −%.0f 能量/秒（待機 0）" % float(def["engage_power"]))
	if def.has("range"):
		out.append("射程　%.0f 格　射速 %.1f 發/秒　傷害 %.0f（%s）%s" % [
			float(def["range"]), float(def.get("rof", 0.0)), float(def.get("dmg", 0.0)),
			"能量" if String(def.get("dmg_type", "physical")) == "energy" else "物理",
			"　濺射 %.1f 格" % float(def["splash"]) if def.has("splash") else ""
		])
	out.append("生命　%.0f　※ 退開敵人路徑 2 格就打不到" % NodeDefs.hp(type))
	# ★ B3.8：把三級的階梯寫在**花錢之前**看得到的地方（§4.3）。
	#   「每一級加的不是同一樣東西」如果只有升級當下才看得到，玩家在擺位時
	#   就沒有辦法把它算進去——而擺位是本作的主要決策。
	var ladder := PackedStringArray()
	for lv in Build.NODE_MAX_LEVEL:
		ladder.append("%d 級 %s" % [lv + 1, step_text(Build.next_step(type, lv))])
	out.append("升級　" + "　→　".join(ladder))
	return out
