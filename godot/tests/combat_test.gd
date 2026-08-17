extends SceneTree
## 戰鬥計算（`10_GDD.md` §3.3、§7.4；`50_QA_PLAN.md` §2）。
##
## 這支測試鎖住的設計承諾：
##   ★ **交戰才耗電，待機 0**——全案的心臟。塔蓋著不打時電網完全感覺不到它
##   ★ **能量不足時射速線性下降，不停火**（§3.1 供不應求按比例降速）
##   ★ **匯率 1 礦砂 = 5 能量**——照字面 1:1 的話回收者是淨耗電，
##     「打破峰值約束的鑰匙」會是假的（CLAUDE.md 鎖定設計）
##   ★ **回收者算的是「射程內的死亡」，不是「自己的擊殺」**
##   ★ **回收的能量受自己那條導管的 cap 約束**——沒有全域能量池
##   ★ **拉動優先權改變誰先餓死**；優先權讀的是節點類型
##   ★ RG-17 光環再重也停不下敵人
##
## 跑法：<godot> --headless --path godot --script res://tests/combat_test.gd

const T := preload("res://tests/_assert.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Maps := preload("res://data/Maps.gd")
const MapsData := preload("res://data/Maps.gd")
const Enemies := preload("res://data/Enemies.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Shapes := preload("res://scripts/render/Shapes.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("combat_test", 177)
	_exchange_rate(t)
	_armor_and_barrier(t)
	_rate_of_fire(t)
	_targeting_and_pierce(t)
	_engage_power(t)
	_starved_towers_slow_down(t)
	_kill_salvage(t)
	_reclaimer_counts_deaths_not_kills(t)
	_reclaim_rate_is_capped_by_its_own_conduit(t)
	_knell_aura(t)
	_in_battle_node_upgrade(t)
	_who_is_feeding_this_tower(t)
	_priority_decides_who_starves(t)
	_breaker_splash(t)
	_m3_enemy_rules(t)
	# ★ M3 第二批（B3.2b）。三條規則各對應玩家的一個動詞，各配一個反向對照。
	_rustsurge_eats_lines(t)
	_bridges_still_safe_from_rust(t)
	_bulwark_shields_its_neighbours(t)
	_drainer_breaks_the_peak_budget(t)
	_every_enemy_looks_different(t)
	quit(t.report())


# ── ★ 碎浪的濺射（B1.1、§7.4）────────────────────────────────────────

## 它要解的是**密集隊列**，而它換來的代價是單體 dps 比錨還低。
## 兩件事都要成立，只驗其中一件就會養出一隻「錨但更強」的塔。
func _breaker_splash(t: T) -> void:
	# 單體：碎浪 22 × 0.6 發/秒 ＝ 13.2/秒 < 錨 18 × 1.2 ＝ 21.6/秒。
	t.ok(
		NodeDefs.of("breaker")["dmg"] * NodeDefs.of("breaker")["rof"]
		< NodeDefs.of("anchor")["dmg"] * NodeDefs.of("anchor")["rof"],
		"★ 單體 dps 比錨低——濺射是對『敵人排隊方式』的賭注，不是免費傷害"
	)
	t.eq(
		String(NodeDefs.of("breaker")["dmg_type"]), "physical",
		"★ 物理：甲殼護甲 8 是減法 → 碎浪打不動裝甲隊，剋制表沒被壓平"
	)
	t.ok(NodeDefs.alloy_cost("breaker") > 0, "★ 碎浪要合金：它是第一個合金去處")

	# 三隻擠在一起 → 一發打到三隻。**這是它存在的全部理由。**
	var s := _session()
	_power_plant(s)
	BuildController.place(s, "breaker", Vector2i(16, 6))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 6))
	_spawn_at(s, "drifter", 16.0)
	s.add_enemy("drifter")
	s.enemies[s.enemies.size() - 1]["progress"] = 15.0
	s.add_enemy("drifter")
	s.enemies[s.enemies.size() - 1]["progress"] = 17.0
	# 30 隻遠在射程外的對照組不需要——射程本來就有 `_targeting_and_pierce` 在守。
	var hp0: Array[float] = []
	for e: Dictionary in s.enemies:
		hp0.append(float(e["hp"]))
	# 射速 0.6/秒 → 平均 1.67 秒一發；推 30 tick（3 秒）保證至少開了一發。
	for _i in 30:
		BattleController.step(s)
	var hurt := 0
	for i in s.enemies.size():
		if float((s.enemies[i] as Dictionary)["hp"]) < hp0[i]:
			hurt += 1
	t.eq(hurt, 3, "★ 一發同時打到三隻（濺射以『主目標所在的格』為圓心）")


# ── ★ 匯率（CLAUDE.md 鎖定設計）────────────────────────────────────

func _exchange_rate(t: T) -> void:
	t.near(Combat.ORE_TO_POWER, 5.0, "★ 匯率常數：1 礦砂 = 5 能量")
	# §7.4 的三個數字，逐一對表。**這張表錯了，回收者的定位整個垮掉。**
	t.near(Combat.reclaim_power(12.0, 0.6), 36.0, "★ 漂蟲 12 礦砂 → 36 能量")
	t.near(Combat.reclaim_power(22.0, 0.6), 66.0, "★ 熾泳 22 礦砂 → 66 能量")
	t.near(Combat.reclaim_power(30.0, 0.6), 90.0, "★ 甲殼 30 礦砂 → 90 能量")
	# 匯率不是新發明的數字——它就是發電機的轉換比（§3.3）。
	var gen := NodeDefs.of("generator")
	t.near(
		float(gen["power_out"]) / float(gen["ore_in"]), Combat.ORE_TO_POWER,
		"★ 匯率＝發電機的轉換比（4 礦砂/秒 → 20 能量/秒）"
	)
	# 1:1 的話回收者一波回收 120 能量、卻要耗 210——淨耗電。這條斷言在守那件事。
	t.ok(
		Combat.reclaim_power(20.0, 0.6) * 10.0 > 7.0 * 30.0,
		"★ 均價 20 的敵人死 10 隻 > 回收者一波的耗能（否則它不是「鑰匙」是負擔）"
	)


# ── 護甲與屏障（§3.5 剋制表）──────────────────────────────────────

func _armor_and_barrier(t: T) -> void:
	var carapace := Enemies.of("carapace")   # 護甲 8
	var ember := Enemies.of("ember")         # 屏障 40%

	t.near(
		Combat.hit_damage(18.0, "physical", carapace, 0.0), 10.0,
		"護甲是**減法**：錨 18 打甲殼（護甲 8）→ 10"
	)
	t.near(
		Combat.hit_damage(30.0, "energy", ember, 0.0), 18.0,
		"屏障是**百分比**：稜鏡 30 打熾泳（屏障 40%）→ 18"
	)
	t.near(
		Combat.hit_damage(30.0, "energy", carapace, 0.0), 30.0,
		"能量傷害不吃護甲——這就是甲殼的剋制方式"
	)
	t.near(
		Combat.hit_damage(18.0, "physical", ember, 0.0), 18.0,
		"物理傷害不吃屏障——這就是熾泳的剋制方式"
	)
	t.near(
		Combat.hit_damage(18.0, "physical", carapace, 0.25), 12.0,
		"★ 潮鳴破甲 −25%：護甲 8 → 6，錨的傷害 10 → 12"
	)
	t.near(
		Combat.hit_damage(30.0, "energy", ember, 1.0), 18.0,
		"★ 破甲**不吃屏障**：屏障的剋制方式是物理傷害，不是破甲"
	)
	t.near(Combat.hit_damage(4.0, "physical", carapace, 0.0), 0.0, "傷害不會變成負的")


# ── ★ 射速：線性縮放、不停火（§3.1、§7.4）──────────────────────────

