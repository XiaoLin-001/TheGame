extends SceneTree
## 流量網路解算器（30_TECH_DESIGN.md §2.5、50_QA_PLAN.md §2）。
##
## 這支測試鎖住的是**設計承諾**，不只是程式碼行為：
##   RG-18 無全域資源池、RG-19 儲槽充放電受自身導管 cap 約束、
##   「供不應求按比例降速不停機」、「優先權讀節點類型」、「採集器無輸入需求」。
## 任何一條紅字被改掉，這裡要先變紅。
##
## 跑法：<godot> --headless --path godot --script res://tests/flow_test.gd

const T := preload("res://tests/_assert.gd")
const FN := preload("res://scripts/sim/FlowNetwork.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("flow_test")
	_single_line_saturation(t)
	_capacity_split(t)
	_priority_by_type(t)
	_cycle_converges(t)
	_starvation_scales(t)
	_silo_rate_limited_by_cap(t)
	_no_global_pool(t)
	_harvester_never_deadlocks(t)
	_three_resource_networks(t)
	_two_lines_feed_one_consumer(t)
	quit(t.report())


## ★ 「兩條線一起餵一個大消費者」（B1.2、`10_GDD.md` §7.9 第 2 關的正解）。
##
## 稜鏡交戰吃 20 能量/秒而導管基礎 cap 是 10——**一條線本來就餵不飽它**，
## 正解是繞成菱形讓兩條線同時進。這件事以前是壞的：一條實體導管的兩個方向
## 各自有一份完整的 cap，於是中繼會把一半的量沿著來路推回去（它「看到」經由
## 另一條分支還有需求），三次迭代彈完只送到 25%。
##
## 修法是 `FlowNetwork._residual()`：**管子是一根，容量就是一份。**
## 這裡直接鎖住那個數字——25% 那個版本會讓這一條變紅。
func _two_lines_feed_one_consumer(t: T) -> void:
	var nodes := [
		{"id": 1, "type": "generator", "supply": 2.0},
		{"id": 2, "type": "relay"},
		{"id": 3, "type": "relay"},
		{"id": 4, "type": "prism", "demand": 2.0},
	]
	var edges: Array = []
	for pair: Array in [[1, 2], [1, 3], [2, 4], [3, 4]]:
		edges.append({"from": pair[0], "to": pair[1], "cap": 1.0})
		edges.append({"from": pair[1], "to": pair[0], "cap": 1.0})
	var res := FN.solve(nodes, edges, {"generator": 4, "prism": 3, "relay": 1})
	t.near(
		float((res["satisfaction"] as Dictionary)[4]), 1.0,
		"★ 兩條 cap 10 的線並聯 → 20 能量/秒的稜鏡餵得飽"
	)
	# 反向邊上不該有任何流量：來回彈是上面那個缺陷的指紋。
	var back := float(res["flow"][1]) + float(res["flow"][3])
	t.near(back, 0.0, "★ 沒有任何量沿著來路推回去（同一根管子共用一份 cap）")


# ── ★ 第三資源：合金網（B1.1、GDD §3.1／§7.3）─────────────────────────
#
# 這一段是**端到端**的（`SessionState` ＋ `BattleController`），不是解算器層：
# 「三種資源網互不干擾」這句話的實作不在 `FlowNetwork`（它一次只解一種），
# 而在解算順序與滿足率的串接。要驗的是那個串接。
#
# 用一張**沒有敵人路徑的極簡測試圖**：`Maps.path_of()` 只認得 "shoal"，
# 其他 id 一律回空路徑 → 沒有敵人、沒有跨越點限制，剩下的就只有物流本身。

func _three_resource_networks(t: T) -> void:
	var s := _fed_smelter()
	for _i in 20:
		BattleController.step(s)

	# ① 熔爐吃飽 → 產得出合金，而且**要送達核心才入帳**（§7.3 與礦砂同規則）。
	t.near(_sat(s, Vector2i(2, 6)), 1.0, "★ 熔爐礦砂與電都餵飽 → 滿足率 1.0")
	t.near(float(s.rates["alloy_in"]), 2.0, "★ 合金 2/秒送達核心（熔爐標稱值）")
	t.ok(float(s.alloy) > 0.0, "★ 合金真的進了帳上（核心＝合金銀行）")
	t.near(float(s.alloy), float(s.alloy_total), "起始合金 0：帳上 ＝ 累計送達")

	# ② 三種資源各自獨立解算：合金網跑起來不會動到礦砂網的結論。
	#    發電機 4 ＋ 熔爐 8 ＝ 12 ＝ 兩台採集器的全部產量 → 核心的礦砂入帳恰好 0
	#    （§7.3「核心只收剩下的」）。合金入帳同時 > 0——兩張網互不干擾。
	t.near(float(s.rates["ore_in"]), 0.0, "★ 礦砂全被發電機與熔爐吃掉 → 礦砂入帳 0")
	t.ok(float(s.rates["alloy_in"]) > 0.0, "★ 而合金照樣入帳：兩種資源各解各的")

	# ③ 缺電 → 合金按比例降速，**不停機**（§3.1）。
	#    拆掉供電那條線之後，熔爐的能量滿足率掉到 0，於是產出乘 0。
	var dark := _fed_smelter()
	for _i in 20:
		BattleController.step(dark)
	var before := float(dark.rates["alloy_in"])
	# 拆的是**發電機本身**，不是那條電線——導管不分資源（§7.2），拆掉
	# (6,2)→(2,6) 之後電照樣繞道 (6,2)→(2,2)→(2,6) 走礦砂線過去。
	# 這件事本身就是這張網的設計：一條管子什麼都送。
	BuildController.demolish(dark, Vector2i(6, 2))
	for _i in 20:
		BattleController.step(dark)
	t.ok(before > 1.9, "前置：斷線前合金確實在流")
	t.near(float(dark.rates["alloy_in"]), 0.0, "★ 沒電 → 合金產出歸零（取兩個滿足率的較低者）")
	t.eq(
		_state(dark, Vector2i(2, 6)), SessionState.STARVED,
		"★ 斷電的熔爐掛「缺料」——它宣告過需求，這是玩家該去看的那一格"
	)

	# ④ 產得出來但送不掉 → `滿溢`，而且帳上一毛都不會多。
	var orphan := _fed_smelter()
	BuildController.demolish(orphan, Vector2i(4, 6))  # 出海口 (2,6)→(6,6) 的中段
	for _i in 20:
		BattleController.step(orphan)
	t.near(float(orphan.alloy), 0.0, "★ 熔爐沒接到核心 → 合金一塊都不入帳")
	t.eq(
		_state(orphan, Vector2i(2, 6)), SessionState.OVERFLOW,
		"★ 而它掛「滿溢」：位置資訊就是「這條線斷在哪」"
	)


## 沙盤「靜水」上的三路熔爐（`data/Maps.gd` 的 `SANDBOX_DEMO`）。
## **測試與截圖共用同一份佈局**——`TL_PANEL=sandbox` 拍的就是這個局面，
## 所以圖上看到的珠子和這裡斷言的數字保證是同一件事。
func _fed_smelter() -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SANDBOX)
	BuildController.apply_ops(s, Maps.SANDBOX_DEMO)
	return s


