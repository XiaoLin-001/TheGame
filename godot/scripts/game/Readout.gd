extends RefCounted
## 狀態 → 玩家讀得到的數字與句子（read model）。B3.14 自 `screens/Battle*.gd` 抽出。
##
## **純函式、零副作用、不引用 autoload、不引用任何 `Control`／`Palette`。**
## 面板（2D 或日後的 3D HUD）只負責擺版面與上色，「這一格要寫什麼」只有這裡一份：
##   · 頂欄的階段字串（`phase_parts`）
##   · 能量收支面板的每一列（`energy_rows`）
##   · 檢視面板的內容與兩顆動詞鈕（`inspect_node`／`inspect_wire`）
##   · 圖鑑簡介（`codex_lines`）、升級台階（`step_text`）
##   · 導引用的問題格（`problem_cells`）
##
## 顏色以**語意**回傳（`"energy"`／`"warn"`／`"ok"`／`""`），由面板翻成 `Palette`
## ——這一層不知道畫面長什麼樣，才搬得進 3D。

const Build := preload("res://scripts/sim/Build.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")

## 「餵不飽」最多列幾座，其餘收成一行「…還有 N 座」。
const SHORT_ROWS := 3




## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
##
## ★ 回傳 `[主, 附屬]` 兩段（B2.4.4）：主的是「我還有多少時間／現在第幾波」
## （`text.lg`），附屬的是波號、快進倍率、殘敵（`text.sm`）。
## **原本是一整串塞在同一個 22px 的標籤裡**，量到那一格 299px、把整條頂欄
## 撐出畫面 —— 而它裡面本來就有兩階資訊。
static func phase_parts(s: RefCounted) -> Array:
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


## 「問題」不新發明判定，就是既有的兩件事，依嚴重度排序：
##   ① 正在被 walk-by 啃的節點（`_threat`，和主畫面的四角括號同一份判定）
##   ② `缺料`／`滿溢`（`node_state`，和三態徽章同一份判定）
## 排序決定 `ARROW_MAX` 砍掉的是哪幾個——被啃的永遠留著。
static func problem_cells(s: RefCounted, threat: Dictionary) -> Array[Vector2i]:
	var hurt: Array[Vector2i] = []
	var stuck: Array[Vector2i] = []
	var state: Dictionary = s.rates["node_state"]
	for n: Dictionary in s.nodes:
		var c: Vector2i = n["cell"]
		if threat.has(c):
			hurt.append(c)
		elif int(state.get(int(n["id"]), SessionState.NORMAL)) != SessionState.NORMAL:
			stuck.append(c)
	hurt.append_array(stuck)
	return hurt