func _rate_of_fire(t: T) -> void:
	t.eq(_fire_count(1.2, 1.0, 100), 12, "滿電：1.2 發/秒 × 10 秒 = 12 發（累加器讓除不盡的射速仍然準）")
	t.eq(_fire_count(1.2, 0.5, 100), 6, "★ 滿足率 50% → 射速正好一半（線性，§7.4）")
	t.eq(_fire_count(1.2, 0.1, 100), 1, "★ 滿足率 10% → 10 秒仍打得出 1 發")
	t.ok(_fire_count(1.2, 0.1, 100) > 0, "★ 餓到剩一成也**不停火**（§3.1：停機會雪崩）")
	t.eq(_fire_count(1.2, 0.0, 100), 0, "滿足率 0：不開火")
	t.near(float(Combat.shots(0.0, 1.2, 0.0)["cd"]), 0.0, "不開火時累加器也不倒退")


func _fire_count(rof: float, sat: float, ticks: int) -> int:
	var cd := 0.0
	var fired := 0
	for i in ticks:
		var r := Combat.shots(cd, rof, sat)
		cd = float(r["cd"])
		fired += int(r["n"])
	return fired


# ── 目標選擇與稜鏡穿透 ────────────────────────────────────────────

func _targeting_and_pierce(t: T) -> void:
	var enemies: Array = [
		{"id": 1, "progress": 3.0}, {"id": 2, "progress": 9.0}, {"id": 3, "progress": 5.0},
	]
	t.eq(
		Combat.front_most([0, 1, 2], enemies), 1,
		"目標選擇「最前」＝路徑進度最大的那隻（最靠近核心）"
	)
	t.eq(Combat.front_most([], enemies), -1, "射程內沒人回 −1，不當掉")

	# 稜鏡站在 (33,4)，橫段路徑是 y=4：**同一列的敵人一次全穿**。
	var cells: Array = [
		Vector2i(28, 4), Vector2i(26, 4), Vector2i(30, 4),  # 同列，射程內
		Vector2i(30, 9),                                     # 不同列
		Vector2i(20, 4),                                     # 同列但超出射程 9
	]
	var hit := Combat.pierce_indices(Vector2i(33, 4), cells, 9.0)
	t.eq(hit.size(), 3, "★ 稜鏡：與路徑同列 → 一次貫穿 3 隻（§7.4 的對齊謎題）")
	t.ok(not hit.has(3), "不同列的不算——直線就是直線")
	t.ok(not hit.has(4), "同列但超出射程 9 格的不算")

	# 四條軸線中**敵人最多的那一條**：垂直 2 隻勝過水平 1 隻。
	var vert: Array = [Vector2i(10, 2), Vector2i(10, 6), Vector2i(13, 4)]
	var pick := Combat.pierce_indices(Vector2i(10, 4), vert, 9.0)
	t.eq(pick.size(), 2, "★ 稜鏡選敵人最多的那條軸線")
	t.ok(pick.has(0) and pick.has(1), "選中的是垂直那條")
	t.eq(
		Combat.pierce_indices(Vector2i(10, 4), vert, 9.0),
		Combat.pierce_indices(Vector2i(10, 4), vert, 9.0),
		"★ 同一局面兩次選出同一條線（確定性，§2.4）"
	)


# ── ★ 交戰耗能：待機 0（全案的心臟）──────────────────────────────

func _engage_power(t: T) -> void:
	# ① 塔蓋好、接上電、**射程內沒有敵人** → 電網完全感覺不到它。
	var idle := _session()
	_power_plant(idle)
	BuildController.place(idle, "anchor", Vector2i(16, 14))
	BuildController.lay_conduit(idle, Vector2i(16, 11), Vector2i(16, 14))
	BattleController.step(idle)
	t.near(
		float(idle.rates["power_demand"]), 0.0,
		"★ **待機耗能 0**：塔蓋著沒敵人，總需求仍是 0"
	)
	t.eq(int(idle.rates["engaged"]), 0, "交戰 0 座")

	# ② 同一座塔，射程內站一隻敵人 → 立刻開始吃電。
	var busy := _session()
	_power_plant(busy)
	BuildController.place(busy, "anchor", Vector2i(16, 7))   # 距路徑 (16,4) 3 格 < 射程 4
	BuildController.lay_conduit(busy, Vector2i(16, 8), Vector2i(16, 7))
	_spawn_at(busy, "drifter", 16.0)
	BattleController.step(busy)

	t.eq(int(busy.rates["engaged"]), 1, "★ 射程內有敵人 → 交戰 1 座")
	t.near(
		float(busy.rates["power_demand"]), 4.0,
		"★ **交戰耗能 4/秒**（§7.4 錨）——這一行就是「同一份能量餵塔還是餵生產線」"
	)
	t.near(
		_sat(busy, Vector2i(16, 7)), 1.0, "20 的發電機餵得起 4 的錨：滿足率 1.0"
	)


# ── ★ 電不夠：全部一起降速，沒有誰被判死（DoD）─────────────────────

func _starved_towers_slow_down(t: T) -> void:
	var s := _session()
	_power_plant(s)
	BuildController.place(s, "relay", Vector2i(16, 6))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 6))
	# 幹線 cap 22：**瓶頸不在線上**，這支測試要看的是供給不足時的分配。
	# ★ B1.6.1：索引 0（採集器→發電機）也要一起加粗——支線改從採集器接出去
	#   之後，電是走「發電機 → 採集器 → 幹線」，那一段沒加粗就換它當瓶頸了。
	BuildController.upgrade(s, 0)
	BuildController.upgrade(s, 0)
	BuildController.upgrade(s, 1)
	BuildController.upgrade(s, 1)
	BuildController.place(s, "prism", Vector2i(14, 6))
	BuildController.place(s, "prism", Vector2i(18, 6))
	BuildController.lay_conduit(s, Vector2i(16, 6), Vector2i(14, 6))
	BuildController.lay_conduit(s, Vector2i(16, 6), Vector2i(18, 6))

	_spawn_at(s, "drifter", 16.0)
	BattleController.step(s)

	t.eq(int(s.rates["engaged"]), 2, "兩座稜鏡都在交戰")
	t.near(float(s.rates["power_demand"]), 40.0, "★ 峰值需求 40/秒（一座稜鏡 ≈ 五座錨）")
	t.near(float(s.rates["power_supply"]), 20.0, "供給只有一台發電機的 20/秒")
	var a := _sat(s, Vector2i(14, 6))
	var b := _sat(s, Vector2i(18, 6))
	t.ok(a < 0.99 and b < 0.99, "★ 需求 40 供給 20 → 兩座都餓著")
	t.near(a + b, 1.0, "★ 供給按比例攤給兩座（合計滿足率 = 20/40 × 2）")
	t.ok(a > 0.0 and b > 0.0, "★ 餓著也照打——**沒有任何一座被判死**（§3.1）")


# ── 全域擊殺回收（§3.3）──────────────────────────────────────────

func _kill_salvage(t: T) -> void:
	t.near(Combat.SALVAGE, 0.25, "全域擊殺回收比例 25%")
	t.near(Combat.salvage_ore(12.0), 3.0, "漂蟲 12 礦砂 → 回收 3 礦砂")

	var s := _session()
	_power_plant(s)
	BuildController.place(s, "anchor", Vector2i(16, 7))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 7))
	_spawn_at(s, "drifter", 16.0)
	s.enemies[0]["hp"] = 1.0                          # 下一發必死
	var before: float = s.ore
	for i in 20:
		BattleController.step(s)

	t.eq(s.kills, 1, "★ 塔擊殺了那隻漂蟲")
	t.eq(s.enemies.size(), 0, "死掉的敵人真的從場上消失")
	t.near(s.salvage_total, 3.0, "★ 回收 3 礦砂（價值 12 × 25%）")
	t.near(
		s.ore, before + 3.0,
		"★ 回收的礦砂**直接入帳**——它是擊殺處撿的殘骸，不必接線運回核心（§3.3）"
	)


# ── ★ 回收者：算的是「射程內的死亡」，不是「自己的擊殺」（§7.4）──────