func _sat(s: RefCounted, cell: Vector2i) -> float:
	return float((s.rates["satisfaction"] as Dictionary).get(int(s.node_at(cell)["id"]), 1.0))


func _state(s: RefCounted, cell: Vector2i) -> int:
	return int((s.rates["node_state"] as Dictionary).get(int(s.node_at(cell)["id"]), -1))


# ── 測項 ──────────────────────────────────────────────────────────────

## 單線滿載：發電機輸出 20 塞不進 cap 10 的導管（GDD §7.2 的第一課）。
func _single_line_saturation(t: T) -> void:
	var r := FN.solve(
		[_n(1, "generator", 20.0), _n(2, "anchor", 0.0, 20.0)],
		[_e(1, 2, 10.0)],
		{}
	)
	t.near(r["flow"][0], 10.0, "單線滿載：flow 被 cap 10 削平")
	t.near(r["received"][2], 10.0, "單線滿載：下游只收得到 10")
	t.near(r["satisfaction"][2], 0.5, "單線滿載：satisfaction = 10/20")
	t.near(r["supply_total"], 20.0, "單線滿載：頂欄供給仍是 20（供給不等於送達）")
	t.near(r["demand_total"], 20.0, "單線滿載：頂欄需求 20")


## 容量削減：瓶頸後方的兩個同類型消費者等分殘量。
func _capacity_split(t: T) -> void:
	var r := FN.solve(
		[
			_n(1, "generator", 20.0), _n(2, "relay"),
			_n(3, "anchor", 0.0, 10.0), _n(4, "anchor", 0.0, 10.0),
		],
		[_e(1, 2, 10.0), _e(2, 3, 20.0), _e(2, 4, 20.0)],
		{"anchor": 1}
	)
	t.near(r["flow"][0], 10.0, "容量削減：幹線滿載 10")
	t.near(r["received"][3], 5.0, "容量削減：同優先權等分（3）")
	t.near(r["received"][4], 5.0, "容量削減：同優先權等分（4）")
	t.near(r["satisfaction"][3], 0.5, "容量削減：satisfaction 同步降到 0.5")


