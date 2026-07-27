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
##   `supply_total` / `demand_total` float ── 頂欄「本 tick 供給／需求」用
##
## ── 已知近似（30_TECH_DESIGN.md §2.5 明文允許）────────────────────────
## 有環圖上採「前向傳播 × 3 次迭代」而非完全收斂。副作用：極少數拓樸下
## 資源可能流進中繼節點後無處可去（下游需求被同一迭代內的其他分支先吃掉），
## 該份量會留在該節點而不再前進。3 次迭代後接受此近似值——這是規格選擇，
## 不是缺陷；換來的是每 tick 計算量有硬上界。

## 有環圖的前向傳播迭代上限。
const ITERATIONS := 3
## 小於此值的量一律當作 0，避免浮點尾數讓佇列跑不完。
const EPS := 0.000001
## 觸發儲槽語意的節點類型。
const SILO := "silo"
## 單一節點在一次迭代內重新分配出邊的回合數（吃掉「配額>殘餘cap」的零頭）。
const REDISTRIBUTE_ROUNDS := 3


static func solve(nodes: Array, edges: Array, priorities: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	var by_id: Dictionary = {}
	for n: Dictionary in nodes:
		var nid: int = int(n.get("id", 0))
		by_id[nid] = n
		ids.append(nid)
	ids.sort()

	var out_edges: Dictionary = {}  # node id -> Array[int]（edge 索引，依索引遞增）
	var in_edges: Dictionary = {}
	for i in edges.size():
		var e: Dictionary = edges[i]
		var f: int = int(e.get("from", -1))
		var t: int = int(e.get("to", -1))
		if not out_edges.has(f):
			out_edges[f] = [] as Array[int]
		out_edges[f].append(i)
		if not in_edges.has(t):
			in_edges[t] = [] as Array[int]
		in_edges[t].append(i)

	# ── 1. 收集：先算不含儲槽的供需，才知道全網是盈餘還是赤字 ──────────
	var supply: Dictionary = {}
	var demand: Dictionary = {}
	var base_supply := 0.0
	var base_demand := 0.0
	for nid: int in ids:
		var n: Dictionary = by_id[nid]
		supply[nid] = 0.0
		demand[nid] = 0.0
		if String(n.get("type", "")) == SILO:
			continue
		var s := maxf(0.0, float(n.get("supply", 0.0)))
		var d := maxf(0.0, float(n.get("demand", 0.0)))
		supply[nid] = s
		demand[nid] = d
		base_supply += s
		base_demand += d

	# ── 儲槽換邊站（GDD §3.1）：盈餘時是消費者，赤字時是供給者。
	#    充放電速率受**自己那條導管的 cap** 約束——這是它與全域水池的根本差別，
	#    不得為了方便豁免（一座 300 容量的儲槽接 cap 10 的線，最多只放得出 10/秒）。
	var silo_ids: Array[int] = []
	var silo_discharging := base_demand > base_supply
	var total_rate := 0.0
	for nid: int in ids:
		var n: Dictionary = by_id[nid]
		if String(n.get("type", "")) != SILO:
			continue
		silo_ids.append(nid)
		var charge := maxf(0.0, float(n.get("charge", 0.0)))
		var capacity := maxf(0.0, float(n.get("capacity", 0.0)))
		if silo_discharging:
			supply[nid] = minf(charge, _cap_sum(out_edges.get(nid, []), edges))
			total_rate += float(supply[nid])
		else:
			# 充能時儲槽是**普通消費者**，照自己類型的優先權去搶——搶不搶得贏熔爐
			# 是玩家的戰術決定（GDD §3.1），所以這裡不拿盈餘去封頂。
			demand[nid] = minf(maxf(0.0, capacity - charge), _cap_sum(in_edges.get(nid, []), edges))

	# 放電只補缺口，不超額：否則多出來的電會流進網路又無人可用，
	# 表現成「儲槽掉得比赤字還快」的無故漏電。
	var deficit := base_demand - base_supply
	if silo_discharging and total_rate > deficit and total_rate > EPS:
		var scale := deficit / total_rate
		for nid: int in silo_ids:
			supply[nid] = float(supply[nid]) * scale

	# ── 2. 傳播：容量受限的優先權加權分配 ─────────────────────────────
	var flow: Array[float] = []
	flow.resize(edges.size())
	flow.fill(0.0)

	var demand_left: Dictionary = demand.duplicate()
	var avail: Dictionary = supply.duplicate()
	var received: Dictionary = {}
	var sent: Dictionary = {}
	for nid: int in ids:
		received[nid] = 0.0
		sent[nid] = 0.0

	var step_budget: int = (ids.size() + edges.size()) * 4 + 64
	for _iter in ITERATIONS:
		var reach := _reach_all(ids, by_id, out_edges, edges, flow, demand_left, priorities)

		var carry: Dictionary = {}
		var queue: Array[int] = []
		for nid: int in ids:
			carry[nid] = 0.0
			if float(avail[nid]) > EPS:
				carry[nid] = avail[nid]
				avail[nid] = 0.0  # 全部倒進 carry；送不出去的會在下面回填
				queue.append(nid)
		if queue.is_empty():
			break

		var steps := 0
		while not queue.is_empty() and steps < step_budget:
			steps += 1
			var nid: int = queue.pop_front()
			var amt := float(carry[nid])
			if amt <= EPS:
				continue
			carry[nid] = 0.0

			# 自己先吸收（消費節點／充能中的儲槽）
			var take := minf(amt, float(demand_left[nid]))
			if take > EPS:
				demand_left[nid] = float(demand_left[nid]) - take
				received[nid] = float(received[nid]) + take
				amt -= take
			if amt <= EPS:
				continue

			# 其餘依「下游可送達需求 × 優先權」分配給出邊
			var outs: Array = out_edges.get(nid, [])
			for _round in REDISTRIBUTE_ROUNDS:
				if amt <= EPS:
					break
				var weights: Dictionary = {}
				var total_w := 0.0
				for ei: int in outs:
					var e: Dictionary = edges[ei]
					var residual := float(e.get("cap", 0.0)) - flow[ei]
					if residual <= EPS:
						continue
					var down: Vector2 = reach.get(int(e.get("to", -1)), Vector2.ZERO)
					if down.x <= EPS:
						continue
					var deliverable := minf(residual, down.x)
					if deliverable <= EPS:
						continue
					var w := down.y * (deliverable / down.x)
					if w <= EPS:
						continue
					weights[ei] = Vector2(w, deliverable)
					total_w += w
				if total_w <= EPS:
					break
				var moved := 0.0
				for ei: int in weights.keys():
					var wv: Vector2 = weights[ei]
					var push := minf(amt * wv.x / total_w, wv.y)
					if push <= EPS:
						continue
					flow[ei] += push
					sent[nid] = float(sent[nid]) + push
					moved += push
					var to_id: int = int(edges[ei].get("to", -1))
					carry[to_id] = float(carry[to_id]) + push
					queue.append(to_id)
					# 這份下游需求已經被認領，從 reach 扣掉——否則同一份需求會被
					# 重新分配的下一回合、或另一個上游節點重複服務一次。
					var rr: Vector2 = reach[to_id]
					reach[to_id] = Vector2(
						maxf(0.0, rr.x - push), rr.y * maxf(0.0, rr.x - push) / rr.x
					)
				if moved <= EPS:
					break
				amt -= moved

			# 送不出去的留在原地，下一次迭代再試（下游需求／殘餘 cap 已更新）。
			# 同一節點可能在一次迭代中被彈出多次，所以是累加而非覆寫。
			avail[nid] = float(avail[nid]) + amt

	# ── 3. 削減與回寫 ────────────────────────────────────────────────
	var satisfaction: Dictionary = {}
	for nid: int in ids:
		var d := float(demand[nid])
		satisfaction[nid] = 1.0 if d <= EPS else clampf(float(received[nid]) / d, 0.0, 1.0)

	var charge_delta: Dictionary = {}
	var silo_discharge := 0.0
	var silo_demand := 0.0
	for nid: int in silo_ids:
		if silo_discharging:
			charge_delta[nid] = -float(sent[nid])
			silo_discharge += float(sent[nid])
		else:
			charge_delta[nid] = float(received[nid])
			silo_demand += float(demand[nid])

	return {
		"flow": flow,
		"satisfaction": satisfaction,
		"received": received,
		"sent": sent,
		"charge_delta": charge_delta,
		# 頂欄顯示的是「本 tick 供給／需求」，不是存量／容量（GDD §3.1）。
		# 儲槽的充能需求另外給一個數字，讓呼叫端自己決定要不要算進頂欄的「需求」。
		"supply_total": base_supply + silo_discharge,
		"demand_total": base_demand,
		"silo_demand_total": silo_demand,
		"silo_supply_total": silo_discharge,
	}


## 每條出邊的權重需要知道「順著這條線下去，還有多少需求送得到」。
## 回傳 `{id: Vector2(可送達需求, 優先權加權後的同一份需求)}`。
## 加權值只用於分配比例，可送達量用於截斷——兩者分開才不會拿權重當量用。
static func _reach_all(
	ids: Array[int],
	by_id: Dictionary,
	out_edges: Dictionary,
	edges: Array,
	flow: Array[float],
	demand_left: Dictionary,
	priorities: Dictionary
) -> Dictionary:
	var memo: Dictionary = {}
	var visiting: Dictionary = {}
	for nid: int in ids:
		_reach(nid, by_id, out_edges, edges, flow, demand_left, priorities, memo, visiting)
	return memo


static func _reach(
	nid: int,
	by_id: Dictionary,
	out_edges: Dictionary,
	edges: Array,
	flow: Array[float],
	demand_left: Dictionary,
	priorities: Dictionary,
	memo: Dictionary,
	visiting: Dictionary
) -> Vector2:
	if visiting.has(nid):
		return Vector2.ZERO  # 環：這一圈不再往回算，交給迭代收斂
	if memo.has(nid):
		return memo[nid]
	visiting[nid] = true

	var node: Dictionary = by_id.get(nid, {})
	var d := float(demand_left.get(nid, 0.0))
	var prio := maxf(1.0, float(priorities.get(String(node.get("type", "")), 1)))
	var amt := d
	var weighted := d * prio

	for ei: int in out_edges.get(nid, []):
		var e: Dictionary = edges[ei]
		var residual := float(e.get("cap", 0.0)) - flow[ei]
		if residual <= EPS:
			continue
		var down := _reach(
			int(e.get("to", -1)), by_id, out_edges, edges, flow, demand_left,
			priorities, memo, visiting
		)
		if down.x <= EPS:
			continue
		var deliverable := minf(residual, down.x)
		amt += deliverable
		weighted += down.y * (deliverable / down.x)

	visiting.erase(nid)
	var r := Vector2(amt, weighted)
	memo[nid] = r
	return r


static func _cap_sum(edge_ids: Array, edges: Array) -> float:
	var total := 0.0
	for ei: int in edge_ids:
		total += float((edges[ei] as Dictionary).get("cap", 0.0))
	return total