func _reclaimer_counts_deaths_not_kills(t: T) -> void:
	# 錨 (14,7) 射速 1.2 會在第 9 tick 開火；回收者射速 0.9 要到第 12 tick。
	# 所以**擊殺一定是錨的**，回收者一發都還沒打就回收到能量。
	var s := _kill_beside_reclaimer(Vector2i(16, 7))
	t.eq(s.kills, 1, "前置：那隻漂蟲死了（死在錨手上）")
	t.near(
		s.reclaimed_total, 36.0,
		"★ 回收者回收 36 能量（12 × 60% × 匯率 5）——**不限自己擊殺**"
	)
	t.near(s.salvage_total, 3.0, "同一次擊殺**同時**產生礦砂與能量（兩條規則並存）")

	# 射程外的死亡不算——這正是「擺在殺戮最密集處」這道空間謎題的來源。
	var far := _kill_beside_reclaimer(Vector2i(11, 12))   # 離擊殺點 9.4 格，射程 5
	t.eq(far.kills, 1, "前置：一樣死了一隻")
	t.near(
		far.reclaimed_total, 0.0,
		"★ 死在射程外 → 回收 0。**擺位是空間謎題，不是蓋了就有**（§7.4）"
	)


# ── ★ 回收的能量受自己那條導管的 cap 約束（沒有全域能量池）────────────

func _reclaim_rate_is_capped_by_its_own_conduit(t: T) -> void:
	# 回收者 → 儲槽，網路裡沒有別的供給也沒有別的消費者：
	# 這條線每秒送得出多少，就是回收的能量每秒到得了多少。
	var s := _session()
	BuildController.place(s, "reclaimer", Vector2i(16, 7))
	BuildController.place(s, "silo", Vector2i(16, 11))
	BuildController.lay_conduit(s, Vector2i(16, 7), Vector2i(16, 11))
	var r: Dictionary = s.node_at(Vector2i(16, 7))
	r["buffer"] = 100.0

	for i in 10:
		BattleController.step(s)                      # 1 秒
	t.near(
		float(r["buffer"]), 90.0,
		"★ 基礎 cap 10 的線：一秒只推得出 **10** 能量（不是 100）"
	)
	t.near(
		float(s.rates["silo_charge"]), 10.0,
		"★ 推出去的 10 真的進了儲槽——它是**流過導管**，不是憑空到帳"
	)

	BuildController.upgrade(s, 0)
	BuildController.upgrade(s, 0)
	BuildController.upgrade(s, 0)                     # cap 28
	for i in 10:
		BattleController.step(s)
	t.near(
		float(r["buffer"]), 62.0,
		"★ 加粗到 cap 28 → 同樣一秒推得出 28。**回收者的線是一個真的瓶頸**"
	)

	# ★ 緩衝有上限：沒有上限的話回收者就是一座沒造價、沒容量欄位、
	#   也沒被列進優先權面板的第二座儲槽。
	r["buffer"] = 100.0
	var over := _session()
	BuildController.place(over, "reclaimer", Vector2i(16, 7))
	var rr: Dictionary = over.node_at(Vector2i(16, 7))
	rr["buffer"] = 95.0
	BattleController._on_kill(over, 30.0, Vector2i(16, 7))   # 甲殼：回收 90
	t.near(
		float(rr["buffer"]), float(NodeDefs.of("reclaimer")["reclaim_buffer"]),
		"★ 回收緩衝有上限（100），溢流丟棄"
	)
	t.near(
		over.reclaimed_total, 5.0,
		"★ 累計只記真的進得了緩衝的 5——溢流掉的電從來沒進過電網"
	)

	# 沒有下游需求時緩衝不會蒸發——推不出去就留著，下一 tick 再試。
	var stuck := _session()
	BuildController.place(stuck, "reclaimer", Vector2i(16, 7))
	var lone: Dictionary = stuck.node_at(Vector2i(16, 7))
	lone["buffer"] = 50.0
	for i in 30:
		BattleController.step(stuck)
	t.near(
		float(lone["buffer"]), 50.0,
		"★ 沒接線的回收者：回收的能量原地不動——**沒有全域能量池可以偷渡**"
	)


# ── 潮鳴光環（§7.4）──────────────────────────────────────────────

func _knell_aura(t: T) -> void:
	var nodes: Array = [{"id": 1, "type": "knell", "cell": Vector2i(10, 6)}]
	var cells: Array = [Vector2i(10, 4), Vector2i(20, 4)]
	var full := Combat.auras(nodes, cells, {1: 1.0})
	t.near(full[0].x, 0.4, "光環：射程內減速 −40%")
	t.near(full[0].y, 0.25, "光環：射程內破甲 −25%")
	t.near(full[1].x, 0.0, "射程外沒有光環")

	var half := Combat.auras(nodes, cells, {1: 0.5})
	t.near(half[0].x, 0.2, "★ 光環強度按滿足率縮放：電剩一半，減速也剩一半")
	t.near(half[0].y, 0.125, "★ 破甲同樣按滿足率縮放")

	nodes.append({"id": 2, "type": "knell", "cell": Vector2i(10, 7)})
	t.near(
		(Combat.auras(nodes, cells, {1: 1.0, 2: 1.0})[0] as Vector2).x, 0.4,
		"★ 兩座潮鳴**不疊加**——控場塔不做成堆量遊戲"
	)

	# ★ RG-17 的守門：減速再重，速度也永遠 > 0。
	var s := _session()
	_power_plant(s)
	BuildController.place(s, "knell", Vector2i(16, 7))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 7))
	_spawn_at(s, "drifter", 16.0)
	for i in 10:
		BattleController.step(s)
	var moved: float = float((s.enemies[0] as Dictionary)["progress"]) - 16.0
	t.near(moved, 0.6, "★ 減速 −40%：1.0 格/秒 → 0.6 格/秒")
	t.ok(moved > 0.0, "★ RG-17：**沒有任何建築能讓一隻敵人停下**")


# ── ★ 優先權決定誰先餓死（DoD）────────────────────────────────────

func _priority_decides_who_starves(t: T) -> void:
	var s := _session()
	_power_plant(s)
	BuildController.place(s, "relay", Vector2i(16, 6))
	BuildController.place(s, "prism", Vector2i(14, 6))
	BuildController.place(s, "anchor", Vector2i(18, 6))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 6))   # 索引 1：幹線
	BuildController.lay_conduit(s, Vector2i(16, 6), Vector2i(14, 6))    # 索引 2：稜鏡支線
	BuildController.lay_conduit(s, Vector2i(16, 6), Vector2i(18, 6))
	for i in 2:
		BuildController.upgrade(s, 1)
		BuildController.upgrade(s, 2)                 # 兩條都加粗：瓶頸只能是「電不夠」

	_spawn_at(s, "drifter", 16.0)
	BattleController.step(s)
	var even_prism := _sat(s, Vector2i(14, 6))
	var even_anchor := _sat(s, Vector2i(18, 6))
	t.ok(even_prism < 0.99, "前置：電不夠，稜鏡餓著")

	# 稜鏡拉到 5、錨壓到 1。**同一份電，重新裁決誰先拿到。**
	s.priorities["prism"] = 5
	s.priorities["anchor"] = 1
	BattleController.step(s)
	t.ok(
		_sat(s, Vector2i(14, 6)) > even_prism,
		"★ DoD：拉動優先權滑桿改變了誰先餓死（稜鏡 3→5，滿足率上升）"
	)
	t.ok(
		_sat(s, Vector2i(18, 6)) < even_anchor,
		"★ 而錨相對餓了——電就那麼多，這是取捨不是設定"
	)

	# 面板本身的約束（§3.1）。**真正被鎖住的是「依類型、不依單一節點」**——
	# 那才是「操作負擔不隨建築數量成長」（R-1）的來源。列數上限跟著角色名冊走：
	# B1.1 加了熔爐與碎浪 → 9 列。12 是這個單欄／雙欄版面撐得住的天花板，
	# 撞到就得改成角色分組（M2 有 16 隻角色，見風險 R-15）。
	t.ok(NodeDefs.PRIORITY_ROWS.size() <= 12, "優先權面板 ≤ 12 列（撞到就要改分組，R-15）")
	t.eq(
		NodeDefs.PRIORITY_ROWS.size(), 9,
		"★ 列數＝有需求的節點『類型』數，不隨蓋了幾座成長"
	)
	t.ok(NodeDefs.PRIORITY_ROWS.has("silo"), "★ 儲槽佔一格：它是核心策略建築，不是配件")
	t.ok(NodeDefs.PRIORITY_ROWS.has("smelter"), "★ 熔爐佔一格：它就是「餵塔還是餵產線」那一格")
	for type: String in NodeDefs.PRIORITY_ROWS:
		t.ok(NodeDefs.of(type).size() > 0, "優先權列「%s」對得上資料表" % type)
	# 雙欄的分界＝生產側／防線側。分界左邊不得出現塔，右邊不得出現生產節點，
	# 否則那條線就只是排版而不是那句話（`Battle.gd` 的面板照這個切）。
	for i in NodeDefs.PRIORITY_ROWS.size():
		var is_tower: bool = NodeDefs.of(String(NodeDefs.PRIORITY_ROWS[i])).get("tower", false)
		t.eq(
			is_tower, i >= NodeDefs.PRIORITY_SPLIT,
			"優先權第 %d 列落在正確的欄（左生產／右防線）" % i
		)
	t.eq(NodeDefs.DEFAULT_PRIORITY["silo"], 2, "預設：儲槽充能搶不贏塔（波次期先餵防線）")
	t.eq(NodeDefs.DEFAULT_PRIORITY["anchor"], 3, "預設：塔 3 > 儲槽 2")
	t.eq(NodeDefs.DEFAULT_PRIORITY["smelter"], 2, "★ 預設：熔爐搶不贏塔——輸掉核心是不可逆的")


