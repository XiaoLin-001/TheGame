extends RefCounted
## 流量網路解算器（30_TECH_DESIGN.md §2.5、10_GDD.md §3.1）。
##
## **純函式、零副作用、零系統 RNG**——這是每日挑戰公平性與重播的地基。
## 不引用任何 autoload（`tests/*.gd` 以 `--script` 執行時不載入 autoload）。
##
## 一次 `solve()` 只解**一種資源**的網路（礦砂／能量／合金各跑一次），
## 呼叫端只把該資源的節點與導管傳進來。
##
## ── 輸入 ────────────────────────────────────────────────────────────
## `nodes`：`Array[Dictionary]`，欄位（缺的都有安全預設）：
##   `id`       int    ── 唯一。**遍歷一律依 id 排序**（浮點紀律，§2.4）
##   `type`     String ── 優先權查表的鍵。`"silo"` 觸發儲槽語意
##   `supply`   float  ── 本 tick 產出（採集器、發電機）
##   `demand`   float  ── 本 tick 需求（熔爐、交戰中的塔）
##   `charge`   float  ── 儲槽現有充能
##   `capacity` float  ── 儲槽容量上限
## `edges`：`Array[Dictionary]`，`from` / `to`（node id）、`cap`（吞吐上限）。
##   儲槽的那條線要給**兩條有向邊**（進去充能、出來放電），cap 相同。
## `priorities`：`{type: int}`，1–5。缺者視為 1。
##
## ── 輸出 ────────────────────────────────────────────────────────────
##   `flow`         Array[float]  ── 依 edges 索引，供渲染層算線寬（2 + 6×flow/cap）
##   `satisfaction` {id: float}   ── 實得/需求；無需求者為 1.0
##   `received` / `sent` {id: float}
##   `charge_delta` {id: float}   ── 儲槽：正=充能、負=放電。呼叫端據此更新 charge
##   `stuck`        {id: float}   ── 推不出去的餘量（`滿溢` 徽章，GDD §3.1）
##   `supply_total` / `demand_total` float ── 頂欄「本 tick 供給／需求」用
##
## ── 已知近似（30_TECH_DESIGN.md §2.5 明文允許）────────────────────────
## 有環圖上採「前向傳播 × 3 次迭代」而非完全收斂。副作用：極少數拓樸下
## 資源可能流進中繼節點後無處可去（下游需求被同一迭代內的其他分支先吃掉），
## 該份量會留在該節點而不再前進。3 次迭代後接受此近似值——這是規格選擇，
## 不是缺陷；換來的是每 tick 計算量有硬上界。
##
## ── ★ B2.1e：可送達需求的估計方式（R-17）────────────────────────────
## 「順著這條線下去還有多少需求」以**生成森林上的重根法**求出，而不是
## 對每一次推送各跑一趟 DFS。動機與代價見 `30_TECH_DESIGN.md` §5.3。
## 一句話：舊法是 `O(推送次數 × (V+E))`，新法是 `O(V+E)`，而兩者算的
## 都是同一個近似量——**沒有一個是精確解**，精確解在有環圖上根本不存在
## （這正是上面那段「已知近似」在講的事）。
##
## ★ 非樹邊（環上多出來的那一條）給的是**一跳**的量：只看對面那一格自己的
##   需求，不再往下看。理由是它必須是正的——玩家「兩條線一起餵同一個大
##   消費者」是最自然的佈局之一（見 `_residual()` 的註解），若非樹邊一律
##   估 0，那第二條線會完全不載流，等於偷偷禁掉迴路。

## 有環圖的前向傳播迭代上限。
const ITERATIONS := 3
## 小於此值的量一律當作 0，避免浮點尾數讓佇列跑不完。
const EPS := 0.000001
## 觸發儲槽語意的節點類型。
const SILO := "silo"
## 單一節點在一次迭代內重新分配出邊的回合數（吃掉「配額>殘餘cap」的零頭）。
const REDISTRIBUTE_ROUNDS := 3


