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
const Enemies := preload("res://data/Enemies.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("combat_test")
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
	_priority_decides_who_starves(t)
	_breaker_splash(t)
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
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 6))
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
	BuildController.lay_conduit(busy, Vector2i(16, 11), Vector2i(16, 7))
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
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 6))
	BuildController.upgrade(s, 1)
	BuildController.upgrade(s, 1)                     # 幹線 cap 22：瓶頸不在線上
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
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 7))
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
	var far := _kill_beside_reclaimer(Vector2i(16, 14))   # 離路徑 10 格，射程 5
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
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 7))
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
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 6))   # 索引 1：幹線
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
	BuildController.place(s, "relay", Vector2i(16, 9))
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(16, 9))
	BuildController.place(s, "reclaimer", cell)
	BuildController.lay_conduit(s, Vector2i(16, 9), cell)
	BuildController.place(s, "anchor", Vector2i(14, 7))
	BuildController.lay_conduit(s, Vector2i(16, 9), Vector2i(14, 7))
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