# ── 共用 ──────────────────────────────────────────────────────────

## ★ 局內臨時升級（`10_GDD.md` §4.3、B3.5）。
##
## 這一段要證明的是**兩件事一起動**：升級抬效果、也抬耗能。
## 只驗前者的話，一個「傷害 ×1.75 而耗能不變」的實作照樣全綠，
## 而那正是把核心取捨（同一份能量餵塔還是餵產線）拆掉的那個版本。
func _in_battle_node_upgrade(t: RefCounted) -> void:
	# ── 規則本身 ──
	t.eq(Build.node_scale(0), 1.0, "0 級＝原值")
	t.eq(Build.node_scale(3), 1.75, "3 級 ＝ ×1.75（每級 +25%）")
	t.eq(Build.node_scale(5), 2.25, "★ 5 級 ＝ ×2.25（B3.9 把上限從 3 抬到 5）")
	t.eq(Build.NODE_MAX_LEVEL, 5, "★ 上限就是 5（使用者指定「升級會有共 5 級」）")
	t.eq(Build.node_scale(9), Build.node_scale(5), "★ 越界夾回上限，不是無限成長")
	t.eq(Build.node_upgrade_cost(50, 0), 25, "錨（50）升 1 級 ＝ 半價")
	t.eq(Build.node_upgrade_cost(50, 2), 75, "升 3 級 ＝ 一倍半")
	t.eq(Build.node_upgrade_cost(50, 4), 125, "★ 升 5 級 ＝ 兩倍半（五級全升 ＝ 造價的 7.5 倍）")

	# ── 產出真的變（採集器：它沒有輸入，量得到乾淨的倍率） ──
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(16, 8))
	# 繞到南邊再進核心：核心 (34,14) 的西邊被下坡列 x=30 擋著，
	# 而導管過路徑只能走橋——淺灘沒有橋，所以從 y=17 那一排繞過去。
	for cell: Vector2i in [Vector2i(22, 14), Vector2i(25, 17), Vector2i(34, 17)]:
		BuildController.place(s, "relay", cell)
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(22, 14))
	BuildController.lay_conduit(s, Vector2i(22, 14), Vector2i(25, 17))
	BuildController.lay_conduit(s, Vector2i(25, 17), Vector2i(34, 17))
	BuildController.lay_conduit(s, Vector2i(34, 17), Vector2i(34, 14))
	BattleController.step(s)
	var base := float(s.rates["ore_in"])
	t.ok(base > 0.0, "（前提）採集器在送礦")
	for _i in Build.NODE_MAX_LEVEL:
		t.eq(
			BuildController.upgrade_node(s, Vector2i(16, 8)), Build.OK,
			"採集器升得了級"
		)
	t.eq(
		BuildController.upgrade_node(s, Vector2i(16, 8)), Build.MAX_LEVEL,
		"★ 到 5 級就升不上去（上限是規則不是提示）"
	)
	BattleController.step(s)
	# ★★ **升級把瓶頸推回導管上**——這一條就是 `Build.gd` 那段註解的證據。
	#
	#    3 級採集器產 10.5/秒，而基礎導管 cap 是 10：**實際只送得到 10**。
	#    這一條當初是紅的（預期 10.5、實得 10.0），而紅得對——
	#    我寫斷言時假設了「產得出來就送得到」，那正是這個機制要打掉的假設。
	t.near(
		float(s.rates["ore_in"]), 10.0,
		"★★ 滿級採集器產 13.5，而 cap 10 的線只送得到 10（升級把瓶頸推給導管）", 0.01
	)
	# 加粗**整條**線之後，那 0.5 才真的到得了帳上。
	# （只加粗第一段是不夠的——瓶頸是那一串裡最窄的任何一段，
	#   而它們四段當初都是 cap 10。這也是紅過一次才寫對的。）
	for ci in s.conduits.size():
		BuildController.upgrade(s, ci)
	BattleController.step(s)
	t.near(
		float(s.rates["ore_in"]), base * 2.25,
		"★ 加粗之後才拿得到完整的 ×2.25", 0.01
	)

	# ── ★ **消費者的胃口也一起長**。發電機升級之後每秒吃 4 → 7 礦砂，
	#      所以它的供電**不會**乾淨地 ×1.75——會被自己的礦砂滿足率拉回來。
	#      這一條當初是紅的（預期 35、實得 30），而**紅得對**：
	#      我以為升級只加產出，實際上它同時把那台機器的胃口撐大了。
	var g := _session()
	_power_plant(g)
	BattleController.step(g)
	var g0 := float(g.rates["power_supply"])
	for _i in Build.NODE_MAX_LEVEL:
		BuildController.upgrade_node(g, Vector2i(16, 11))
	BattleController.step(g)
	var g1 := float(g.rates["power_supply"])
	t.ok(g1 > g0, "滿級發電機供得比較多")
	t.ok(
		g1 < g0 * 2.25,
		"★★ 但**達不到 ×2.25**——它自己的礦砂需求也 ×2.25，而那台採集器沒跟著升"
	)

	# ── 耗能也真的變（塔）──**這一條是這一段存在的理由** ──
	var s2 := _session()
	_power_plant(s2)
	BuildController.place(s2, "anchor", Vector2i(16, 7))   # 距路徑 (16,4) 3 格 < 射程 4
	BuildController.lay_conduit(s2, Vector2i(16, 8), Vector2i(16, 7))
	_spawn_at(s2, "drifter", 16.0)
	BattleController.step(s2)
	var d0 := float(s2.rates["power_demand"])
	t.ok(d0 > 0.0, "（前提）錨在交戰、正在吃電")
	for _i in Build.NODE_MAX_LEVEL:
		BuildController.upgrade_node(s2, Vector2i(16, 7))
	BattleController.step(s2)
	t.near(
		float(s2.rates["power_demand"]), d0 * 2.25,
		"★★ 5 級塔的**耗能**也 ×2.25——升級買的是集中，不是效率", 0.01
	)

	# ── ★★ 使用者實玩回報：「潮鳴跟霜礁升級都沒用」（B3.8）────────────────
	#
	#    兩隻的 `dmg` 與 `rof` 都是 0——它們**整個效果**都在 `slow` 與
	#    `armor_break` 上，而 B3.5 只把級數乘進了 `dmg`／`ore_out`／`power_out`。
	#    於是升級對它們的唯一作用是**多吃 25% 的電**：嚴格更差的一筆消費。
	#
	#    `auras()` 是純函式，所以這裡直接餵它一個節點陣列，不必跑一整局。
	#    ⚠ 用**兩個級數的同一隻塔**比，不比絕對值——比絕對值的話，日後動一次
	#      資料表就會變成假紅，而壞掉的是斷言不是功能。
	for aura_type: String in ["knell", "frostreef"]:
		var cell := Vector2i(10, 10)
		var probe: Array = [Vector2i(10, 11)]     # 貼著它，兩種射程都罩得到
		var lo: Array[Vector2] = Combat.auras(
			[{"id": 1, "type": aura_type, "cell": cell, "level": 0}], probe, {}
		)
		var hi: Array[Vector2] = Combat.auras(
			[{"id": 1, "type": aura_type, "cell": cell, "level": Build.NODE_MAX_LEVEL}], probe, {}
		)
		var base_def := NodeDefs.of(aura_type)
		# 減速與破甲**至少有一項要真的變強**（霜礁沒有破甲，只有減速）。
		t.ok(
			hi[0].x > lo[0].x or hi[0].y > lo[0].y,
			"★★ %s 升到滿級之後光環真的更強（使用者回報「升級都沒用」）"
			% NodeDefs.label(aura_type)
		)
		# 而且**耗能確實有漲**——沒有這一句，一個「效果不變、耗能也不變」的
		# 實作也能讓上面那條變綠（只要它的 `power` 級數夠多）。
		t.ok(
			Build.node_scale(Build.NODE_MAX_LEVEL) > Build.node_scale(0),
			"（對照）%s 的耗能本來就在漲——所以效果不漲＝嚴格更差" % NodeDefs.label(aura_type)
		)
		if float(base_def.get("slow", 0.0)) > 0.0:
			t.ok(
				hi[0].x <= Combat.SLOW_MAX + 0.001,
				"★ 減速夾在上限內——**敵人永不停步**是鎖定設計，1.0 就是釘住"
			)

	# ── ★ 每一級加的不是同一樣東西（§4.3，B3.8，使用者指定）────────────
	#
	#    「應該是要每次升級有不同效果，這樣多元化的效果才會好玩。」
	#    三級走完是一隻**質變過**的塔，不是同一隻塔的 1.75 倍。
	t.ok(
		Build.node_range("anchor", 3) > Build.node_range("anchor", 0),
		"★★ 升級會加射程（錨的第 3 級）——使用者指出這個機制原本不存在"
	)
	t.eq(
		Build.node_range("anchor", 0), float(NodeDefs.of("anchor")["range"]),
		"0 級＝表上的原值"
	)
	t.ok(
		Build.rof_scale("anchor", 2) > Build.rof_scale("anchor", 1),
		"★ 錨的第 2 級加的是射速"
	)
	t.eq(
		Build.rof_scale("anchor", 1), 1.0,
		"★ 而第 1 級**不**加射速——三級各不相同，不是每級都全加"
	)
	t.ok(
		Build.splash_radius("breaker", 2) > Build.splash_radius("breaker", 0),
		"★ 碎浪的第 2 級加濺射半徑（它賣的就是這個）"
	)
	t.eq(
		Build.splash_radius("anchor", Build.NODE_MAX_LEVEL), 0.0,
		"★ 沒有濺射的塔升到滿級也長不出濺射"
	)
	t.ok(
		Build.node_range("frostreef", 1) > Build.node_range("frostreef", 0),
		"★ 霜礁的短板是射程 3，所以它第一級就補射程"
	)
	# ★ 每一隻塔的五級**必須都寫了**，而且只用得上那四個詞。
	#   漏寫一隻的症狀是「它安靜地退回五個 power」——那正是 B3.8 要修掉的東西，
	#   而它不會報錯（`10_GDD.md` §4.3；B2.4 的 `_no_glyph` 是同一個錯法）。
	var vocab := [Build.STEP_POWER, Build.STEP_RANGE, Build.STEP_ROF, Build.STEP_SPLASH]
	var no_steps := PackedStringArray()
	var bad_steps := PackedStringArray()
	for type: String in NodeDefs.BUILDABLE:
		var d := NodeDefs.of(type)
		if not d.get("tower", false):
			continue
		var steps: Array = d.get("steps", [])
		if steps.size() != Build.NODE_MAX_LEVEL:
			no_steps.append(type)
			continue
		for st: Variant in steps:
			if not vocab.has(String(st)):
				bad_steps.append("%s:%s" % [type, st])
	t.eq(
		String(",".join(no_steps)), "",
		"★★ 每一隻塔都要寫滿五級的 `steps`（漏寫會安靜地退回五個 power）"
	)
	t.eq(String(",".join(bad_steps)), "", "★ `steps` 只能用那四個詞（打錯字＝那一級無效）")
	# 而生產節點**刻意沒有** `steps`：它們沒有第二個維度，退回五個 power 是對的。
	t.eq(
		Build.effect_scale("extractor", 5), Build.node_scale(5),
		"★ 沒寫 `steps` 的節點＝五個 power ＝ B3.5 的原行為，一個數字都不變"
	)

	# ── ★★ B3.9：五級，而且**每一級都看得出來**（使用者指定）────────────────
	#
	#    「升級會有共 5 級，且每一級都要有外觀上的改變。」
	#    外觀有兩個通道，這裡釘住的是**尺寸**那一個——它是唯一一個
	#    「每一種節點、每一級都保證不同」的通道（零件的形狀只有升到那一項時才變，
	#    而採集器五級都是出力）。尺寸只要有一級沒長，那一級在畫面上就是隱形的。
	var seen_scales: Array[float] = []
	for lv in Build.NODE_MAX_LEVEL + 1:
		var sc := Shapes.level_scale(lv)
		for prev: float in seen_scales:
			t.ok(sc > prev + 0.001, "★★ %d 級的塔身比每一個更低的級數都大（每一級都看得出來）" % lv)
		seen_scales.append(sc)
	t.eq(Shapes.level_scale(0), 1.0, "★ 沒升過的塔是原尺寸（擺放預覽走的也是這條）")
	t.ok(
		Shapes.level_scale(Build.NODE_MAX_LEVEL) * 13.0 < Shapes.GRID * 0.55,
		"★ 滿級塔身仍在自己那一格裡（最大的塔身半徑 13px，半格 16px）"
	)
	# ★ **`power` 最多三級**。`slow`／`reclaim` 是比例，乘四次就越過自己的物理意義
	#   ——回收 1.05 ＝ 回收得比敵人的價值還多，那是印鈔機不是塔。
	#   逐塔查而不是只查現有的兩隻：這張表以 type 為鍵，而漏掉的那一隻不會報錯。
	var over_power := PackedStringArray()
	for type: String in NodeDefs.BUILDABLE:
		var d := NodeDefs.of(type)
		if not d.get("tower", false):
			continue
		var mx := Build.NODE_MAX_LEVEL
		if Build.step_count(type, mx, Build.STEP_POWER) > 3:
			over_power.append(type)
		var eff := Build.effect_scale(type, mx)
		if float(d.get("reclaim", 0.0)) * eff > 1.0:
			over_power.append("%s:回收 %.2f" % [type, float(d["reclaim"]) * eff])
		if float(d.get("slow", 0.0)) * eff > Combat.SLOW_MAX + 0.001:
			over_power.append("%s:減速 %.2f" % [type, float(d["slow"]) * eff])
	t.eq(
		String(",".join(over_power)), "",
		"★★ 滿級的比例欄位不得越界（回收 ≤ 100%、減速 ≤ 上限、`power` ≤ 3 級）"
	)
	# ★ 五級的階梯**真的用到了新的兩級**：至少一隻塔的第 4／5 級加的東西
	#   和它前三級的最後一項不同——否則「擴到五級」等於多買兩份同樣的東西。
	t.ok(
		Build.node_range("frostreef", 5) - Build.node_range("frostreef", 3) >= 2.0,
		"★ 霜礁的第 4、5 級都在補射程（3 → 7 格的減速場）"
	)
	t.ok(
		Build.rof_scale("anchor", 5) > Build.rof_scale("anchor", 3),
		"★ 錨的第 5 級加射速——五級走完是一挺機槍"
	)

	# ── 核心升不得 ──
	t.eq(
		BuildController.upgrade_node(s, s.core()["cell"]), Build.OCCUPIED,
		"★ 核心升不得（它沒有產出也沒有耗能，一顆「5 級核心」只會騙人）"
	)
	# ── 錢不夠就不給升，而且**不扣款** ──
	var s3 := _session()
	BuildController.place(s3, "extractor", Vector2i(16, 8))
	s3.ore = 1.0
	t.eq(
		BuildController.upgrade_node(s3, Vector2i(16, 8)), Build.NO_ORE,
		"礦砂不夠就升不了"
	)
	t.eq(s3.ore, 1.0, "★ 升不成不得扣款")
	t.eq(int(s3.node_at(Vector2i(16, 8))["level"]), 0, "★ 升不成級數不得變")

	# ── 級數要進狀態摘要（否則重播會在有人升級過的局上靜靜地對不上） ──
	var a := _session()
	BuildController.place(a, "extractor", Vector2i(16, 8))
	var h0: String = a.state_hash()
	BuildController.upgrade_node(a, Vector2i(16, 8))
	t.ok(a.state_hash() != h0, "★★ 升級會改變狀態摘要（`level` 是狀態不是裝飾）")