## 一張網的**拓樸**——與哪一種資源無關的那一半：稠密索引、有向邊表、
## 孿生邊、出／入邊 CSR、每個節點的導管 cap 總和、生成森林。
##
## ★ 一個 tick 要解三次網路（礦砂／能量／合金），三次的拓樸**逐位元相同**，
##   只有 supply／demand 不同。呼叫端算一次傳三次就好（`BattleController`
##   就是這樣用的）；不傳的話 `solve()` 自己算，介面仍然向後相容。
static func prepare(nodes: Array, edges: Array) -> Dictionary:
	# ★ 全部熱迴圈改用 `0..V-1` 的整數索引與 Packed 陣列。字典查表在 GDScript
	#   裡是解算最大的單一成本（B2.1e 剖析：舊法一次 `_reach` 拜訪約 2.6 µs，
	#   其中大半是 `Dictionary.get`）。對外回傳仍以 node id 為鍵，介面不變。
	var ids: Array[int] = []
	for n: Dictionary in nodes:
		ids.append(int(n.get("id", 0)))
	ids.sort()
	var vn := ids.size()
	var index_of: Dictionary = {}
	for i in vn:
		index_of[ids[i]] = i

	var en := edges.size()
	var e_from := PackedInt32Array()
	var e_to := PackedInt32Array()
	var e_cap := PackedFloat64Array()
	var e_twin := PackedInt32Array()
	e_from.resize(en)
	e_to.resize(en)
	e_cap.resize(en)
	e_twin.resize(en)
	var out_deg := PackedInt32Array()
	out_deg.resize(vn)
	# 儲槽的充放電上限是**自己那條導管的 cap**，一趟掃邊就順手累加好。
	var out_cap := PackedFloat64Array()
	var in_cap := PackedFloat64Array()
	out_cap.resize(vn)
	in_cap.resize(vn)
	# ★ 孿生邊的鍵用**整數**（`f * V + t`）而不是字串。一次 tick 要建三次網路、
	#   每次 700+ 條邊，字串格式化本身就是可量到的成本。
	var seen: Dictionary = {}
	for i in en:
		var e: Dictionary = edges[i]
		var f: int = int(index_of.get(int(e.get("from", -1)), -1))
		var t: int = int(index_of.get(int(e.get("to", -1)), -1))
		e_from[i] = f
		e_to[i] = t
		e_cap[i] = float(e.get("cap", 0.0))
		e_twin[i] = -1
		if f < 0 or t < 0:
			continue
		out_deg[f] += 1
		out_cap[f] += e_cap[i]
		in_cap[t] += e_cap[i]
		var back: int = t * vn + f
		if seen.has(back):
			var j: int = int(seen[back])
			e_twin[i] = j
			e_twin[j] = i
		seen[f * vn + t] = i

	# CSR 出邊表。`out_list[out_start[v] .. out_start[v+1]-1]` 是 v 的出邊索引，
	# **依邊索引遞增**——和舊版 `out_edges[v]` 的順序一致（浮點紀律，§2.4）。
	var out_start := PackedInt32Array()
	out_start.resize(vn + 1)
	var acc := 0
	for v in vn:
		out_start[v] = acc
		acc += out_deg[v]
	out_start[vn] = acc
	var fill := PackedInt32Array()
	fill.resize(vn)
	var out_list := PackedInt32Array()
	out_list.resize(acc)
	for i in en:
		var f := e_from[i]
		if f < 0 or e_to[i] < 0:
			continue
		out_list[out_start[f] + fill[f]] = i
		fill[f] += 1

	# 生成森林也是純拓樸的，所以一起算在這裡——三張網、三次迭代共用同一棵。
	var forest := _spanning_forest(vn, out_start, out_list, e_to)
	return {
		"vn": vn, "en": en, "acc": acc,
		"ids": ids, "index_of": index_of,
		"e_from": e_from, "e_to": e_to, "e_cap": e_cap, "e_twin": e_twin,
		"out_start": out_start, "out_list": out_list,
		"out_cap": out_cap, "in_cap": in_cap,
		"parent_edge": forest[0], "order": forest[1],
	}