## 本 tick 每條導管的**能量**淨流（沿 a→b 為正）。
static func energy_net(s: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		out[c["id"]] = v.y
	return out


## 會發電的那些格（發電機、放電中的儲槽、回收者的緩衝）。
static func power_sources(s: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for n: Dictionary in s.nodes:
		var d := NodeDefs.of(String(n["type"]))
		if float(d.get("power_out", 0.0)) > 0.0 or String(n["type"]) in ["silo", "reclaimer"]:
			out[n["cell"]] = true
	return out


## 一種節點的簡介。**先講它在取捨裡的位置，再列數字**——
## 一串沒有脈絡的數值幫不了正在決定「這一分鐘要蓋什麼」的人。
## 升級階梯的一個台階講成人話（B3.8）。**四個詞的唯一翻譯處**——
## 圖鑑與檢視面板讀同一支，兩邊各寫一份的話遲早有一邊沒跟上資料表。
static func step_text(step: String) -> String:
	return {
		Build.STEP_POWER: "出力 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_RANGE: "射程 +1 格",
		Build.STEP_ROF: "射速 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_SPLASH: "濺射 +1 格",
	}.get(step, step)


static func codex_lines(type: String) -> Array[String]:
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


## 回傳固定順序的列：`[[key, 文字, 有沒有在作用, 語意色], ...]`。**沒作用的列照樣回傳**
## （面板把它變暗而不是隱藏——版面位置固定本身就是可讀性，B0.7.4）。
## 語意色：`"energy"`＝琥珀（能量）、`"warn"`＝橙（危險／挨餓）、`"ok"`＝綠、`""`＝次要文字色。
## `engaged` 是 `Combat.engaged()` 的結果（`{節點 id: 是否交戰}`）。
static func energy_rows(s: RefCounted, engaged: Dictionary) -> Array:
	var rows: Array = []
	var r: Dictionary = s.rates
	var gen := 0.0
	var reclaim := 0.0
	var tower := 0.0
	# 熔爐的耗能**不能併進任何一列既有的**：它既不是交戰耗能（待機也吃），
	# 也不是儲槽充能。B1.1 之前 `silo_in = demand − tower` 會把熔爐那 10/秒
	# 記到儲槽頭上——面板從此開始說謊。
	var smelt := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		gen += float(def.get("power_out", 0.0)) * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		if def.has("reclaim"):
			reclaim += float(n["buffer"])
		smelt += float(def.get("power_in", 0.0))
		if engaged.get(int(n["id"]), false):
			tower += float(def.get("engage_power", 0.0))
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var silo_out := maxf(0.0, supply - gen)
	var silo_in := maxf(0.0, demand - tower - smelt)
	var net := supply - demand

	_row(rows, "gen", "＋ 發電機 ×%d　%+.0f" % [s.count_of("generator"), gen],
		gen > 0.05, "energy")
	_row(rows, "silo_out", "＋ 儲槽放電　%+.0f" % silo_out, silo_out > 0.05, "energy")
	_row(rows, "reclaim", "＋ 回收者存量　%.0f（擊殺換來的，限速注入）" % reclaim,
		reclaim > 0.05, "energy")
	_row(rows, "sep1", "─────────────────", false)
	_row(rows, "tower", "− 塔（交戰 %d 座）　%.0f" % [int(r["engaged"]), tower], tower > 0.05)
	_row(rows, "smelt", "− 熔爐 ×%d　%.0f（待機也吃）" % [s.count_of("smelter"), smelt],
		smelt > 0.05)
	_row(rows, "silo_in", "− 儲槽充能　%.0f（受自己那條線限速）" % silo_in, silo_in > 0.05)
	# ★ 儲槽**存量**（B2.4.4）。它原本掛在頂欄，而頂欄的三階層次容不下 11 個
	#   數字（§2 反模式：每畫面最多 4 個主要數字）。搬到這裡而不是刪掉：
	#   這一格是「充放電」那兩列的分母，放在它們旁邊比放在頂欄更講得通。
	#   ★ **每一顆儲槽自己身上還有一圈琥珀弧**，所以「哪一顆滿了」在地圖上讀得到，
	#     頂欄少的只是那個總和數字。
	_row(rows, "silo_store", "　　儲槽存量　%.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]],
		float(r["silo_capacity"]) > 0.05, "energy")
	_row(rows, "sep2", "─────────────────", false)

	# ★ 「誰餵不飽」（使用者要求）。淨值只說「差多少」，不說「誰在挨餓」——
	#   而玩家能採取的動作（拉優先權、加粗那條線、多蓋一台發電機）取決於後者。
	#   名單直接取三態徽章的 `STARVED`，與地圖上的橙色倒三角是同一份判定。
	var short_list: Array[String] = []
	var states: Dictionary = r["node_state"]
	for n: Dictionary in s.nodes:
		# ★ `is_starved()` 而不是 `== STARVED`（B2.4.8）：缺料分成礦／電兩態之後，
		#   寫死等號的地方會安靜地漏掉一半的節點——而「安靜地漏掉」正是這一整批
		#   在修的東西。
		if not SessionState.is_starved(int(states.get(int(n["id"]), 0))):
			continue
		short_list.append("%s%s %.0f%%" % [
			NodeDefs.label(String(n["type"])), n["cell"],
			100.0 * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		])

	var ok_all := short_list.is_empty()
	_row(rows, "net", "淨值　%+.0f/秒　%s" % [net, "餵得飽" if ok_all else "有東西在挨餓"], true,
		"ok" if ok_all else "warn")
	for i in SHORT_ROWS:
		var key := "short%d" % i
		if ok_all:
			_row(rows, key, "　全部餵得飽" if i == 0 else "", false)
		elif i == SHORT_ROWS - 1 and short_list.size() > SHORT_ROWS:
			_row(rows, key, "　…還有 %d 座" % (short_list.size() - SHORT_ROWS + 1), true,
				"warn")
		elif i < short_list.size():
			_row(rows, key, "　餵不飽：" + short_list[i] if i == 0 else "　　　　　" + short_list[i],
				true, "warn")
		else:
			_row(rows, key, "", false)

	_row(rows, "tip", "加電：多蓋發電機（每台吃 4 礦砂/秒）", false)
	_row(rows, "tip2", "省電：塔少一點，或用「優先權」決定誰先餓", false)
	return rows


static func _row(rows: Array, key: String, text: String, live: bool, tone: String = "") -> void:
	rows.append([key, text, live, tone])


## 被選取那一座的**當下數據**（B3.6）。每幀重算——它講的是這個 tick。
##
## 三件事，照玩家問的順序：**這是什麼 → 它現在吃多少電 → 電從哪來。**
## 前兩件是它自己的欄位，第三件要逆著本 tick 的實際流向走（`FlowNetwork.upstream_power()`）。
##
## 回傳 `{lines, up, del, up_on}`：面板的內容行、兩顆動詞鈕的文字（空字串＝那顆鈕收起來）、
## 升級鈕按不按得動。選的那格沒有東西時回傳 `{}`。
static func inspect_node(s: RefCounted, selected: Vector2i, engaged: Dictionary) -> Dictionary:
	var n: Dictionary = s.node_at(selected)
	if n.is_empty():
		return {}
	var type := String(n["type"])
	var def := NodeDefs.of(type)
	var lvl := int(n.get("level", 0))
	var scale := Build.node_scale(lvl)
	var lines: Array[String] = []
	lines.append("%s%s" % [NodeDefs.label(type), "　%d 級" % lvl if lvl > 0 else ""])
	lines.append("生命　%d / %d" % [int(n["hp"]), int(NodeDefs.hp(type))])

	# ── 它自己的數據（升級之後要顯示**升過的值**，不是表上的原值）──
	# ★ B3.8：升的是哪一項各問各的（`10_GDD.md` §4.3）。這裡**不能用 `scale`**
	#   ——那是耗能倍率；一座第 2 級加射速的錨，傷害還停在 1 級的值。
	var eff := Build.effect_scale(type, lvl)
	var rng := Build.node_range(type, lvl)
	if rng > 0.0:
		lines.append("射程　%.0f 格" % rng)
	if float(def.get("dmg", 0.0)) > 0.0:
		lines.append("傷害　%.0f × %.1f 發/秒" % [
			float(def["dmg"]) * eff * float(s.mods["damage_mult"]),
			float(def.get("rof", 0.0)) * Build.rof_scale(type, lvl),
		])
	if float(def.get("slow", 0.0)) > 0.0:
		# 光環塔的**全部效果**都在這一行。B3.5 起它一直沒有被級數乘過，而面板
		# 也從來沒有印出來——使用者實玩才發現「潮鳴跟霜礁升級都沒用」（B3.8）。
		lines.append("減速　%d%%%s" % [
			int(round(minf(float(def["slow"]) * eff, Combat.SLOW_MAX) * 100.0)),
			"　破甲 %d%%" % int(round(float(def["armor_break"]) * eff * 100.0))
				if float(def.get("armor_break", 0.0)) > 0.0 else "",
		])
	if Build.splash_radius(type, lvl) > 0.0:
		lines.append("濺射　%.1f 格" % Build.splash_radius(type, lvl))
	if float(def.get("reclaim", 0.0)) > 0.0:
		lines.append("回收　射程內任何死亡的 %d%% 換能量" % int(round(
			float(def["reclaim"]) * eff * 100.0
		)))
	if float(def.get("ore_out", 0.0)) > 0.0:
		lines.append("產出　%.1f 礦砂/秒" % (float(def["ore_out"]) * eff
			* float(s.mods["produce_mult"])))
	if float(def.get("power_out", 0.0)) > 0.0:
		lines.append("發電　%.0f 能量/秒" % (float(def["power_out"]) * eff
			* float(s.mods["produce_mult"])))

	# ── 耗能：**帳面**與**當下**分開講 ──
	# 帳面是「它交戰時會吃多少」，當下是「這個 tick 它真的拿到多少」。
	# 只講一個的話，玩家看不出「它在挨餓」——而那正是他點開這座塔的原因。
	var engage := float(def.get("engage_power", 0.0)) * scale * float(s.mods["engage_mult"])
	var idle := float(def.get("power_in", 0.0)) * scale
	if engage > 0.0 or idle > 0.0:
		# ⚠ **預設值不能是 1.0**。沒接進電網的節點根本不在解算器的表上，
		#   `.get(id, 1.0)` 會把「查無此人」讀成「餵得飽飽的」——
		#   截圖當場抓到面板自相矛盾：上一行寫「餵得 100%」，下一行寫「供電 沒有」。
		#   用 −1 當哨兵，把「沒在表上」和「在表上而且滿足率是 1」分開。
		var sat_raw := float((s.rates["satisfaction"] as Dictionary).get(int(n["id"]), -1.0))
		var wired: bool = sat_raw >= 0.0
		var sat: float = sat_raw if wired else 0.0
		# `.get()` 不是 `.has()`：`_engaged` 是 {id: bool}，沒交戰的塔**鍵也在**，
		# 值才是 false（第 1008 行那條既有斷言用的就是 get）。
		var busy: bool = engage > 0.0 and bool(engaged.get(int(n["id"]), false))
		var draw := (engage if busy else 0.0) + idle
		if engage > 0.0:
			lines.append("交戰耗能　%.1f 能量/秒%s" % [engage, "" if busy else "（待機 0）"])
		if idle > 0.0:
			lines.append("待機耗能　%.1f 能量/秒" % idle)
		if not wired:
			# 和提示列講同一句話——同一件事在兩個地方要有同一個說法。
			lines.append("此刻　沒接進電網，交戰時一發都打不出來")
		else:
			lines.append("此刻　%.1f 能量/秒　餵得 %d%%" % [draw * sat, int(round(sat * 100.0))])

	# ── ★ 電從哪來 ──
	var sources: Dictionary = power_sources(s)
	var chain := FlowNetwork.upstream_power(s.conduits, energy_net(s), selected, sources)
	var feeders: Dictionary = chain["sources"]
	if engage > 0.0 or idle > 0.0:
		# ⚠ 「沒有外部來源」和「在挨餓」**不是同一件事**。回收者靠自己的回收緩衝、
		#   儲槽靠自己的存量，兩者都會出現「一條線都沒有在餵它，而它餵得飽飽的」。
		#   第一版一律寫「沒有——這一刻沒有任何電流進來」，於是面板上一行寫
		#   「餵得 100%」、下一行寫「沒有供電」，讀起來像壞掉了（截圖當場看到）。
		var self_fed: bool = String(n["type"]) in ["reclaimer", "silo"]
		var supply_text := "%d 座（已在地圖上標出）" % feeders.size()
		if feeders.is_empty():
			supply_text = "沒有外部來源，這一刻靠自己的存量" if self_fed 				else "這一刻沒有電流進來"
		lines.append("供電　%s" % supply_text)

	# ── ★ 兩顆動詞鈕（B3.7）──
	# **核心兩顆都關**：它升不得也拆不得（`upgrade_node()`／`demolish()` 都擋著）。
	# 鈕在那裡而按不動，等於邀請玩家去按一個保證失敗的東西。

	# ── ★ 兩顆動詞鈕（B3.7）──
	# **核心兩顆都關**：它升不得也拆不得（`upgrade_node()`／`demolish()` 都擋著）。
	# 鈕在那裡而按不動，等於邀請玩家去按一個保證失敗的東西。
	var up := ""
	var del := ""
	var up_on := true
	if type != "core":
		# ★ B3.8：鈕上寫**這一級買到的是什麼**。三級各不相同，而玩家在按下去
		#   之前必須知道自己買的是射程還是射速——否則「多元化」對他等於隨機。
		up = "已滿級" if lvl >= Build.NODE_MAX_LEVEL else "升級　%s　%d 礦砂" % [
			step_text(Build.next_step(type, lvl)),
			Build.node_upgrade_cost(NodeDefs.cost(type), lvl),
		]
		del = "拆除　退 %d 礦砂" % BuildController.node_refund(type).x
		up_on = lvl < Build.NODE_MAX_LEVEL
	return {"lines": lines, "up": up, "del": del, "up_on": up_on}


## ★ 被選取那條導管的當下數據（B3.7）。
##
## 玩家點一條線要問的是同一組問題，只是主詞換了：**它多粗 → 這一刻擠不擠 →
## 加粗要多少錢**。「擠不擠」是這一批真正要答的——導管滿載在圖上是變色與線寬，
## 那是給掃視用的；點下去要拿得到數字。
## 回傳格式同 `inspect_node`。`wi` 是 `s.conduits` 的索引。
static func inspect_wire(s: RefCounted, wi: int) -> Dictionary:
	var c: Dictionary = s.conduits[wi]
	var lvl := int(c["level"])
	var cap := Build.conduit_cap(lvl, float(s.mods["cap_bonus"]))
	var flow := float((s.rates["conduit_flow"] as Dictionary).get(c["id"], 0.0))
	var lines: Array[String] = []
	lines.append("導管%s" % ("　%d 級" % lvl if lvl > 0 else ""))
	lines.append("生命　%d / 40" % int(c["hp"]))
	lines.append("長度　%d 格" % (Build.conduit_cost(c["a"], c["b"]) / Build.CONDUIT_COST_PER_CELL))
	# 「這一刻擠不擠」：滿載是這條線正在**卡住**它下游的每一個節點。
	lines.append("流量　%.1f / %.0f 每秒%s" % [
		flow, cap, "　已滿載" if flow >= cap - 0.05 else ""
	])
	if lvl < Build.CAP_MAX_LEVEL:
		lines.append("加粗後　%.0f 每秒" % Build.conduit_cap(lvl + 1, float(s.mods["cap_bonus"])))

	var up := "已滿級"
	if lvl < Build.CAP_MAX_LEVEL:
		var alloy := Build.upgrade_alloy(lvl)
		up = "加粗　%d 礦砂%s" % [
			Build.upgrade_cost(lvl), "" if alloy == 0 else " ＋ %d 合金" % alloy
		]
	var refund := BuildController.conduit_refund(c)
	return {
		"lines": lines, "up": up, "del": "拆除　退 %d 礦砂" % refund.x,
		"up_on": lvl < Build.CAP_MAX_LEVEL,
	}
