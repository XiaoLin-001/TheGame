extends RefCounted
## 每 tick 的解算迴圈（`30_TECH_DESIGN.md` §2.4、§2.5）。
##
## **固定時間步 0.1 秒，模擬不使用 `delta`。** 畫面掉幀時補跑 tick，
## 不改變模擬結果——這是確定性的另一半（另一半是 `sim/` 的純函式）。
##
## 解算順序是有意義的：**先礦砂、後能量**。發電機的能量產出要乘上它自己的
## 礦砂滿足率（供不應求按比例降速，不停機，`10_GDD.md` §3.1）。

const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Score := preload("res://scripts/sim/Score.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Enemies := preload("res://data/Enemies.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")

const Clock := preload("res://scripts/sim/Clock.gd")
## 固定時間步。**值的唯一來源是 `sim/Clock.gd`**（B1.9）——這裡只是別名，
## 讓呼叫端維持讀得懂的 `BattleController.TICK`。
const TICK := Clock.TICK
## 低於這個滿足率就掛 `缺料` 徽章。與導管的飢餓變色同一個門檻，
## 兩個編碼講的是同一件事，用不同門檻只會讓玩家以為它們無關。
const STARVED_BELOW := 0.95
## 高於這個量（每 tick）才算 `滿溢`。浮點尾數不是塞車。
const OVERFLOW_ABOVE := 0.001

## `Tide.in_blast` 的九格（Chebyshev ≤ 1）。**寫成常數不是為了好看**：
## 陣列字面量在迴圈裡每次都會配一個新陣列，而這裡是每隻敵人每 tick 跑一遍。
const BLAST_CELLS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


## 推進一個 tick。就地變更 `s`。
##
## **順序是有意義的**：先判交戰、再解電網、最後才開火。
## 交戰狀態是純幾何（射程內有沒有敵人），與電無關；電網解出來的滿足率才決定
## 射速與光環強度。倒過來做的話塔會拿上一 tick 的電開這一 tick 的火，
## 「電不夠射速就慢」這條規則會延遲一格才生效，玩家讀不出因果。
static func step(s: RefCounted) -> void:
	if s.phase == "lost" or s.phase == "won":
		return
	s.tick_count += 1
	s.phase_time += TICK
	# 碎片的壽命在這裡遞減，**不放進 `_fire()`**：那支函式在「場上沒有敵人」
	# 時會提早 return，而最後一隻敵人死掉的那一 tick 正好就是沒有敵人的那一 tick
	# ——碎片會卡在畫面上不消失。
	for i in range(s.shields.size() - 1, -1, -1):
		var sh: Dictionary = s.shields[i]
		sh["ttl"] = int(sh["ttl"]) - 1
		if int(sh["ttl"]) <= 0:
			s.shields.remove_at(i)
	for i in range(s.bursts.size() - 1, -1, -1):
		var b: Dictionary = s.bursts[i]
		b["ttl"] = int(b["ttl"]) - 1
		if int(b["ttl"]) <= 0:
			s.bursts.remove_at(i)
	_phase(s)

	var cells := Combat.enemy_cells(s.enemies, s.path)
	var engaged := Combat.engaged(s.nodes, cells)

	# 邊只建一次：兩個資源網與回寫共用同一份，索引順序才對得起來。
	var edges := _edges(s)
	# ★ 拓樸也只建一次（B2.1e）：三張網的圖逐位元相同，只有供需不同。
	#   三次各建一遍等於把 CSR、孿生邊、生成森林都算三遍。
	var topo := FlowNetwork.prepare(s.nodes, edges)
	var ore_res := _solve_ore(s, edges, topo)
	var power_res := _solve_power(s, edges, ore_res, engaged, topo)
	# 合金最後：熔爐的產出要乘上它**礦砂與能量兩個滿足率中較低的那一個**（§3.1）。
	var alloy_res := _solve_alloy(s, edges, ore_res, power_res, topo)
	var sat: Dictionary = power_res["satisfaction"]

	# 光環算一次就好，推進與開火共用：兩者相隔一個 tick 的移動量，
	# 破甲比例不會因此改變，多算一次只是多跑一趟 塔×敵人。
	var aura := Combat.auras(s.nodes, cells, sat)
	_advance_and_damage(s, aura)
	_fire(s, engaged, sat, aura)
	_end_of_wave(s)
	_write_rates(s, edges, ore_res, power_res, alloy_res, engaged)


# ── 敵潮：時間流 ＋ walk-by 破壞 ──────────────────────────────────────

static func _phase(s: RefCounted) -> void:
	if s.phase == "prep":
		if s.phase_time >= s.prep_time():
			start_wave(s)
	elif s.phase == "wave":
		_spawn_due(s)


## 一波「結束」＝ 沒有還在路上的敵人，也沒有還沒出場的。
## 走到核心的會留下來繼續啃——**它們是駐足，不是消失**，所以推進與開火
## 每個 tick 都跑，不看階段。（B0.4 把它們關在 `wave` 分支裡，導致殘敵在
## 準備期停手又停挨打，「只有核心會讓它們駐足」等於只成立半個階段。）
static func _end_of_wave(s: RefCounted) -> void:
	if s.phase != "wave":
		return
	if not s.spawn_queue.is_empty() or _anyone_walking(s):
		return
	# 波次表跑完＝這一關通關。沒有這個分支的話 `start_wave` 會一直排出空波次，
	# 局面永遠停在「準備期倒數→瞬間結束」的空轉，局末結算永遠等不到。
	#
	# ★ 無盡沒有波次表也沒有「通關」（§7.10）——它只會輸。這一句就是分岔點：
	# 波次由公式長出來，所以 `waves_of()` 恆為空，不擋掉就每一波都判通關。
	if not bool(s.map.get("endless", false)) and s.wave_index >= Maps.waves_of(s.map).size():
		# 但駐足在核心的殘敵還在啃就還沒結束——不是它們死，就是核心死。
		if s.enemies.is_empty():
			s.phase = "won"
		return
	s.phase = "prep"
	s.phase_time = 0.0
	s.speed_mult = 1


## 開打。準備期可以提前按（`10_GDD.md` §3.4 提前召喚）。
##
## ★ 倍率**在這裡算一次就鎖給這一波**：開打後準備期倒數就停了，
## 事後再算一律拿到 1.0。鎖住的另一個好處是玩家按下去當場就知道賭到多少。
static func start_wave(s: RefCounted) -> void:
	if s.phase != "prep":
		return
	s.wave_bonus = Score.summon_bonus(maxf(0.0, s.prep_time() - s.phase_time), s.prep_time())
	s.bonus_data += Score.summon_data_bonus(s.wave_bonus)
	if bool(s.map.get("endless", false)):
		# `wave_index` 是 0-based，§7.10 的公式是 1-based。
		var w: int = int(s.wave_index) + 1
		s.spawn_queue = Enemies.endless_schedule(int(s.map.get("seed", 0)), w)
		s.hp_mult = Enemies.endless_hp_mult(w)
	else:
		s.spawn_queue = Enemies.schedule(Maps.waves_of(s.map), s.wave_index)
	s.wave_index += 1
	s.phase = "wave"
	s.phase_time = 0.0
	s.speed_mult = 1  # 戰鬥期不可加速也不可減速（`10_GDD.md` B5）


static func _spawn_due(s: RefCounted) -> void:
	while not s.spawn_queue.is_empty() and float(s.spawn_queue[0]["at"]) <= s.phase_time:
		s.add_enemy(String(s.spawn_queue[0]["type"]))
		s.spawn_queue.remove_at(0)


static func _anyone_walking(s: RefCounted) -> bool:
	for e: Dictionary in s.enemies:
		if not Tide.at_core(float(e["progress"]), s.path.size()):
			return true
	return false


## ★ walk-by：先打相鄰 1 格內的建築，然後**繼續走**。
## 推進與破壞完全不互相影響——沒有任何建築能改變一隻敵人的到達時間。
##
## `aura` 與 `s.enemies` 同索引，`x` 是減速比例（潮鳴，§7.4）。
## 減速只改速度，**不會改成 0**：光環強度上限 40%，永遠停不下來（RG-17）。
static func _advance_and_damage(s: RefCounted, aura: Array = []) -> void:
	var crossings: Dictionary = s.sets["crossings"]
	# ★ 格索引（B2.1e）。`in_blast` 是 Chebyshev ≤ 1 ＝ 剛好九格，所以「誰挨打」
	#   可以用查表回答，不必每隻敵人重掃一遍全部節點與導管。
	#
	#   舊寫法是 `O(敵人 × (節點 + 導管 × 每條導管的格數))`，而且每一對
	#   （敵人, 導管）都要重算一次 `immune_indices()`（那還會配一個字典）。
	#   一屏地圖上量不出來；64×40 的無盡圖上它是單 tick 最大的一筆開銷
	#   ——198 節點／357 導管時 17.2 ms，佔整個 tick 的六成。
	#
	#   **這是等價改寫，不是新規則**：同一個 `in_blast`、同一份免疫格，
	#   而且每個目標挨打的順序仍然是敵人陣列的順序（逐位元相同）。
	var node_at_cell: Dictionary = {}
	var cond_at_cell: Dictionary = {}
	var hit_by := PackedInt32Array()
	if not s.enemies.is_empty():
		for n: Dictionary in s.nodes:
			node_at_cell[n["cell"]] = n
		for ci in s.conduits.size():
			var c: Dictionary = s.conduits[ci]
			var cells: Array = c["cells"]
			var immune := Tide.immune_indices(cells, crossings)
			for k in cells.size():
				if immune.has(k):
					continue
				var cc: Vector2i = cells[k]
				if not cond_at_cell.has(cc):
					cond_at_cell[cc] = [] as Array[int]
				cond_at_cell[cc].append(ci)
		hit_by.resize(s.conduits.size())
		hit_by.fill(-1)

	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var def := Enemies.of(String(e["type"]))
		var cell := Tide.cell_of(s.path, float(e["progress"]))
		# 難度層 2+ 讓敵人啃得更快（`data/Difficulty.gd`）。乘在**傷害**上而不是
		# 半徑或速度上：那兩個會改「誰挨得到打」，而規則卡上寫的是「破壞建築 ×N」。
		var dmg := float(def.get("dmg", 0.0)) * TICK * float(s.mods["enemy_damage_mult"])

		for off: Vector2i in BLAST_CELLS:
			var at := cell + off
			var n: Dictionary = node_at_cell.get(at, {})
			if not n.is_empty():
				n["hp"] = float(n["hp"]) - dmg
			# 一條導管可能有好幾格都在同一隻敵人的半徑內——**只能挨一次**
			# （舊寫法的 `conduit_hit()` 命中就 return，語意在此以戳記保留）。
			for ci: int in cond_at_cell.get(at, []):
				if hit_by[ci] == i:
					continue
				hit_by[ci] = i
				var c: Dictionary = s.conduits[ci]
				c["hp"] = float(c["hp"]) - dmg

		var slow := 0.0 if i >= aura.size() else (aura[i] as Vector2).x
		e["progress"] = Tide.advance(
			float(e["progress"]), float(def.get("speed", 1.0)) * (1.0 - slow), s.path.size()
		)

	_clear_wreckage(s)


# ── 開火與結算（`10_GDD.md` §3.3、§7.4）─────────────────────────────

## 塔開火。**只有本 tick 付了交戰耗能的塔才會開火**——付錢與開火是同一件事，
## 分開就會出現「待機的塔白打一發」的漏洞。
## 開火線留幾個 tick 才看得見：稜鏡 0.5 發/秒，只留一個 tick 的話
## 60Hz 下大約每 20 幀才閃一次，玩家看到的是一座沉默的塔。
const SHOT_TTL := 3

static func _fire(s: RefCounted, engaged: Dictionary, sat: Dictionary, aura: Array) -> void:
	for i in range(s.shots.size() - 1, -1, -1):
		var sh: Dictionary = s.shots[i]
		sh["ttl"] = int(sh["ttl"]) - 1
		if int(sh["ttl"]) <= 0:
			s.shots.remove_at(i)
	if s.enemies.is_empty():
		return
	# 敵人已經走過了，射擊看的是**現在**的位置。
	var cells := Combat.enemy_cells(s.enemies, s.path)
	var damage: Array[float] = []
	damage.resize(s.enemies.size())
	damage.fill(0.0)

	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		var rof := float(def.get("rof", 0.0))
		if not def.get("tower", false) or rof <= 0.0:
			continue
		var busy: bool = engaged.get(int(n["id"]), false)
		var k := clampf(float(sat.get(int(n["id"]), 1.0)), 0.0, 1.0) if busy else 0.0
		# 滿足率直接乘進累加器 → 射速線性下降，不停火（§3.1）。
		var step_res := Combat.shots(float(n["cd"]), rof, k)
		n["cd"] = step_res["cd"]
		var count := int(step_res["n"])
		if count <= 0:
			continue

		var r := float(def.get("range", 0.0))
		var targets: Array[int] = []
		# 濺射的**圓心**（純渲染）。`-1` ＝ 這一發不濺射。
		var splash_at := Vector2i(-1, -1)
		if def.get("pierce", false):
			targets = Combat.pierce_indices(n["cell"], cells, r)
		else:
			var t := Combat.front_most(Combat.in_range_indices(n["cell"], cells, r), s.enemies)
			if t >= 0:
				# ★ 濺射（碎浪，§7.4）：主目標仍是「最前」那一隻，濺射以**它所在的
				#   格**為圓心往外找。不寫新幾何——「這個圓內有誰」就是射程判定本身。
				# 寫成 if/else 而不是三元式：`[t]` 在三元式裡是 untyped `Array`，
				# 指派給 `Array[int]` 會在**執行期**丟型別錯誤（塔從此一發不發）。
				var splash := float(def.get("splash", 0.0))
				if splash > 0.0:
					targets = Combat.in_range_indices(cells[t], cells, splash)
					splash_at = cells[t]
				else:
					targets = [t]
		for i: int in targets:
			var edef := Enemies.of(String((s.enemies[i] as Dictionary)["type"]))
			# 科技「校準」（§7.8）乘在**原始傷害**上，在減傷／破甲之前——
			# 乘在最後結果上會讓它對高護甲敵人的效益憑空變小，而玩家買的是
			# 「塔傷害 +6%」，不是「對軟目標 +6%」。
			var raw := float(def.get("dmg", 0.0)) * float(count) * float(s.mods["damage_mult"])
			var dealt := Combat.hit_damage(
				raw, String(def.get("dmg_type", "physical")), edef, aura[i].y
			)
			damage[i] += dealt
			# ★ 屏障擋格（B2.1d，使用者指定「類似盾牌隔檔」）。**純渲染**：
			#   `shields` 和 `shots`／`bursts` 一樣不進 `state_hash()`。
			#   只有**能量傷害被屏障吃掉一截**時才出現——護甲（減法）不畫，
			#   它已經有六邊形＋厚邊在講「硬」（§1.7）。
			#   屏障在此之前**完全沒有視覺通道**：玩家只看得出熾泳「快」，
			#   看不出自己的能量傷害被砍掉四成。
			if dealt < raw - 0.001 and String(def.get("dmg_type", "physical")) == "energy":
				_shield(s, cells[i], (raw - dealt) / maxf(raw, 0.001))
			# `by` 是**純渲染**欄位（`shots` 不進 `state_hash()`）：畫的時候要知道
			# 這一發是誰開的，才畫得出四種開火形態（`20_ART_DIRECTION.md` §1.7）。
			# 形態本身由 `NodeDefs` 既有的 `dmg_type`／`pierce`／`splash`／`reclaim`
			# 推導，不新增美術欄位。
			var rec := {
				"from": n["cell"], "to": cells[i], "ttl": SHOT_TTL, "by": String(n["type"]),
			}
			# ★ 濺射環**只掛在第一發上**。碎浪是「一發濺射打中 N 隻」，不是 N 發：
			#   每隻各畫一圈會疊出 N 個同心圓，既吵又把機制講錯（實看抓到，B1.6.3）。
			if splash_at.x >= 0:
				rec["splash_at"] = splash_at
				splash_at = Vector2i(-1, -1)
			# ⚠ **這一行必須在 `if` 外面。** B1.6.3 誤縮排到 `if` 裡面，於是
			#   只有濺射（碎浪）會留下 `shots` 記錄——其餘四座塔的開火形態
			#   （稜鏡光束、實體彈、回收珠）**整整一批都沒有畫出來過**，
			#   而所有測試都是綠的，因為 `shots` 是純渲染、不進 `state_hash()`。
			#   回歸斷言在 `hud_test`：非濺射塔開火後 `shots` 不得為空。
			s.shots.append(rec)

	# **先把全部傷害算完再結算死亡**：邊打邊結算的話，同一 tick 內誰拿到擊殺
	# 會由節點在陣列裡的順序決定——那是把 id 順序偷渡成遊戲規則。
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		e["hp"] = float(e["hp"]) - damage[i]
	for i in range(s.enemies.size() - 1, -1, -1):
		if float((s.enemies[i] as Dictionary)["hp"]) > 0.0:
			continue
		# ★ 碎片爆（B1.6）：混沌消散。種子用敵人 id → 同一隻永遠炸成同一個樣子。
		_burst(s, Vector2(cells[i]), "chaos", int((s.enemies[i] as Dictionary)["id"]))
		_on_kill(s, float(Enemies.of(String(s.enemies[i]["type"])).get("value", 0.0)), cells[i])
		s.enemies.remove_at(i)


## ★ 碎片爆（B1.6，`20_ART_DIRECTION.md` §161 反模式：「爆炸不用 200 顆粒子。
## 用 3–5 個幾何碎片＋一次縮放閃光」）。純渲染，不進 `state_hash()`。
##
## `Motion.reduce` 為真時 `ticks()` 回 0 → 這裡直接不生成，「所有動效都可跳過」
## （§4.4）在源頭就成立，不必讓畫面層再判一次。
static func _burst(s: RefCounted, at: Vector2, kind: String, seed_id: int) -> void:
	var life := Motion.ticks(Motion.BASE)
	if life <= 0:
		return
	s.bursts.append({"at": at, "kind": kind, "seed": seed_id, "life": life, "ttl": life})


## ★ 屏障擋格的渲染記錄（B2.1d）。同一隻敵人同一 tick 只留一筆——
## 一發打中 N 隻是 N 筆（各自在自己身上擋），但一隻被 N 座塔打中只畫一次，
## 否則同一個位置會疊出 N 層弧線（和 B1.6.3 濺射環疊 N 圈是同一個錯）。
static func _shield(s: RefCounted, at: Vector2i, frac: float) -> void:
	var life := Motion.ticks(Motion.BASE)
	if life <= 0:
		return
	for r: Dictionary in s.shields:
		if r["at"] == at:
			return
	s.shields.append({"at": at, "frac": frac, "life": life, "ttl": life})


## 一次擊殺的兩種回收，**並存**（§7.4）。
static func _on_kill(s: RefCounted, value: float, at: Vector2i) -> void:
	s.kills += 1
	# ① 全域擊殺回收：任何塔擊殺 → 價值 25% 的礦砂，**直接入帳**。
	#    它是擊殺處撿到的殘骸，不是採出來要運回核心的礦（§3.3）。
	# 提前召喚的倍率乘在**掉落**上（§3.4「該波掉落的礦砂與研究數據按倍率增加」）。
	var salvage: float = Combat.salvage_ore(value) * s.wave_bonus
	s.ore += salvage
	s.salvage_total += salvage
	# ② 回收者：射程內**任何**死亡（不限自己擊殺）→ 價值 60% × 匯率 5 的能量。
	#    進的是它自己的緩衝，之後受自己那條導管的 cap 限速注入（§7.4）。
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("reclaim"):
			continue
		if not Combat.in_range(n["cell"], at, float(def.get("range", 0.0))):
			continue
		var gain := Combat.reclaim_power(value, float(def["reclaim"]))
		var before := float(n["buffer"])
		n["buffer"] = minf(before + gain, float(def.get("reclaim_buffer", 0.0)))
		# 累計只記**真的進得了緩衝**的部分：溢流掉的電從來沒進過電網，
		# 把它算進「已回收」會讓頂欄的數字比實際好看。
		s.reclaimed_total += float(n["buffer"]) - before


## 打掉的東西要真的消失——**產能中斷是玩家該看到的後果**，
## 留著一條 0 血的線只會讓瓶頸圖說謊。
static func _clear_wreckage(s: RefCounted) -> void:
	if s.core_hp() <= 0.0:
		s.phase = "lost"
		return
	for i in range(s.nodes.size() - 1, -1, -1):
		var n: Dictionary = s.nodes[i]
		if float(n["hp"]) > 0.0 or int(n["id"]) == s.core_id:
			continue
		# ★ 碎片爆（B1.6）：**秩序破裂**。玩家的東西被啃掉了，這件事之前
		#   在畫面上完全沒有表現——節點就這樣消失，產能跟著掉，而玩家不知道
		#   剛剛發生了什麼。這是「你的生產線就是你的防線」最該被看見的一刻。
		_burst(s, Vector2(n["cell"]), "order", int(n["id"]))
		s.remove_node_at(n["cell"])
	for i in range(s.conduits.size() - 1, -1, -1):
		var c: Dictionary = s.conduits[i]
		if float(c["hp"]) > 0.0:
			continue
		# 導管斷在中點：整條線消失，爆在哪裡都不精確，中點最不誤導。
		_burst(s, (Vector2(c["a"]) + Vector2(c["b"])) * 0.5, "order", int(c["id"]))
		s.conduits.remove_at(i)


# ── 礦砂網 ────────────────────────────────────────────────────────────

static func _solve_ore(s: RefCounted, edges: Array, topo: Dictionary = {}) -> Dictionary:
	var nodes: Array = []
	var supply_total := 0.0
	var demand_total := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		# 科技「採集精煉」只加採集器（§7.8）。用 `ore_out > 0` 當條件會在日後
		# 出現第二種產礦節點時靜靜地一起加上去——那不是這個科技買的東西。
		var out_bonus := float(s.mods["extractor_ore"]) if n["type"] == "extractor" else 0.0
		# ★ 等級軸的生產乘數（B2.7）。乘在**科技加成之後**：科技是「這座採集器
		#   每秒多挖 1」，等級是「我的整條生產線都好 8%」——後者該把前者也含進去。
		var supply := (float(def.get("ore_out", 0.0)) + out_bonus) * float(s.mods["produce_mult"]) * TICK
		var demand := float(def.get("ore_in", 0.0)) * TICK
		supply_total += supply
		demand_total += demand
		nodes.append(_sim_node(n, supply, demand))

	# ★ 核心只收剩下的（`10_GDD.md` §7.3）：燃料永遠優先於入帳。
	# 這讓「礦砂 ▲0/秒」變成一句完整的診斷——你採到的剛好被發電機吃光。
	for sn: Dictionary in nodes:
		if sn["id"] == s.core_id:
			sn["demand"] = maxf(0.0, supply_total - demand_total)

	return FlowNetwork.solve(nodes, edges, s.priorities, topo)


# ── 合金網（B1.1）─────────────────────────────────────────────────────

## 熔爐 → 核心。**沒有其他消費者**：合金是造價貨幣不是流量（§7.3）。
##
## 所以核心的 `demand` 就是全網供給。這與礦砂的「只收剩下的」是同一個式子，
## 只是減數為 0——特意用同一段程式碼寫，日後真的出現吃合金的節點時，
## 那個 `demand_total` 會自己開始起作用，不必回頭改語意。
static func _solve_alloy(
	s: RefCounted, edges: Array, ore_res: Dictionary, power_res: Dictionary,
	topo: Dictionary = {}
) -> Dictionary:
	var ore_sat: Dictionary = ore_res.get("satisfaction", {})
	var power_sat: Dictionary = power_res.get("satisfaction", {})
	var nodes: Array = []
	var supply_total := 0.0
	var demand_total := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		# ★ 取**較低**的那個滿足率：缺礦砂或缺電都會讓熔爐降速，而它不會
		#   因為兩樣都缺就降兩次——那會讓 50% 電 ＋ 50% 礦變成 25% 產出，
		#   比玩家從畫面上讀到的兩條線任何一條都糟，因果就斷了。
		var k := minf(float(ore_sat.get(n["id"], 1.0)), float(power_sat.get(n["id"], 1.0)))
		var supply := float(def.get("alloy_out", 0.0)) * float(s.mods["produce_mult"]) * TICK * k
		var demand := float(def.get("alloy_in", 0.0)) * TICK
		supply_total += supply
		demand_total += demand
		nodes.append(_sim_node(n, supply, demand))

	for sn: Dictionary in nodes:
		if sn["id"] == s.core_id:
			sn["demand"] = maxf(0.0, supply_total - demand_total)

	return FlowNetwork.solve(nodes, edges, s.priorities, topo)


# ── 能量網 ────────────────────────────────────────────────────────────

static func _solve_power(
	s: RefCounted, edges: Array, ore_res: Dictionary, engaged: Dictionary,
	topo: Dictionary = {}
) -> Dictionary:
	var sat: Dictionary = ore_res.get("satisfaction", {})
	var nodes: Array = []
	# 回收者本 tick 自己用掉的緩衝，解算後要從緩衝裡扣掉。
	var self_use: Dictionary = {}
	for n: Dictionary in s.nodes:
		var type := String(n["type"])
		var def := NodeDefs.of(type)
		# 發電機的產出 × 它自己的礦砂滿足率（按比例降速，不停機）。
		var supply := (float(def.get("power_out", 0.0)) * float(s.mods["produce_mult"])
			* TICK * float(sat.get(n["id"], 1.0)))
		var demand := float(def.get("power_in", 0.0)) * TICK
		# ★ 交戰耗能：**射程內有敵人才扣，待機 0**（§7.4）。全案的心臟就在這一行。
		if engaged.get(int(n["id"]), false):
			# 科技「能量效率」（§7.8）。**它作用在交戰耗能上，不是待機耗能**——
			# 待機早就是 0，乘在那上面是空操作（v0.3 定案第 ⑬ 條）。
			demand += float(def.get("engage_power", 0.0)) * float(s.mods["engage_mult"]) * TICK
		var sn := _sim_node(n, supply, demand)
		if type == "silo":
			# 儲槽是能量專用緩衝（§7.3）。charge 是**絕對量**，不乘 TICK；
			# 解算器拿它跟「每 tick 的 cap」比，兩邊都是同一 tick 的單位。
			sn["charge"] = float(n["charge"])
			sn["capacity"] = float(def.get("capacity", 0.0))
		elif def.has("reclaim"):
			# ★ 回收的能量經**自己那條導管**以 cap 限速注入（§7.4）——與儲槽同構。
			#   沒有全域能量池，回收來的電也不例外，否則等於在回收者身上偷開第二個水池。
			#   **不必先把它跟自己的交戰耗能相抵**：解算器讓每個節點先吸收自己手上的
			#   供給再往外送，所以「先供自己」是它本來就會做的事，滿足率也因此自動正確。
			var offer := minf(float(n["buffer"]), _out_cap(int(n["id"]), edges))
			self_use[int(n["id"])] = minf(offer, demand)
			sn["supply"] = float(sn["supply"]) + offer
		nodes.append(sn)

	var res := FlowNetwork.solve(nodes, edges, s.priorities, topo)

	# 回寫儲槽充能。解算器是純函式，狀態的變更在這一層。
	var deltas: Dictionary = res.get("charge_delta", {})
	for n: Dictionary in s.nodes:
		if n["type"] != "silo":
			continue
		var cap := float(NodeDefs.of("silo").get("capacity", 0.0))
		n["charge"] = clampf(float(n["charge"]) + float(deltas.get(n["id"], 0.0)), 0.0, cap)

	# 回收者：扣掉「自用 ＋ 真的送出去的」。推不出去的留在緩衝裡下一 tick 再試——
	# 這就是 cap 限速的具體長相。
	var sent: Dictionary = res.get("sent", {})
	for n: Dictionary in s.nodes:
		var nid := int(n["id"])
		if self_use.has(nid):
			n["buffer"] = maxf(
				0.0, float(n["buffer"]) - float(self_use[nid]) - float(sent.get(nid, 0.0))
			)
	return res


## 一個節點所有出邊的 cap 總和（每 tick 單位）。回收者能推出去的上限。
static func _out_cap(id: int, edges: Array) -> float:
	var total := 0.0
	for e: Dictionary in edges:
		if int(e.get("from", -1)) == id:
			total += float(e.get("cap", 0.0))
	return total


# ── 共用 ──────────────────────────────────────────────────────────────

static func _sim_node(n: Dictionary, supply: float, demand: float) -> Dictionary:
	return {
		"id": int(n["id"]),
		"type": String(n["type"]),
		"supply": supply,
		"demand": demand,
		"charge": 0.0,
		"capacity": 0.0,
	}


## 導管 → 有向邊。**每一條導管都展開成雙向**（`sim/FlowNetwork.gd` 收的是
## 有向邊，一條實體管線就是兩條方向相反的邊）。所有量換算成「每 tick」，含 cap。
##
## ── 為什麼不是有向（B0.5 修正）────────────────────────────────────
## B0.3–B0.4 只給一條邊，方向是 `a`→`b`，也就是**玩家先點哪個節點**。
## 那個方向在畫面上完全看不見，玩家也無從選擇，而 `Build.conduit_key()`
## 早就把 A→B 與 B→A 當成同一條線在擋重複——「點的順序」從來就不是規則。
##
## B0.5 才讓它現形：塔是末端消費者，而「先點塔、再點幹線」是最自然的手勢，
## 拉出來的線卻只能從塔往外送電。示範佈局裡有三座塔就這樣**永遠是 0 電**，
## 而畫面上那條線看起來一切正常。看不見、控制不了、又會靜靜毀掉佈局的東西
## 不是規則，是缺陷。
static func _edges(s: RefCounted) -> Array:
	# ★ 格索引（B2.1e）。`SessionState.node_at()` 是線性掃描，而這裡每條導管要查
	#   兩次 → `O(導管 × 節點)`。31×19 的無盡佈局（604 節點／1095 導管）光這一支
	#   就吃掉 25.8 ms，比整個解算器還貴。
	#   索引建在這裡而不是塞進 `SessionState`：那要多一套失效機制，而失效機制
	#   漏一個呼叫點的下場是「模擬拿到一份過期的網路」——比慢嚴重得多。
	var by_cell: Dictionary = {}
	for n: Dictionary in s.nodes:
		by_cell[n["cell"]] = n
	var edges: Array = []
	for c: Dictionary in s.conduits:
		var a: Dictionary = by_cell.get(c["a"], {})
		var b: Dictionary = by_cell.get(c["b"], {})
		if a.is_empty() or b.is_empty():
			continue
		var cap := Build.conduit_cap(int(c["level"]), float(s.mods["cap_bonus"])) * TICK
		# `dir` 只給回寫用：讓 `_write_rates()` 算得出**淨流向**（渲染層的流動珠
		# 要靠它決定珠子往哪邊跑）。解算器本身不看這個欄位。
		edges.append({
			"from": int(a["id"]), "to": int(b["id"]), "cap": cap, "conduit": c["id"], "dir": 1.0
		})
		edges.append({
			"from": int(b["id"]), "to": int(a["id"]), "cap": cap, "conduit": c["id"], "dir": -1.0
		})
	return edges


## 把解算結果換算成**單位/秒**寫進 `rates`，供渲染與頂欄讀取。
## 渲染層不做單位換算——它只讀這裡。
static func _write_rates(
	s: RefCounted, edges: Array, ore_res: Dictionary, power_res: Dictionary,
	alloy_res: Dictionary, engaged: Dictionary
) -> void:
	var per_sec := 1.0 / TICK
	var flows: Dictionary = {}
	# 每條導管的**淨流率**（`Vector3(礦砂, 能量, 合金)`，沿 a→b 為正）。線寬只要
	# 大小，流動珠還要方向與資源別——一條幹線上三者常常互相反向。
	var nets: Dictionary = {}
	for i in edges.size():
		var e: Dictionary = edges[i]
		var cid: int = int(e.get("conduit", -1))
		var ore_f := float((ore_res["flow"] as Array)[i])
		var pow_f := float((power_res["flow"] as Array)[i])
		var alloy_f := float((alloy_res["flow"] as Array)[i])
		var net: Vector3 = nets.get(cid, Vector3.ZERO)
		nets[cid] = net + Vector3(ore_f, pow_f, alloy_f) * float(e.get("dir", 1.0)) * per_sec
		# **取最大值，不是相加**：三種資源各跑一次解算、各自吃滿同一個 cap
		# （每種資源獨立計容量）。相加會讓一條同時走礦與電的幹線報出超過 cap
		# 的流量，於是渲染層把一條還有餘裕的線畫成滿載——瓶頸圖直接說謊（R-3）。
		# 三者共用同一個 cap 數值，所以「最大流率 ÷ cap」正好等於最大飽和度。
		flows[cid] = maxf(
			float(flows.get(cid, 0.0)), maxf(alloy_f, maxf(ore_f, pow_f)) * per_sec
		)

	var charge := 0.0
	var capacity := 0.0
	for n: Dictionary in s.nodes:
		if n["type"] == "silo":
			charge += float(n["charge"])
			capacity += float(NodeDefs.of("silo").get("capacity", 0.0))

	var sat: Dictionary = {}
	for id: int in (ore_res["satisfaction"] as Dictionary):
		sat[id] = minf(
			float(ore_res["satisfaction"][id]), float(power_res["satisfaction"].get(id, 1.0))
		)

	s.rates["ore_in"] = float((ore_res["received"] as Dictionary).get(s.core_id, 0.0)) * per_sec
	s.rates["alloy_in"] = float((alloy_res["received"] as Dictionary).get(s.core_id, 0.0)) * per_sec
	s.rates["power_supply"] = float(power_res["supply_total"]) * per_sec
	# 儲槽的充能需求算進「需求」——網路本 tick 確實想要那些電，
	# 存量／容量則由 `silo_charge` / `silo_capacity` 另列一格（GDD §3.1）。
	s.rates["power_demand"] = (
		float(power_res["demand_total"]) + float(power_res["silo_demand_total"])
	) * per_sec
	s.rates["silo_charge"] = charge
	s.rates["silo_capacity"] = capacity
	s.rates["conduit_flow"] = flows
	s.rates["conduit_net"] = nets
	s.rates["satisfaction"] = sat
	s.rates["node_state"] = _node_states(s, sat, ore_res, power_res, alloy_res)

	# 交戰中的塔座數＝**本 tick 真的在吃電的那些**。頂欄要它，因為
	# 「能量需求為什麼突然翻倍」這個問題的答案永遠是這個數字。
	s.rates["engaged"] = engaged.values().count(true)

	# 入帳：**只有送達核心的算數**（§7.3）。合金走完全同一條規則。
	var delivered := float((ore_res["received"] as Dictionary).get(s.core_id, 0.0))
	s.ore += delivered
	s.delivered_total += delivered
	var smelted := float((alloy_res["received"] as Dictionary).get(s.core_id, 0.0))
	s.alloy += smelted
	s.alloy_total += smelted


## 節點三態（`10_GDD.md` §3.1）。**兩種資源合看**：一座塔缺電、一台採集器
## 送不掉礦砂，玩家要的都是同一句「這裡有問題」，分兩套徽章只會逼他學兩套。
##
## `缺料` 排在 `滿溢` 前面：兩者同時成立時（中繼被兩邊夾住），
## 玩家該先處理的是「有東西沒送到」，那是產能真的在流失的那一半。
static func _node_states(
	s: RefCounted, sat: Dictionary, ore_res: Dictionary, power_res: Dictionary,
	alloy_res: Dictionary
) -> Dictionary:
	var ore_stuck: Dictionary = ore_res.get("stuck", {})
	var power_stuck: Dictionary = power_res.get("stuck", {})
	var alloy_stuck: Dictionary = alloy_res.get("stuck", {})
	var out: Dictionary = {}
	for n: Dictionary in s.nodes:
		var nid := int(n["id"])
		var def := NodeDefs.of(String(n["type"]))
		# ★ 只有**自己宣告過需求**的節點才會 `缺料`。核心的礦砂需求與儲槽的充能
		#   需求都是解算器合成出來的機會性需求（核心收剩下的、儲槽有多少收多少），
		#   照滿足率掛徽章的話這兩個會幾乎全程亮著——把例外標記變成背景雜訊。
		var declares_demand: bool = (
			def.has("ore_in") or def.has("power_in") or def.has("engage_power")
		)
		# 對稱的另一半：只有**自己產得出東西**的節點才會 `滿溢`。中繼手上塞著
		# 推不掉的餘量是「全網有盈餘」的路由後果，不是一件玩家能在那一格處理的事
		# ——電網滿載又儲槽充飽時它會恆亮，例外標記照樣退化成背景雜訊。
		var produces: bool = (
			def.has("ore_out") or def.has("power_out") or def.has("alloy_out")
		)
		if declares_demand and float(sat.get(nid, 1.0)) < STARVED_BELOW:
			# ★ **餓的是哪一種**（B2.4.8，遊玩測試 P2-1）。`sat` 是兩者取小
			#   （見上），所以「誰比較低」就是答案。相等時算缺電——峰值電力是
			#   本作的核心約束，而且兩邊都缺時先補電比較有機會一次解決。
			var ore_s := float((ore_res["satisfaction"] as Dictionary).get(nid, 1.0))
			var pow_s := float((power_res["satisfaction"] as Dictionary).get(nid, 1.0))
			out[nid] = SessionState.STARVED if ore_s < pow_s else SessionState.STARVED_POWER
		elif produces and maxf(float(alloy_stuck.get(nid, 0.0)), maxf(
			float(ore_stuck.get(nid, 0.0)), float(power_stuck.get(nid, 0.0))
		)) > OVERFLOW_ABOVE:
			out[nid] = SessionState.OVERFLOW
		else:
			out[nid] = SessionState.NORMAL
	return out