static func solve(
	nodes: Array, edges: Array, priorities: Dictionary, topo: Dictionary = {}
) -> Dictionary:
	# ── 0. 拓樸 ──────────────────────────────────────────────────────
	# 尺寸對不上就自己重算：呼叫端傳了一份**過期**的拓樸進來，寧可慢也不能
	# 拿錯誤的圖去解——那會靜靜地把資源送到不存在的節點上。
	var tp := topo
	if tp.is_empty() or int(tp.get("vn", -1)) != nodes.size() or int(tp.get("en", -1)) != edges.size():
		tp = prepare(nodes, edges)
	var vn: int = tp["vn"]
	var en: int = tp["en"]
	var acc: int = tp["acc"]
	var ids: Array[int] = tp["ids"]
	var index_of: Dictionary = tp["index_of"]
	var e_from: PackedInt32Array = tp["e_from"]
	var e_to: PackedInt32Array = tp["e_to"]
	var e_cap: PackedFloat64Array = tp["e_cap"]
	var e_twin: PackedInt32Array = tp["e_twin"]
	var out_start: PackedInt32Array = tp["out_start"]
	var out_list: PackedInt32Array = tp["out_list"]
	var out_cap: PackedFloat64Array = tp["out_cap"]
	var in_cap: PackedFloat64Array = tp["in_cap"]
	var parent_edge: PackedInt32Array = tp["parent_edge"]
	var order: PackedInt32Array = tp["order"]

	var node_at: Array[Dictionary] = []
	node_at.resize(vn)
	for n: Dictionary in nodes:
		node_at[int(index_of[int(n.get("id", 0))])] = n

	# ── 1. 收集：先算不含儲槽的供需，才知道全網是盈餘還是赤字 ──────────
	var supply := PackedFloat64Array()
	var demand := PackedFloat64Array()
	var prio := PackedFloat64Array()
	supply.resize(vn)
	demand.resize(vn)
	prio.resize(vn)
	# 依索引遞增收集（浮點紀律，§2.4）。**在這一趟就收好**，下面那一趟才不必
	# 為了認出儲槽再做一次 `String()`——那是這支函式最貴的單一操作。
	var silo_ids: Array[int] = []
	var base_supply := 0.0
	var base_demand := 0.0
	for v in vn:
		var n: Dictionary = node_at[v]
		var type := String(n.get("type", ""))
		prio[v] = maxf(1.0, float(priorities.get(type, 1)))
		if type == SILO:
			silo_ids.append(v)
			continue
		var s := maxf(0.0, float(n.get("supply", 0.0)))
		var d := maxf(0.0, float(n.get("demand", 0.0)))
		supply[v] = s
		demand[v] = d
		base_supply += s
		base_demand += d

	# ── 儲槽換邊站（GDD §3.1）：盈餘時是消費者，赤字時是供給者。
	#    充放電速率受**自己那條導管的 cap** 約束——這是它與全域水池的根本差別，
	#    不得為了方便豁免（一座 300 容量的儲槽接 cap 10 的線，最多只放得出 10/秒）。
	var silo_discharging := base_demand > base_supply
	var total_rate := 0.0
	for v: int in silo_ids:
		var n: Dictionary = node_at[v]
		var charge := maxf(0.0, float(n.get("charge", 0.0)))
		var capacity := maxf(0.0, float(n.get("capacity", 0.0)))
		if silo_discharging:
			supply[v] = minf(charge, out_cap[v])
			total_rate += supply[v]
		else:
			# 充能時儲槽是**普通消費者**，照自己類型的優先權去搶——搶不搶得贏熔爐
			# 是玩家的戰術決定（GDD §3.1），所以這裡不拿盈餘去封頂。
			demand[v] = minf(maxf(0.0, capacity - charge), in_cap[v])

	# 放電只補缺口，不超額：否則多出來的電會流進網路又無人可用，
	# 表現成「儲槽掉得比赤字還快」的無故漏電。
	var deficit := base_demand - base_supply
	if silo_discharging and total_rate > deficit and total_rate > EPS:
		var scale := deficit / total_rate
		for v: int in silo_ids:
			supply[v] = supply[v] * scale

	# ── 2. 傳播：容量受限的優先權加權分配 ─────────────────────────────
	var flow := PackedFloat64Array()
	var demand_left := PackedFloat64Array()
	var avail := PackedFloat64Array()
	var received := PackedFloat64Array()
	var sent := PackedFloat64Array()
	var carry := PackedFloat64Array()
	flow.resize(en)
	demand_left.resize(vn)
	avail.resize(vn)
	received.resize(vn)
	sent.resize(vn)
	carry.resize(vn)
	for v in vn:
		demand_left[v] = demand[v]
		avail[v] = supply[v]

	# 重根法的工作陣列。**只在真的要傳播時才配置**——沒有供給的那張網
	# （合金網在沒有熔爐時就是）連森林都不必建。
	var claim := PackedFloat64Array()
	var w_buf := PackedFloat64Array()
	var d_buf := PackedFloat64Array()
	var down_a := PackedFloat64Array()
	var down_w := PackedFloat64Array()
	var up_a := PackedFloat64Array()
	var up_w := PackedFloat64Array()

	var step_budget: int = (vn + en) * 4 + 64
	for _iter in ITERATIONS:
		var queue: Array[int] = []
		for v in vn:
			carry[v] = 0.0
			if avail[v] > EPS:
				carry[v] = avail[v]
				avail[v] = 0.0  # 全部倒進 carry；送不出去的會在下面回填
				queue.append(v)
		if queue.is_empty():
			break

		if down_a.is_empty():
			claim.resize(acc)
			w_buf.resize(acc)
			d_buf.resize(acc)
			down_a.resize(vn)
			down_w.resize(vn)
			up_a.resize(vn)
			up_w.resize(vn)
		_reach_pass(
			vn, e_from, e_to, e_cap, e_twin, flow, demand_left, prio,
			parent_edge, order, down_a, down_w, up_a, up_w
		)
		# 「往上看」的量對**除了自己這一支以外**的所有節點都一樣會被消耗，
		# 所以扣減走一個全域位移，只有祖先鏈上那幾個要加回來（見下面的吸收段）。
		var up_off_a := 0.0
		var up_off_w := 0.0

		var steps := 0
		while not queue.is_empty() and steps < step_budget:
			steps += 1
			var v: int = queue.pop_front()
			var amt := carry[v]
			if amt <= EPS:
				continue
			carry[v] = 0.0

			# 自己先吸收（消費節點／充能中的儲槽）
			var take := minf(amt, demand_left[v])
			if take > EPS:
				demand_left[v] -= take
				received[v] += take
				amt -= take
				# ★ 這一份需求沒了，森林上**每一條看得到它的邊**都要跟著扣。
				#
				#   舊法對每一次推送重跑一趟 DFS，所以 `demand_left` 永遠是活的。
				#   新法一個迭代只算一次，不補這一刀的話會出現最難看的那種浪費：
				#   採集器把礦推給發電機、發電機吃飽了，**上游的中繼卻還以為它餓著**，
				#   於是把三分之二的量原路推回去。淺灘示範佈局當場掉 55% 產出
				#   （`delivered_total` 4412.8 → 2008.4），而且看起來像是解算器變笨了。
				var dw := take * prio[v]
				var a := v
				while a >= 0:
					down_a[a] -= take
					down_w[a] -= dw
					# 祖先鏈上這幾個的「往上看」不含 v，所以要抵銷掉下面那個全域位移。
					up_a[a] += take
					up_w[a] += dw
					var ape := parent_edge[a]
					a = -1 if ape < 0 else e_from[ape]
				up_off_a += take
				up_off_w += dw
			if amt <= EPS:
				continue

			var k0 := out_start[v]
			var k1 := out_start[v + 1]
			for k in range(k0, k1):
				claim[k] = 0.0
			# 其餘依「下游可送達需求 × 優先權」分配給出邊
			for _round in REDISTRIBUTE_ROUNDS:
				if amt <= EPS:
					break
				var total_w := 0.0
				for k in range(k0, k1):
					w_buf[k] = 0.0
					var ei := out_list[k]
					var residual := e_cap[ei] - flow[ei]
					var tw := e_twin[ei]
					if tw >= 0:
						residual -= flow[tw]
					if residual <= EPS:
						continue
					var t := e_to[ei]
					var base_a := 0.0
					var base_w := 0.0
					if parent_edge[t] == ei:
						# 樹邊（父→子）：整棵子樹
						base_a = down_a[t]
						base_w = down_w[t]
					elif tw >= 0 and parent_edge[v] == tw:
						# 樹邊的孿生（子→父）：重根後「往上看出去」的那一半
						base_a = up_a[v] - up_off_a
						base_w = up_w[v] - up_off_w
					else:
						# 非樹邊只看對面那一格自己的需求（一跳）——理由見檔頭
						base_a = demand_left[t]
						base_w = base_a * prio[t]
					if base_a <= EPS:
						continue
					# 本回合之前已經認領掉的那一份（`claim` 是**這一次彈出**的局部量，
					# 和舊法那個每次彈出重建的 `reach` 字典是同一件事）。
					var ra := base_a - claim[k]
					if ra <= EPS:
						continue
					var deliverable := minf(residual, ra)
					if deliverable <= EPS:
						continue
					var w := base_w * (ra / base_a) * (deliverable / ra)
					if w <= EPS:
						continue
					w_buf[k] = w
					d_buf[k] = deliverable
					total_w += w
				if total_w <= EPS:
					break
				var moved := 0.0
				for k in range(k0, k1):
					var w := w_buf[k]
					if w <= EPS:
						continue
					var push := minf(amt * w / total_w, d_buf[k])
					if push <= EPS:
						continue
					var ei := out_list[k]
					flow[ei] += push
					sent[v] += push
					moved += push
					var to_v := e_to[ei]
					carry[to_v] += push
					queue.append(to_v)
					# 這份下游需求已經被認領，記進本次彈出的 `claim`——否則同一份
					# 需求會被重新分配的下一回合重複服務一次。
					claim[k] += push
				if moved <= EPS:
					break
				amt -= moved

			# 送不出去的留在原地，下一次迭代再試（下游需求／殘餘 cap 已更新）。
			# 同一節點可能在一次迭代中被彈出多次，所以是累加而非覆寫。
			avail[v] += amt

	# ── 3. 削減與回寫 ────────────────────────────────────────────────
	var flow_out: Array[float] = []
	flow_out.resize(en)
	for i in en:
		flow_out[i] = flow[i]

	var satisfaction: Dictionary = {}
	var received_out: Dictionary = {}
	var sent_out: Dictionary = {}
	var stuck: Dictionary = {}
	for v in vn:
		var nid := ids[v]
		var d := demand[v]
		satisfaction[nid] = 1.0 if d <= EPS else clampf(received[v] / d, 0.0, 1.0)
		received_out[nid] = received[v]
		sent_out[nid] = sent[v]
		stuck[nid] = avail[v]

	var charge_delta: Dictionary = {}
	var silo_discharge := 0.0
	var silo_demand := 0.0
	for v: int in silo_ids:
		if silo_discharging:
			charge_delta[ids[v]] = -sent[v]
			silo_discharge += sent[v]
		else:
			charge_delta[ids[v]] = received[v]
			silo_demand += demand[v]

	return {
		"flow": flow_out,
		"satisfaction": satisfaction,
		"received": received_out,
		"sent": sent_out,
		"charge_delta": charge_delta,
		# ★ 迭代結束後還留在手上、推不出去的量（`滿溢` 徽章的唯一資料來源，
		# `10_GDD.md` §3.1）。
		"stuck": stuck,
		# 頂欄顯示的是「本 tick 供給／需求」，不是存量／容量（GDD §3.1）。
		# 儲槽的充能需求另外給一個數字，讓呼叫端自己決定要不要算進頂欄的「需求」。
		"supply_total": base_supply + silo_discharge,
		"demand_total": base_demand,
		"silo_demand_total": silo_demand,
	}