## ★ 「電從哪來」（`FlowNetwork.upstream_power()`、B3.6）。
##
## 這一段要證明的是它逆著**實際流向**走，不是「有沒有連著」——
## 一座塔可能連著好幾條線，而這一刻真正在餵它的只有其中幾條。
## 只驗「連著的都算上」的話，一個回傳「所有相鄰節點」的實作照樣全綠，
## 而那對玩家沒有用：他問的是我的電從哪來，不是我接了幾條線。
func _who_is_feeding_this_tower(t: RefCounted) -> void:
	var s := _session()
	_power_plant(s)                                   # 採集器(16,8) → 發電機(16,11)
	BuildController.place(s, "anchor", Vector2i(16, 7))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 7))
	_spawn_at(s, "drifter", 16.0)
	BattleController.step(s)

	var net: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		net[c["id"]] = v.y
	var sources: Dictionary = {Vector2i(16, 11): true}

	var chain: Dictionary = FlowNetwork.upstream_power(
		s.conduits, net, Vector2i(16, 7), sources
	)
	t.eq(
		(chain["sources"] as Dictionary).size(), 1,
		"★ 找得到那一台在餵它的發電機"
	)
	t.ok(
		(chain["sources"] as Dictionary).has(Vector2i(16, 11)),
		"★ 而且就是 (16,11) 那一台"
	)
	t.ok(
		(chain["conduits"] as Dictionary).size() >= 1,
		"★ 沿途的導管也標得出來（畫面要把它們亮起來）"
	)

	# ★★ **反向對照：沒有電流進來的時候，答案要是空的。**
	#    敵人走光 → 塔不交戰 → 不吃電 → 沒有任何一條線在餵它。
	#    這一條就是「流向 vs 連著」的分界：拓樸完全沒變，答案要變。
	s.enemies.clear()
	BattleController.step(s)
	var idle_net: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v2: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		idle_net[c["id"]] = v2.y
	var idle_chain: Dictionary = FlowNetwork.upstream_power(
		s.conduits, idle_net, Vector2i(16, 7), sources
	)
	t.eq(
		(idle_chain["sources"] as Dictionary).size(), 0,
		"★★ 待機時沒有任何來源——線還連著，但這一刻沒有電流進來"
	)

	# 選錯格（空地）不得炸，回空的。
	var nowhere: Dictionary = FlowNetwork.upstream_power(
		s.conduits, net, Vector2i(1, 1), sources
	)
	t.eq((nowhere["sources"] as Dictionary).size(), 0, "空地沒有供電來源（也不得炸）")