## 三方競爭：priority 讀的是**節點類型**的值，不是節點自己的欄位（GDD §3.1）。
func _priority_by_type(t: T) -> void:
	var loud: Dictionary = _n(5, "prism", 0.0, 10.0)
	loud["priority"] = 99  # 節點自己喊的優先權必須被無視
	var r := FN.solve(
		[
			_n(1, "generator", 12.0), _n(2, "relay"),
			_n(3, "anchor", 0.0, 10.0), _n(4, "smelter", 0.0, 10.0), loud,
		],
		[_e(1, 2, 100.0), _e(2, 3, 100.0), _e(2, 4, 100.0), _e(2, 5, 100.0)],
		{"anchor": 3, "smelter": 2, "prism": 1}
	)
	t.near(r["received"][3], 6.0, "三方競爭：anchor(3) 拿 12×3/6")
	t.near(r["received"][4], 4.0, "三方競爭：smelter(2) 拿 12×2/6")
	t.near(r["received"][5], 2.0, "三方競爭：prism(1) 拿 12×1/6")
	t.ok(
		float(r["received"][5]) < float(r["received"][3]),
		"三方競爭：節點自帶的 priority=99 欄位被無視（只認類型）"
	)


## 環路：允許玩家把線接回去，解算必須收斂且不抖動。
func _cycle_converges(t: T) -> void:
	var nodes := [
		_n(1, "generator", 20.0), _n(2, "relay"), _n(3, "relay"), _n(4, "relay"),
		_n(5, "anchor", 0.0, 5.0),
	]
	var edges := [_e(1, 2, 10.0), _e(2, 3, 10.0), _e(3, 4, 10.0), _e(4, 2, 10.0), _e(4, 5, 10.0)]
	var a := FN.solve(nodes, edges, {})
	var b := FN.solve(nodes, edges, {})
	t.near(a["received"][5], 5.0, "環路：需求仍被完整滿足")
	t.near(a["flow"][0], 5.0, "環路：只送需求量，不在環裡空轉")
	t.eq(a["flow"], b["flow"], "環路：同輸入兩次解算結果完全相同（確定性）")


## 飢餓：滿足率線性縮放，**不停機**（GDD §3.1「停機會雪崩」）。
func _starvation_scales(t: T) -> void:
	var r := FN.solve(
		[_n(1, "generator", 4.0), _n(2, "smelter", 0.0, 10.0)],
		[_e(1, 2, 100.0)],
		{}
	)
	t.near(r["satisfaction"][2], 0.4, "飢餓：satisfaction = 4/10")
	t.ok(float(r["satisfaction"][2]) > 0.0, "飢餓：不歸零、不停機")