## 生成森林（BFS）。回傳 `[parent_edge, order]`：
##   `parent_edge[v]` ── 走到 v 用的那條有向邊索引（根為 −1）
##   `order[i]`       ── 造訪序，**父必在子之前**（正序＝前序、逆序＝後序）
##
## **純拓樸**：不看殘餘容量，所以同一張網三次迭代共用同一棵森林。
## 根依索引遞增取、出邊依邊索引遞增走 → 同一份輸入永遠長出同一棵森林（§2.4）。
static func _spanning_forest(
	vn: int, out_start: PackedInt32Array, out_list: PackedInt32Array, e_to: PackedInt32Array
) -> Array:
	var parent_edge := PackedInt32Array()
	var order := PackedInt32Array()
	parent_edge.resize(vn)
	order.resize(vn)
	var seen := PackedInt32Array()
	seen.resize(vn)
	var head := 0
	var tail := 0
	for root in vn:
		if seen[root] == 1:
			continue
		seen[root] = 1
		parent_edge[root] = -1
		order[tail] = root
		tail += 1
		while head < tail:
			var v := order[head]
			head += 1
			for k in range(out_start[v], out_start[v + 1]):
				var ei := out_list[k]
				var t := e_to[ei]
				if seen[t] == 1:
					continue
				seen[t] = 1
				parent_edge[t] = ei
				order[tail] = t
				tail += 1
	return [parent_edge, order]