func _session() -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SHOAL)
	# B1.1 起導管升到 2/3 級要合金。本檔測的是**電網與戰鬥**，加粗只是為了把
	# 瓶頸挪開——所以直接發合金，不讓「合金經濟」變成每個電網測試的前置條件。
	# 合金經濟本身由 `build_test` 與 `flow_test` 負責。
	s.alloy = 999.0
	return s


## 一台餵飽的發電機（20 能量/秒），接口在 (16,11)。
func _power_plant(s: RefCounted) -> void:
	BuildController.place(s, "extractor", Vector2i(16, 8))
	BuildController.place(s, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 11))


## 一隻血剩 1 的漂蟲站在 (16,4)，錨 (14,7) 把它打死，回收者站在 `cell`。
## 跑 20 個 tick 後回傳整局——射程內／外只差 `cell` 這一個參數。
func _kill_beside_reclaimer(cell: Vector2i) -> RefCounted:
	var s := _session()
	_power_plant(s)
	# ★ B1.6.1：樞紐從 (16,9) 移到 (14,9)。(16,9) 坐在「採集器→發電機」那條
	#   導管的正中間，於是每一條從它接出去的線都整段疊在那條線上——
	#   新規則（不得和既有導管疊在同一排格上）擋掉的正是這個。
	BuildController.place(s, "relay", Vector2i(14, 9))
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(14, 9))
	BuildController.place(s, "reclaimer", cell)
	BuildController.lay_conduit(s, Vector2i(14, 9), cell)
	BuildController.place(s, "anchor", Vector2i(14, 7))
	BuildController.lay_conduit(s, Vector2i(14, 9), Vector2i(14, 7))
	_spawn_at(s, "drifter", 16.0)
	s.enemies[0]["hp"] = 1.0
	for i in 20:
		BattleController.step(s)
	return s


## 開打並把一隻敵人放在指定路徑進度上。
## **先把準備期跑完再開波**：否則提前召喚倍率（B0.6）會是 1.5，
## 這支測試的掉落數字全部乘 1.5——那是另一支測試（`hud_test`）的事。
func _spawn_at(s: RefCounted, type: String, progress: float) -> void:
	s.phase_time = s.prep_time()
	BattleController.start_wave(s)
	s.spawn_queue.clear()          # 只留手放的這一隻，波次表不要插進來
	s.add_enemy(type)
	s.enemies[s.enemies.size() - 1]["progress"] = progress


func _sat(s: RefCounted, cell: Vector2i) -> float:
	return float((s.rates["satisfaction"] as Dictionary).get(s.node_at(cell)["id"], 1.0))


# ── M3 第一批敵人的三條新規則（B3.2、§7.5）──────────────────────────

## 三隻各帶一條新規則，而**規則寫在表上 ≠ 規則作用在局面上**（RG-142 的同一課）。
## 這一段一律問模擬：跑真的 tick，量真的位移與血量。
func _m3_enemy_rules(t: T) -> void:
	_swift_ignores_slow(t)
	_pack_comes_in_runs(t)
	_regen_needs_a_dps_floor(t)


## ★ 迅捷：**光環抓不住它**。§3.5 的屬性表從 M0 就寫著這一條，
## 而 B3.2 之前沒有任何一隻敵人有它——這條斷言就是那句話第一次有人守。
func _swift_ignores_slow(t: T) -> void:
	# 同一張圖、同一座潮鳴、同樣跑 40 tick，只換敵人的種類。
	# ⚠ 潮鳴**要有電才有光環**（強度按滿足率縮放）。第一版忘了接發電機，
	#   於是「熾泳沒被拖慢」——量到的是一座沒通電的塔，不是迅捷。
	var moved := {}
	for type: String in ["ember", "surge"]:
		var s := _session()
		_power_plant(s)
		BuildController.place(s, "knell", Vector2i(16, 7))
		BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 7))
		_spawn_at(s, type, 16.0)
		for _i in 10:
			BattleController.step(s)
		moved[type] = float((s.enemies[0] as Dictionary)["progress"]) - 16.0
	# 1 秒（10 tick）。熾泳 1.6 格/秒 被 −40% 拖成 0.96；潛涌 1.9 一格都不掉。
	t.near(float(moved["surge"]), 1.9, "★★ 迅捷：站在潮鳴的光環裡，位移仍是滿速", 0.02)
	t.near(float(moved["ember"]), 1.6 * 0.6,
		"★ 反向對照：同一座潮鳴確實拖得住不迅捷的熾泳", 0.02)


