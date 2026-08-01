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
	# ★ 同一條實體導管的兩個方向互為孿生（`twin`）。**它們共用一份 cap**——
	#   見下方 `_residual()`。
	var twin: Dictionary = {}
	var seen: Dictionary = {}
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
		var back := "%d>%d" % [t, f]
		if seen.has(back):
			twin[i] = int(seen[back])
			twin[int(seen[back])] = i
		seen["%d>%d" % [f, t]] = i

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
	#
	# ★ 效能（B1.7）：下面這三張表是**把每次拜訪都要重算的常數提到迴圈外**，
	#   不動任何一個算式、不動任何一次運算的順序，所以結果逐位元相同
	#   （`campaign_test` 406 項與 `TL_SIM` 基準是這件事的證明）。
	#
	#   為什麼值得：傳播是 `O(迭代 × (V+E)²)` 級的拜訪次數，而原本**每一次拜訪**
	#   都要做 `by_id` 查表 → `n.get("type")` → `String(...)` → `priorities` 查表。
	#   在 GDScript 裡，一次 Variant 轉 String 比整個算式本身還貴——第 5 關量到
	#   9.2ms/tick（預算是 3ms、上限 8ms），其中大半是這一行在跑。
	#
	#   ⚠ `PackedFloat64Array` 不是 `Float32`：後者會把 cap 降成單精度，
	#   那就不是「一樣的計算跑得比較快」，是**換了一組數字**。
	var edge_to := PackedInt32Array()
	var edge_cap := PackedFloat64Array()
	edge_to.resize(edges.size())
	edge_cap.resize(edges.size())
	for i in edges.size():
		var e: Dictionary = edges[i]
		edge_to[i] = int(e.get("to", -1))
		edge_cap[i] = float(e.get("cap", 0.0))
	var prio_of: Dictionary = {}
	for nid: int in ids:
		prio_of[nid] = maxf(1.0, float(priorities.get(String((by_id[nid] as Dictionary).get("type", "")), 1)))

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

			# ★ 「順著這條線下去還有多少需求」是一個**對每個推送者各自成立**的量，
			#   不是節點自帶的屬性：算的時候必須把推送者自己標成 visiting 排除掉。
			#   否則在雙向邊上（一條實體管線＝兩條方向相反的邊）A 會看到「經 B
			#   還有需求」，而那份需求其實要繞回 A 自己——資源就在兩點之間來回彈，
			#   線寬灌水、流量對不上（B0.5 把導管改成雙向後當場現形）。
			var outs: Array = out_edges.get(nid, [])
			var memo: Dictionary = {}
			var visiting: Dictionary = {nid: true}
			var reach: Dictionary = {}
			for ei: int in outs:
				var tid: int = edge_to[ei]
				if not reach.has(tid):
					reach[tid] = _reach(
						tid, out_edges, edge_to, edge_cap, flow, demand_left, prio_of,
						memo, visiting, twin
					)

			# 其餘依「下游可送達需求 × 優先權」分配給出邊
			for _round in REDISTRIBUTE_ROUNDS:
				if amt <= EPS:
					break
				var weights: Dictionary = {}
				var total_w := 0.0
				for ei: int in outs:
					var residual := _residual(ei, edge_cap, flow, twin)
					if residual <= EPS:
						continue
					var down: Vector2 = reach.get(edge_to[ei], Vector2.ZERO)
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
					var to_id: int = edge_to[ei]
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
		# ★ 迭代結束後還留在手上、推不出去的量（`滿溢` 徽章的唯一資料來源，
		# `10_GDD.md` §3.1）。它一直都在迴圈裡（`avail` 的殘值），只是以前沒回傳。
		"stuck": avail,
		# 頂欄顯示的是「本 tick 供給／需求」，不是存量／容量（GDD §3.1）。
		# 儲槽的充能需求另外給一個數字，讓呼叫端自己決定要不要算進頂欄的「需求」。
		"supply_total": base_supply + silo_discharge,
		"demand_total": base_demand,
		"silo_demand_total": silo_demand,
		"silo_supply_total": silo_discharge,
	}


## 「順著 `nid` 這條線下去，還有多少需求送得到」。
## 回傳 `Vector2(可送達需求, 優先權加權後的同一份需求)`。
## 加權值只用於分配比例，可送達量用於截斷——兩者分開才不會拿權重當量用。
##
## **呼叫端必須把推送者自己放進 `visiting`**：這個量對每個推送者各自成立，
## 不是節點自帶的屬性（見上面傳播段的說明）。`memo` 因此只在同一個推送者的
## 那幾條出邊之間共用，跨推送者不重用。
##
## ponytail: 每個節點彈出時各算一次 ＝ O(V×(V+E))。M0 一屏地圖（≤ 40 節點）
## 綽綽有餘；B2.1 的程序生成大圖若量到瓶頸，再換成不依賴路徑的 reach 估計。
static func _reach(
	nid: int,
	out_edges: Dictionary,
	edge_to: PackedInt32Array,
	edge_cap: PackedFloat64Array,
	flow: Array[float],
	demand_left: Dictionary,
	prio_of: Dictionary,
	memo: Dictionary,
	visiting: Dictionary,
	twin: Dictionary
) -> Vector2:
	if visiting.has(nid):
		return Vector2.ZERO  # 環：這一圈不再往回算，交給迭代收斂
	if memo.has(nid):
		return memo[nid]
	visiting[nid] = true

	var d := float(demand_left.get(nid, 0.0))
	var prio := float(prio_of.get(nid, 1.0))
	var amt := d
	var weighted := d * prio

	for ei: int in out_edges.get(nid, []):
		var residual := _residual(ei, edge_cap, flow, twin)
		if residual <= EPS:
			continue
		var down := _reach(
			edge_to[ei], out_edges, edge_to, edge_cap, flow, demand_left,
			prio_of, memo, visiting, twin
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


## ★ 一條實體導管的**兩個方向共用一份 cap**（B1.2）。
##
## 沒有這一條時，A→B 已經滿載的管子在 B→A 方向還有整份 cap 可用，於是
## 「兩條線一起餵一個大消費者」這種再自然不過的佈局會**只送到四分之一**：
## 資源從幹線推到中繼，中繼看到「經幹線的另一條分支還有需求」，就把一半
## 原路推回去，來回彈掉三次迭代（`10_GDD.md` §7.9 第 2 關的正解正是這種
## 佈局，B1.2 校準時當場現形）。**管子是一根，容量就該是一份。**
static func _residual(ei: int, edge_cap: PackedFloat64Array, flow: Array[float], twin: Dictionary) -> float:
	var cap := edge_cap[ei]
	var used := flow[ei]
	if twin.has(ei):
		used += flow[int(twin[ei])]
	return cap - used


static func _cap_sum(edge_ids: Array, edges: Array) -> float:
	var total := 0.0
	for ei: int in edge_ids:
		total += float((edges[ei] as Dictionary).get("cap", 0.0))
	return total