## 「順著這條有向邊下去，還有多少需求送得到」——兩趟掃過森林就算完
## （後序求子樹 `down`，前序把根重掛到每個節點上得到 `up`）。
##
## `*_a` ＝ 可送達需求，`*_w` ＝ 優先權加權後的同一份需求。
## 加權值只用於分配比例，可送達量用於截斷——兩者分開才不會拿權重當量用。
##
## ★ **結果不攤成「每條邊一份」**：攤開之後就沒辦法在節點吸收需求時
##   O(深度) 地把它扣掉，而那一刀是這套估計法能不能用的關鍵（見傳播段）。
##   讀取端自己從 `down`／`up`／`demand_left` 三者之一取值，一樣是 O(1)。
static func _reach_pass(
	vn: int, e_from: PackedInt32Array, e_to: PackedInt32Array, e_cap: PackedFloat64Array,
	e_twin: PackedInt32Array, flow: PackedFloat64Array, demand_left: PackedFloat64Array,
	prio: PackedFloat64Array, parent_edge: PackedInt32Array, order: PackedInt32Array,
	down_a: PackedFloat64Array, down_w: PackedFloat64Array,
	up_a: PackedFloat64Array, up_w: PackedFloat64Array
) -> void:
	for v in vn:
		down_a[v] = demand_left[v]
		down_w[v] = demand_left[v] * prio[v]

	# ⓪ 非樹邊先以**一跳**的量記進起點的「往下看」。
	#
	# ★ 少了這一段，「兩條 cap 10 的線並聯餵一座 20/秒的塔」會只送到一半
	#   （`flow_test` 那一條就是為這件事寫的）：兩條線之中只有一條會是樹邊，
	#   另一條的起點在森林上看不到那座塔，於是上游把全部的量都押給樹邊那條，
	#   撞上 cap 10 就停了。**迴路不是例外佈局，是最自然的佈局之一。**
	for i in e_from.size():
		var v := e_from[i]
		var t := e_to[i]
		if v < 0 or t < 0 or parent_edge[t] == i:
			continue
		var back := e_twin[i]
		if back >= 0 and parent_edge[v] == back:
			continue
		var d := demand_left[t]
		if d <= EPS:
			continue
		var residual := _res(i, e_cap, flow, e_twin)
		if residual <= EPS:
			continue
		var deliverable := minf(residual, d)
		down_a[v] += deliverable
		down_w[v] += prio[t] * deliverable

	# ① 後序：子樹的可送達需求往上疊。
	for i in range(vn - 1, -1, -1):
		var v := order[i]
		var pe := parent_edge[v]
		if pe < 0:
			continue
		var da := down_a[v]
		if da <= EPS:
			continue
		var residual := _res(pe, e_cap, flow, e_twin)
		if residual <= EPS:
			continue
		var deliverable := minf(residual, da)
		var p := e_from[pe]
		down_a[p] += deliverable
		down_w[p] += down_w[v] * (deliverable / da)

	# ② 前序：把「往父親那一邊看出去」的量算給每個節點（重根）。
	#    `up[v]` ＝ 從 v 沿 v→父 這條邊看出去的可送達需求
	#            ＝ 父的整棵樹 − v 自己這一支 ＋ 父再往上那一段。
	for i in vn:
		var v := order[i]
		var pe := parent_edge[v]
		if pe < 0:
			up_a[v] = 0.0
			up_w[v] = 0.0
			continue
		var p := e_from[pe]
		var base_a := down_a[p]
		var base_w := down_w[p]
		var da := down_a[v]
		if da > EPS:
			var residual := _res(pe, e_cap, flow, e_twin)
			if residual > EPS:
				var deliverable := minf(residual, da)
				base_a -= deliverable
				base_w -= down_w[v] * (deliverable / da)
		var ppe := parent_edge[p]
		if ppe >= 0:
			var ua := up_a[p]
			if ua > EPS:
				# p 往它自己父親那一條邊（＝ p 的 parent_edge 的孿生）
				var upe := e_twin[ppe]
				if upe >= 0:
					var r2 := _res(upe, e_cap, flow, e_twin)
					if r2 > EPS:
						var d2 := minf(r2, ua)
						base_a += d2
						base_w += up_w[p] * (d2 / ua)
		up_a[v] = maxf(0.0, base_a)
		up_w[v] = maxf(0.0, base_w)