## ★ 群體：一次抽中連續佔掉 `pack` 個出場位。
## **隻數與間隔兩條不變量都不動**（§7.10）——群體改的是同一批出場位裡出現什麼。
func _pack_comes_in_runs(t: T) -> void:
	for w in [9, 12, 15, 21, 30]:
		var sched := Enemies.endless_schedule(4242, w)
		t.eq(sched.size(), Enemies.endless_count(w), "第 %d 波：隻數仍是公式那一個" % w)
		for i in range(1, sched.size()):
			t.near(
				float(sched[i]["at"]) - float(sched[i - 1]["at"]), Enemies.ENDLESS_GAP,
				"第 %d 波：間隔仍是固定的 %.1f 秒" % [w, Enemies.ENDLESS_GAP]
			)
	# 真的排得出「連續三隻苔群」（不然 `pack` 只是一個沒有人讀的欄位）。
	var runs := 0
	for w in range(9, 40):
		var sched := Enemies.endless_schedule(4242, w)
		for i in range(2, sched.size()):
			if (String(sched[i]["type"]) == "bloom" and String(sched[i - 1]["type"]) == "bloom"
				and String(sched[i - 2]["type"]) == "bloom"):
				runs += 1
	t.ok(runs > 0, "★ 苔群真的成串出現（%d 串）" % runs)


## ★ 再生：**dps 有一個門檻**。這條規則接的是全案的核心命題（§3.1 峰值電力）——
## 塔在缺電時射速線性下降，而降到某一點之後 dps 追不上再生，它就永遠不會死。
func _regen_needs_a_dps_floor(t: T) -> void:
	var def := Enemies.of("mender")
	var regen := float(def["regen"])
	t.ok(regen > 0.0, "癒殼有再生")

	# ① 沒有人打它：血量回得滿，而且**不會超過上限**。
	var s := SessionState.new()
	s.setup(MapsData.SHOAL)
	s.phase = "wave"
	var id := s.add_enemy("mender")
	for e: Dictionary in s.enemies:
		if int(e["id"]) == id:
			e["hp"] = float(e["max_hp"]) * 0.5
	for _i in 200:
		BattleController.step(s)
	var hp := 0.0
	for e: Dictionary in s.enemies:
		if int(e["id"]) == id:
			hp = float(e["hp"])
	t.near(hp, float(def["hp"]), "★ 再生回得滿，而且封頂在最大血量（不會愈長愈多）", 0.01)

	# ② 反向對照：**不帶 regen 的敵人一點都不會回血**（不然上面那條可能是別的原因）。
	var plain := SessionState.new()
	plain.setup(MapsData.SHOAL)
	plain.phase = "wave"
	var pid := plain.add_enemy("drifter")
	for e: Dictionary in plain.enemies:
		if int(e["id"]) == pid:
			e["hp"] = 20.0
	for _i in 50:
		BattleController.step(plain)
	for e: Dictionary in plain.enemies:
		if int(e["id"]) == pid:
			t.near(float(e["hp"]), 20.0, "★ 反向對照：沒有 regen 的敵人不會自己長血")

	# ③ 比例不是絕對值：血量倍率翻倍，每秒回復量也跟著翻倍
	#    （不然第 30 波的它等於沒有這條規則）。
	var big := SessionState.new()
	big.setup(MapsData.SHOAL)
	big.hp_mult = 4.0
	var bid := big.add_enemy("mender")
	for e: Dictionary in big.enemies:
		if int(e["id"]) == bid:
			t.near(float(e["max_hp"]), float(def["hp"]) * 4.0, "★ 再生的上限跟著血量倍率長")


# ── ★ M3 第二批敵人的三條新規則（B3.2b、§7.5）────────────────────────
#
# 三條規則各對應玩家的**一個動詞**：走線／塔的組成／儲槽與優先權。
# 每一條都配一個**反向對照**——只驗「新的那一隻有這個效果」，
# 證不出效果來自那條規則而不是來自它的血量或速度（B3.2 的同一條紀律）。

## ★ 蝕線：對**導管** ×3、對**節點** ×0.5。
##
## ⚠ 這條規則刻意**不動半徑**。`Tide.BLAST` 是幾何，而橋免疫（跨越點 ±1 格）
## 正是照半徑 1 推導出來的——改半徑會把「橋上導管不受攻擊」挖空（§7.5 記了
## 為什麼第一版的第三隻在規格階段就被否決）。這裡順便把那條不變量釘住。
func _rustsurge_eats_lines(t: T) -> void:
	var lost := {}
	for type: String in ["drifter", "rustsurge"]:
		var s := _session()
		# ⚠ 淺灘的路徑走 y=4。第一版把建築擺在 y=8／11，敵人一格都碰不到，
		#   而症狀是「對照組沒挨打」——不是新規則錯，是測試佈局錯。
		#   兩座中繼夾著敵人那一格：節點 (15,5) 與整條導管都在它的九格內。
		BuildController.place(s, "relay", Vector2i(15, 5))
		BuildController.place(s, "relay", Vector2i(17, 5))
		BuildController.lay_conduit(s, Vector2i(15, 5), Vector2i(17, 5))
		_spawn_at(s, type, 16.0)
		var wire0 := float((s.conduits[0] as Dictionary)["hp"])
		var node0 := float(s.node_at(Vector2i(15, 5))["hp"])
		for _i in 10:
			BattleController.step(s)
		lost[type] = Vector2(
			wire0 - float((s.conduits[0] as Dictionary)["hp"]),
			node0 - float(s.node_at(Vector2i(15, 5))["hp"])
		)
	var d: Vector2 = lost["drifter"]
	var r: Vector2 = lost["rustsurge"]
	t.ok(d.x > 0.0 and d.y > 0.0, "對照組：漂蟲兩者都啃得到（不然下面兩條無意義）")
	t.near(d.x, d.y, "★ 反向對照：漂蟲對導管與節點一視同仁（前六隻都是這樣）", 0.01)
	# 每秒傷害 ＝ dmg × 係數。用比值不用絕對值：日後調 `dmg` 這條斷言仍然對。
	var base := float(Enemies.of("rustsurge")["dmg"]) / float(Enemies.of("drifter")["dmg"])
	t.near(r.x / d.x, base * 3.0, "★★ 蝕線：對導管 ×3", 0.02)
	t.near(r.y / d.y, base * 0.5, "★★ 蝕線：對節點 ×0.5", 0.02)
	t.ok(r.x > r.y * 5.0, "★ 它是一隻咬線的東西，不是一隻比較會啃建築的東西")


## ★ 蝕線不得動搖橋免疫。**這條是設計紅線的斷言化**：
## 「橋是架高的 → 橋上導管不受攻擊 → 玩家可規劃的安全動線」（§3.5）。
## 一隻對導管 ×3 的敵人如果連橋上那段都咬得動，橋就從「答案」變回「限制」。
func _bridges_still_safe_from_rust(t: T) -> void:
	for type: String in ["drifter", "rustsurge"]:
		var s := _session()
		var crossings: Dictionary = s.sets["crossings"]
		t.ok(not crossings.is_empty(), "淺灘圖有橋（不然這條測試什麼都沒驗）")
		var bridge: Vector2i = Vector2i.ZERO
		for c: Variant in crossings:
			bridge = c
			break
		# 一條**只走橋**的導管：兩端各在路徑兩側一格，中間壓在橋上。
		t.eq(BuildController.place(s, "relay", bridge + Vector2i(0, -1)), Build.OK,
			"%s：橋北端的中繼蓋得起來" % type)
		t.eq(BuildController.place(s, "relay", bridge + Vector2i(0, 1)), Build.OK,
			"%s：橋南端的中繼蓋得起來" % type)
		var ok := BuildController.lay_conduit(
			s, bridge + Vector2i(0, -1), bridge + Vector2i(0, 1)
		)
		t.eq(ok, Build.OK, "%s：橋上那條導管蓋得起來" % type)
		var wi: int = s.conduits.size() - 1
		var hp0 := float((s.conduits[wi] as Dictionary)["hp"])
		# 敵人正好站在橋那一格上——沒有比這更近的了。
		var at := -1.0
		for i in s.path.size():
			if s.path[i] == bridge:
				at = float(i)
		t.ok(at >= 0.0, "橋在路徑上（免疫的定義就是從這裡來的）")
		_spawn_at(s, type, at)
		for _i in 10:
			BattleController.step(s)
		t.near(float((s.conduits[wi] as Dictionary)["hp"]), hp0,
			"★★ %s 站在橋上啃 1 秒，橋上導管一滴血都沒掉" % type, 0.001)


