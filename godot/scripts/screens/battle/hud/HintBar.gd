extends Node
## 提示列（底欄右側兩行字）：上行永遠是「下一步」，下行是當下這個動作的細節。
##
## 每幀重算——它講的是**當前狀態**下的下一步，而狀態每 tick 都在變（B0.7：手不動的那幾秒，
## 提示列不可以在說謊）。

const Stage := preload("res://scripts/screens/battle/Stage.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 同伴模組（Stage）。
var stage: Stage = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組（互相引用，不能用型別標註）。
var buildbar: Node = null


var hint: Label = null


## 提示文字擺在底欄右邊 24px（§1.3 間距階的群間距，同底欄自己的三群）。
## 底欄是容器，它的寬度要到版面跑完才知道——所以走 `resized` 而不是算一次。
func place_hint(bar: Control) -> void:
	if hint == null or not is_instance_valid(bar):
		return
	hint.position.x = bar.position.x + bar.size.x + 24.0
	hint.size.x = maxf(120.0, float(scr.size.x) - hint.position.x - 8.0)


func refresh_hint() -> void:
	# ⚠ **UI 還沒建完就可能被呼叫**（B3.7.1）：`_build_ui()` 裡設建造鈕的
	#   `button_pressed = true` 會當場送出 `toggled`，而那時提示列還沒建出來。
	#   少了這道守衛的症狀不是報錯，是 `_build_ui()` **從那一行起整支中止**
	#   ——半個畫面沒建出來，而畫面自己不會抱怨（RG-164 的形狀）。
	if hint == null:
		return
	if Hooks.naked:
		hint.visible = false
		return
	# ★ 兩行：**上行永遠是「下一步」，下行才是當下這個動作的細節。**
	# B0.7 原本讓預覽「取代」下一步，於是玩家把滑鼠移到地圖上——正是最需要
	# 指引的那一刻——指引就消失了。使用者實玩後的第一句話是「你沒教我怎麼操作」。
	var parts: Array[String] = []
	# 拖曳中就只講這一條線連不連得成——這時玩家問的問題只有那一個。
	if scr.drag_from.x >= 0:
		hint.text = "▶ %s\n%s" % [
			"放開在另一個節點上就拉出一條導管；放開在空地／原地則取消。",
			_connect_hint() if stage.in_map(scr.hover) else "",
		]
		return
	match scr.mode:
		scr.Mode.BUILD:
			# ★ 游標壓在導管上時，落點提示是**錯的**——點下去不會蓋東西（B3.7）。
			#   順便把逃生門講出來：想在這一格蓋，就避開線，往格子邊緣點。
			if scr.bp_index < 0 and s.conduit_near(scr.hover_p, scr.WIRE_PICK) >= 0:
				parts.append("這條導管：左鍵點一下就檢視它，面板上可以加粗或拆除。想在這一格蓋東西，避開線往格子邊緣點。")
			elif scr.build_type == "" and scr.bp_index < 0:
				# ★ B3.7.1：手上什麼都沒拿。**要講得出「現在能做什麼」**，
				#   不然這個狀態讀起來會像「怎麼點都沒反應」。
				parts.append("目前沒有拿著任何節點。左鍵點一座建築或一條導管＝檢視它，面板上就能升級、加粗或拆除。要蓋東西就在左欄點一種。")
			elif stage.in_map(scr.hover):
				parts.append_array(BuildController.preview_place(s, scr.build_type, scr.hover)["lines"])
			else:
				parts.append("建造 %s：左鍵點一格放下；從既有節點按住拖到另一個節點＝拉導管。" % NodeDefs.label(scr.build_type))
	if scr.message != "":
		parts.append(scr.message)
	hint.text = "▶ %s\n%s" % [_next_step(), "　".join(parts)]


## ★ 下一步（`50_QA_PLAN.md` §4.4「新玩家開局後 15 秒內知道要做什麼嗎」）。
##
## 這**不是教學系統**，是一句讀當前狀態算出來的話——沒有進度旗標、沒有步驟機、
## 不持久化，玩家拆光重蓋它就跟著退回去。做成教學系統的話它會變成第二套要維護的
## 狀態，而且擋在玩家和遊戲之間；一行提示不會。
##
## 順序＝這張圖真正的依賴鏈：礦→入帳→電→塔→接電。
##
## **每一條都要講出「按哪裡、點哪裡」，不能只講目標。** 使用者實玩 B0.7 的第一句
## 回饋是「你沒教我要怎麼操作」——那時這些字串寫的是「先蓋一台採集器」，
## 而畫面上沒有任何地方說過「蓋」＝左欄選一種、再左鍵點地圖。
## 一句只說目標不說動作的提示，對已經會玩的人是提醒，對新玩家是零。
func _next_step() -> String:
	if s.count_of("extractor") == 0:
		return "左欄點「採集器」→ 左鍵點地圖上任一個青色空心圓（礦點）。這是所有東西的源頭。"
	if float(s.rates["ore_in"]) <= 0.0:
		return "礦砂要「送達核心」才入帳：從採集器按住左鍵，拖到下一個節點放開，一路接到右下角的核心。"
	if s.count_of("generator") == 0:
		return "有礦砂了（看頂欄 ▲/秒）。左欄點「發電機」蓋一台，再從採集器拖一條線給它：4 礦砂/秒 → 20 能量/秒。"
	if _towers() == 0:
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方。貼太近會被走過的敵人打壞。"
	if _unpowered_tower():
		return "那座塔還沒接進電網，交戰時一發都打不出：從那座塔按住拖到發電機那一側的節點。"
	# 合金是第三資源，但它排在「防線先站得住」之後才提——B0.7 的教訓是
	# 提示列一次只能給一件事做，塞第二條路線只會讓玩家兩件都不做。
	#
	# ★ **這一關沒解鎖熔爐就不准提它**（B1.2）：叫人去點一顆畫面上不存在的鈕，
	#   比不給提示更糟——玩家會以為是自己看漏了，然後花掉整個準備期在找。
	if buildbar.buildable().has("smelter") and s.count_of("smelter") == 0 and s.alloy <= 0.0:
		return "防線站住了。想加粗幹線到 2 級以上%s，都要合金：左欄點「熔爐」，它吃 8 礦砂/秒 ＋ 10 能量/秒，產 2 合金/秒。" % (
			"、或蓋「碎浪」" if buildbar.buildable().has("breaker") else ""
		)
	if s.count_of("smelter") > 0 and float(s.rates["alloy_in"]) <= 0.0:
		return "熔爐產的合金也要「送達核心」才入帳：從熔爐拖一條線出去，一路接到核心；同時它的礦砂與電也都要接得到。"
	if s.phase == "prep":
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開。倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
func _connect_hint() -> String:
	if s.node_at(scr.hover).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var cf: Vector2i = scr.drag_from
	var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, scr.hover, s.conduit_cells()
	)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = scr.hover - cf
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(cf, scr.hover)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		scr.label_at(cf), scr.label_at(scr.hover), cost, afford
	]


func _towers() -> int:
	var n := 0
	for node: Dictionary in s.nodes:
		if NodeDefs.of(String(node["type"])).get("tower", false):
			n += 1
	return n


## 有沒有塔完全沒接上任何導管？（接了但電不夠是另一回事，那由三態徽章講。）
func _unpowered_tower() -> bool:
	for node: Dictionary in s.nodes:
		if not NodeDefs.of(String(node["type"])).get("tower", false):
			continue
		var wired := false
		for c: Dictionary in s.conduits:
			if c["a"] == node["cell"] or c["b"] == node["cell"]:
				wired = true
				break
		if not wired:
			return true
	return false