## ★ 一條實體導管的**兩個方向共用一份 cap**（B1.2）。
##
## 沒有這一條時，A→B 已經滿載的管子在 B→A 方向還有整份 cap 可用，於是
## 「兩條線一起餵一個大消費者」這種再自然不過的佈局會**只送到四分之一**：
## 資源從幹線推到中繼，中繼看到「經幹線的另一條分支還有需求」，就把一半
## 原路推回去，來回彈掉三次迭代（`10_GDD.md` §7.9 第 2 關的正解正是這種
## 佈局，B1.2 校準時當場現形）。**管子是一根，容量就該是一份。**
static func _res(
	ei: int, e_cap: PackedFloat64Array, flow: PackedFloat64Array, e_twin: PackedInt32Array
) -> float:
	var used := flow[ei]
	var tw := e_twin[ei]
	if tw >= 0:
		used += flow[tw]
	return e_cap[ei] - used


## ★ 誰正在供電給這個節點（B3.6）。**純函式，零副作用。**
##
## 從 `start` 逆著本 tick 的實際流向往上游走，回傳沿途經過的節點與導管，
## 以及其中哪幾個是**來源**（`sources` 裡列的那些，通常是發電機與放電中的儲槽）。
##
## ── 為什麼是逆著「實際流向」而不是「有沒有連著」 ────────────────────
## 一座塔可能連著五條線，而本 tick 真正在餵它的只有兩條——剩下三條是
## 它的**下游**（電從它那一格再推出去給別人）或根本沒有流量。
## 「連著」回答不了玩家的問題（「我的電從哪來」），而**流向**回答得了。
## 這也是為什麼要吃 `net`：那是解算器算出來的結果，不是拓樸的猜測。
##
## `net` ＝ `{conduit id: float}`，**沿 a→b 為正**（呼叫端從 `conduit_net` 的
## 能量分量取出來）。`conduits` 只需要 `id`／`a`／`b` 三個欄位。
##
## 走訪有 `seen` 擋著，所以有環的圖不會無限繞——電網本來就允許成環（§7.2 菱形）。
static func upstream_power(
	conduits: Array, net: Dictionary, start: Vector2i, sources: Dictionary
) -> Dictionary:
	var seen: Dictionary = {start: true}
	var hit_sources: Dictionary = {}
	var used_conduits: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		for c: Dictionary in conduits:
			var a: Vector2i = c["a"]
			var b: Vector2i = c["b"]
			var f := float(net.get(c["id"], 0.0))
			# 上游 ＝ 電從那一端流「進」這一格。零流量的線不算（它沒有在餵誰）。
			var from := Vector2i.ZERO
			if b == here and f > 0.0:
				from = a
			elif a == here and f < 0.0:
				from = b
			else:
				continue
			used_conduits[c["id"]] = true
			if seen.has(from):
				continue
			seen[from] = true
			if sources.has(from):
				hit_sources[from] = true
				# 來源本身不再往上追：它就是答案，而它上游那條線送的是礦砂。
				continue
			queue.append(from)
	return {"nodes": seen, "conduits": used_conduits, "sources": hit_sources}