## ★ RG-19 儲槽充放電受**自己那條導管**的 cap 約束。
## 這是「能量是流率不是水池」的執行點——豁免它就等於偷偷退回全域水池。
func _silo_rate_limited_by_cap(t: T) -> void:
	# GDD §7.4：63/秒峰值、2 台發電機 40、缺口 −23。
	var thin := FN.solve(_deficit_net(300.0), _silo_edges(10.0), {})
	t.near(thin["sent"][4], 10.0, "儲槽：cap 10 的線最多只放得出 10/秒（不是 300，也不是 23）")
	t.near(thin["charge_delta"][4], -10.0, "儲槽：charge_delta 記為 −10")
	t.near(thin["received"][3], 50.0, "儲槽：下游收到 40+10")
	t.ok(float(thin["satisfaction"][3]) < 1.0, "儲槽：cap 10 補不滿缺口，波次仍在挨餓")

	# 幹線升到 cap 28 才放得出 23（GDD §7.2 的取捨表）。
	var fat := FN.solve(_deficit_net(300.0), _silo_edges(28.0), {})
	t.near(fat["sent"][4], 23.0, "儲槽：cap 28 的線放得出 23，剛好補平缺口")
	t.near(fat["satisfaction"][3], 1.0, "儲槽：缺口補平後滿足率回到 1.0")
	t.near(fat["charge_delta"][4], -23.0, "儲槽：只放缺口那麼多，不無故漏電")

	# 充能：盈餘時它換邊當消費者，速率同樣受 cap 約束。
	var surplus := FN.solve(
		[_n(1, "generator", 60.0), _n(2, "relay"), _n(3, "anchor", 0.0, 20.0),
			_n(4, SILO_TYPE, 0.0, 0.0, 0.0, 300.0)],
		[_e(1, 2, 100.0), _e(2, 3, 100.0), _e(2, 4, 10.0), _e(4, 2, 10.0)],
		{}
	)
	t.near(surplus["charge_delta"][4], 10.0, "儲槽：充能也被自己那條 cap 10 的線限制在 10/秒")


## ★ RG-18 無全域資源池：斷開儲槽後網路即無任何緩衝。
func _no_global_pool(t: T) -> void:
	var with_empty_silo := FN.solve(_deficit_net(0.0), _silo_edges(28.0), {})
	var nodes_without: Array = []
	for n: Dictionary in _deficit_net(300.0):
		if int(n["id"]) != 4:
			nodes_without.append(n)
	var without_silo := FN.solve(nodes_without, [_e(1, 2, 100.0), _e(2, 3, 100.0)], {})

	t.near(without_silo["satisfaction"][3], 40.0 / 63.0, "無全域池：拆掉儲槽，赤字立刻反映為滿足率下降")
	t.near(
		float(with_empty_silo["satisfaction"][3]), float(without_silo["satisfaction"][3]),
		"無全域池：空儲槽 = 沒有儲槽，沒有隱形緩衝"
	)
	t.near(with_empty_silo["sent"][4], 0.0, "無全域池：空儲槽放不出任何電")


## ★ 不變量：採集器無輸入需求 → 結構上不可能全域死鎖（GDD §3.1）。
func _harvester_never_deadlocks(t: T) -> void:
	# 連一條線都沒有的採集器，產出照樣成立。
	var alone := FN.solve([_n(1, "harvester", 5.0)], [], {})
	t.near(alone["supply_total"], 5.0, "採集器：沒有任何輸入也照樣產出")
	t.near(alone["satisfaction"][1], 1.0, "採集器：無需求 → satisfaction 恆為 1.0")

	# 全網嚴重飢餓時，採集器仍是不依賴任何人的源頭。
	var starved := FN.solve(
		[_n(1, "harvester", 5.0), _n(2, "smelter", 0.0, 999.0), _n(3, "anchor", 0.0, 999.0)],
		[_e(1, 2, 100.0), _e(2, 3, 100.0)],
		{}
	)
	t.near(starved["satisfaction"][1], 1.0, "採集器：全網飢餓時仍不被拖下水")
	t.ok(float(starved["supply_total"]) > 0.0, "採集器：全網飢餓時產出仍 > 0（無死鎖）")


# ── 建網小工具 ────────────────────────────────────────────────────────

const SILO_TYPE := "silo"


func _n(
	id: int, type: String, supply: float = 0.0, demand: float = 0.0,
	charge: float = 0.0, capacity: float = 0.0
) -> Dictionary:
	return {
		"id": id, "type": type, "supply": supply, "demand": demand,
		"charge": charge, "capacity": capacity,
	}


func _e(from: int, to: int, cap: float) -> Dictionary:
	return {"from": from, "to": to, "cap": cap}


## GDD §7.4 的赤字情境：供給 40、需求 63、缺口 −23，外加一座儲槽。
func _deficit_net(charge: float) -> Array:
	return [
		_n(1, "generator", 40.0), _n(2, "relay"), _n(3, "prism", 0.0, 63.0),
		_n(4, SILO_TYPE, 0.0, 0.0, charge, 300.0),
	]


## 儲槽那條線要兩條有向邊（進去充能、出來放電），cap 相同。
func _silo_edges(silo_cap: float) -> Array:
	return [_e(1, 2, 100.0), _e(2, 3, 100.0), _e(4, 2, silo_cap), _e(2, 4, silo_cap)]