## ★ 庇護：相鄰同伴護甲 +6，而**它不加給自己**。
## 剋制它的是潮鳴的破甲——那個欄位從 M0 就在表上，而在此之前全場只有甲殼
## 一隻吃得到（和「迅捷」在 B3.2 之前的處境一模一樣）。
func _bulwark_shields_its_neighbours(t: T) -> void:
	var raw := 20.0
	var drifter := Enemies.of("drifter")
	var bulwark := Enemies.of("bulwark")
	# 純函式那一層：兩隻並肩 vs 隔開。
	var side_by_side := Combat.guard_armor(
		[{"type": "bulwark"}, {"type": "drifter"}],
		[Vector2i(10, 10), Vector2i(11, 10)]
	)
	t.near(side_by_side[1], 6.0, "★★ 站在殼衛旁邊的漂蟲拿到 +6 護甲")
	t.near(side_by_side[0], 0.0, "★★ 殼衛**不罩自己**（不然它只是一個走路的護甲數字）")
	var far := Combat.guard_armor(
		[{"type": "bulwark"}, {"type": "drifter"}],
		[Vector2i(10, 10), Vector2i(13, 10)]
	)
	t.near(far[1], 0.0, "★ 反向對照：隔三格就罩不到（範圍是相鄰 1 格）")
	var pair := Combat.guard_armor(
		[{"type": "bulwark"}, {"type": "bulwark"}],
		[Vector2i(10, 10), Vector2i(11, 10)]
	)
	t.near(pair[0], 6.0, "★ 兩隻殼衛並肩＝互相罩（4 自己的 ＋ 6 借來的 ＝ 10）")

	# 傷害那一層：+6 真的吃到物理傷害上。
	t.near(Combat.hit_damage(raw, "physical", drifter, 0.0, 0.0), raw,
		"對照：沒被罩的漂蟲照原樣吃滿")
	t.near(Combat.hit_damage(raw, "physical", drifter, 0.0, 6.0), raw - 6.0,
		"★★ 被罩住的漂蟲吃到的傷害少 6（護甲是減法）")
	# ★ 破甲是解答。0.25 破甲 → 6 點只剩 4.5。
	t.near(Combat.hit_damage(raw, "physical", drifter, 0.25, 6.0), raw - 4.5,
		"★★ 潮鳴的破甲砍得動借來的甲——這是它的剋制手段")
	# 自己的甲與借來的甲**一起**被破甲砍，不是分開算。
	t.near(Combat.hit_damage(raw, "physical", bulwark, 0.5, 6.0), raw - 5.0,
		"★ 自己的 4 ＋ 借來的 6 先相加、再一起被破甲砍")
	# 屏障那一路不受影響：護甲吃物理，屏障吃能量，剋制表不得被壓平。
	t.near(Combat.hit_damage(raw, "energy", drifter, 0.0, 6.0), raw,
		"★ 庇護不碰能量傷害（護甲是減法、屏障是百分比，兩條路各走各的）")


## ★ 汲取：3 格內的塔交戰耗能 ×1.5。
##
## 它擋掉的是「峰值電力算得準」——玩家在準備期就能把整條防線的峰值加總出來，
## 而那個數字到此為止在戰鬥期永遠成立。答案是儲槽與優先權滑桿。
func _drainer_breaks_the_peak_budget(t: T) -> void:
	var nodes: Array = [
		{"id": 1, "type": "anchor", "cell": Vector2i(10, 10)},
		{"id": 2, "type": "anchor", "cell": Vector2i(20, 10)},
		{"id": 3, "type": "extractor", "cell": Vector2i(11, 10)},
	]
	var m := Combat.drain_mult(nodes, [{"type": "drainer"}], [Vector2i(12, 10)])
	t.near(float(m.get(1, 1.0)), 1.5, "★★ 兩格外的塔被汲到（範圍 3 格）")
	t.ok(not m.has(2), "★ 反向對照：八格外的塔沒事——**而且不在字典裡**")
	t.ok(not m.has(3), "★ 只汲塔。採集器沒有交戰耗能，乘上去是空操作")
	# 多隻不疊乘，取最強（`auras()` 的同一條——疊加會讓它變成堆量）。
	var two := Combat.drain_mult(
		nodes, [{"type": "drainer"}, {"type": "drainer"}],
		[Vector2i(12, 10), Vector2i(11, 11)]
	)
	t.near(float(two.get(1, 1.0)), 1.5, "★★ 兩隻汲潮不疊乘（1.5 不是 2.25）")
	t.ok(Combat.drain_mult(nodes, [{"type": "drifter"}], [Vector2i(11, 10)]).is_empty(),
		"★ 反向對照：不會汲的敵人一格都不進字典")

	# 局面那一層：同一座塔、同一個位置，只換旁邊那隻敵人的種類。
	var need := {}
	for type: String in ["drifter", "drainer"]:
		var s := _session()
		_power_plant(s)
		BuildController.place(s, "anchor", Vector2i(16, 5))
		BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 5))
		_spawn_at(s, type, 16.0)
		BattleController.step(s)
		# ⚠ `power_demand` 是一個 **float**，不是分項字典。第一版寫成
		#   `(... as Dictionary).get("tower")` → 執行期 cast 錯 → **整支函式中止**，
		#   而下面三條斷言一條都沒跑，測試卻照樣全綠（RG-164 的形狀第五次）。
		need[type] = float(s.rates["power_demand"])
	t.ok(float(need["drifter"]) > 0.0, "對照組：那座錨真的在交戰（不然下面兩條無意義）")
	# `power_demand` 是**整張網**的需求（含採集器與發電機的待機），所以驗的是
	# **差額**：多出來的必須恰好是那座錨交戰耗能的 0.5 倍，一滴不多。
	# 直接除總量的話，這條斷言會隨著測試佈局多接一台機器而漂掉。
	var engage := float(NodeDefs.of("anchor")["engage_power"])
	t.near(float(need["drainer"]) - float(need["drifter"]), engage * 0.5,
		"★★ 汲潮站在旁邊 → 多出來的需求恰好是那座錨交戰耗能的一半", 0.02)
	t.ok(float(need["drainer"]) > float(need["drifter"]),
		"★ 峰值電力在戰鬥期不再是準備期算得出來的那個數字")


## ★★ 每一隻敵人在畫面上都認得出來（B3.2b）。
##
## 這條守的是本案最貴的一課（RG-145／B2.4 的隱形塔）：**斷言從來不看畫面**。
## 1290 條全綠而三隻塔是隱形的，而使用者是用眼睛發現的。
##
## 做法是把 `_draw_enemies()` **實際讀的那幾個欄位**組成一個簽章，斷言九隻互不相同。
## 它證不出「好不好認」（那是人眼判的），但證得出「兩隻在程式眼裡一模一樣」
## ——而那是隱形的必要條件。日後加第十隻忘了給它視覺通道，這一條會紅。
func _every_enemy_looks_different(t: T) -> void:
	# `SWIFT_SPEED` 住在畫面層（`Battle.gd`），而「快不快」這個視覺分支讀的就是它
	# ——抄一份數字進來的話，改門檻時這條斷言會安靜地變成量別的東西。
	var Battle := load("res://scripts/screens/Battle.gd")
	var swift_gate: float = Battle.SWIFT_SPEED
	var seen: Dictionary = {}
	for type: String in Enemies.DEFS:
		var d := Enemies.of(type)
		var sig := "r%.1f|armor%s|fast%s|swift%s|regen%s|bite%s|drain%s" % [
			float(d.get("radius", 9.0)),
			float(d.get("armor", 0.0)) > 0.0,
			float(d.get("speed", 1.0)) > swift_gate,
			bool(d.get("swift", false)),
			float(d.get("regen", 0.0)) > 0.0,
			float(d.get("wire_mult", 1.0)) > 1.0,
			float(d.get("drain_mult", 1.0)) > 1.0,
		]
		t.ok(not seen.has(sig), "★★ %s 和「%s」在畫面上分得開" % [
			String(d["name"]), String(seen.get(sig, "（沒有人和它撞）"))
		])
		seen[sig] = String(d["name"])
	t.eq(seen.size(), Enemies.DEFS.size(), "★★ %d 隻敵人 = %d 個互不相同的外觀" % [
		Enemies.DEFS.size(), seen.size()
	])
