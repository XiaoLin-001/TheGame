extends RefCounted
## 潮汐公司的純邏輯（`10_GDD.md` §3.8、§7.14）。**B2.5**
##
## 與 `scripts/sim/` 同一條紀律：**純函式、零副作用、零系統 RNG、不讀時鐘**。
## 「現在幾點」一律由呼叫端當參數傳進來——不然離線結算就沒辦法在測試裡
## 快轉三十天，而那正是這個系統唯一會出錯的地方（RG-10）。
##
## 不宣告 `class_name`：一律以路徑 `preload`（`--script` 模式不保證 global class）。
##
## ── 為什麼這個檔案這麼短 ────────────────────────────────────────────
## §3.8 的約束 1 說 tycoon「**沒有失敗狀態、沒有時間壓力、沒有對手**」，
## 約束 2 說 UI 上限兩個畫面。這兩條加起來的意思是：**它是一個水龍頭**。
## 水龍頭不需要狀態機、不需要事件、不需要排程器。
## 任何讓這個檔案變長的提案，先回答 §3.8 約束 3：「這如何讓塔防更好玩」。

## 一個產線位每秒推進的工作單位。**全系統唯一的速率常數**——
## B6「賣速度不賣次數」日後要賣的就是它，所以它必須只有一個。
const RATE := 1.0

## 廠等上限（M2；M3 擴到 25，見 §5 內容矩陣）。
const MAX_LEVEL := 8

## 訂單階 → 這一階的資料。**階 ＝ 解鎖所需的廠等**，一個數字答兩題
## （§7.14：不另做「研發」系統）。
const ORDER_NAMES := [
	"", "浮標外殼", "導管接頭", "冷卻膏", "穩壓線圈",
	"聲納陣列", "合金桁架", "深海軸承", "潮汐渦輪",
]

## 第幾階起附帶招募券（§7.14：名冊的第三條路）。
const TOKEN_FROM_TIER := 4


## 這個廠等有幾個產線位。1,1,1,2,2,2,3,3
##
## ★ **每三級才加一個，不是每兩級**（`tycoon_test._shape_and_curves()` 逼出來的）。
##   產線位是收入的乘數，所以它決定的是收入曲線的**階數**：
##     收入率 ≈ slots(L) × reward(L) ÷ work(L) = slots(L) × 2 × L^0.25
##   每兩級加一個 → `slots ≈ L/2` → 收入 ≈ `L^1.25`，而擴廠成本是 `1.35^L`。
##   在 M2 的八級範圍內，**指數還來不及贏過那個乘數**——實測「存下一次擴廠
##   要多久」是 338 秒 → **314 秒**，也就是越擴越快，方向與 §4.2 的「自然收斂」
##   相反。改成每三級之後是 338 → 419 秒，曲線才真的在收。
##
##   教訓：`10_GDD.md` §4.2 給的兩條公式（成本、報酬）都沒問題，**出問題的是
##   我自己補的第三個參數**。一條「指數成本必定收斂」的直覺，被一個看起來
##   無害的線性乘數推翻了。斷言要驗**玩家感覺得到的量**（存多久），
##   不是驗公式本身長什麼樣。
static func slots(level: int) -> int:
	return 1 + int(floor(float(clampi(level, 1, MAX_LEVEL) - 1) / 3.0))


## 同時最多能接幾張訂單。**比產線位多兩張**，所以「該讓哪一張先上線」
## 從第一分鐘就是一個真的決定——那正是第二個畫面存在的理由。
static func order_cap(level: int) -> int:
	return slots(level) + 2


## 擴到下一級要多少資金（`10_GDD.md` §4.2）。
static func expand_cost(level: int) -> int:
	return int(round(500.0 * pow(1.35, float(level))))


## 這一階訂單的工作量（秒 × RATE）。
static func work_of(tier: int) -> float:
	return 60.0 * float(tier)


## 這一階訂單的報酬。
static func reward_of(tier: int) -> int:
	return int(round(120.0 * pow(float(tier), 1.25)))


## 這一階訂單給幾個升級材料（等級軸的貨幣，兌換介面在 B2.7）。
static func component_of(tier: int) -> int:
	return tier


## 這一階訂單給幾張招募券。
static func token_of(tier: int) -> int:
	return 1 if tier >= TOKEN_FROM_TIER else 0


## 這個廠等接得到哪些階。**階 ≤ 廠等**。
static func available_tiers(level: int) -> Array[int]:
	var out: Array[int] = []
	for t in range(1, clampi(level, 1, MAX_LEVEL) + 1):
		out.append(t)
	return out


## 這一格產線位上是哪一張訂單（回傳 `orders` 的索引，−1 ＝ 空著）。
##
## **佔用狀態是推導的，不另存一份**：存一份「slots 陣列」等於讓同一個事實有兩個
## 版本，而收成一張訂單會讓後面每個索引位移——那一天兩邊都「對」，畫面卻在說謊。
static func order_on_line(state: Dictionary, line: int) -> int:
	var orders: Array = state.get("orders", [])
	for i in orders.size():
		if int((orders[i] as Dictionary).get("line", -1)) == line:
			return i
	return -1


## 這張訂單完成了沒。
static func is_done(order: Dictionary) -> bool:
	return float(order.get("done", 0.0)) >= work_of(int(order.get("tier", 1)))


## 接一張訂單。回傳有沒有接成功（滿了就不接）。
static func accept(state: Dictionary, tier: int) -> bool:
	var orders: Array = state["orders"]
	if orders.size() >= order_cap(int(state.get("level", 1))):
		return false
	if not available_tiers(int(state.get("level", 1))).has(tier):
		return false
	orders.append({"tier": tier, "done": 0.0, "line": -1})
	return true


## 把第 `index` 張訂單放到第 `line` 格產線位（`line < 0` ＝ 下線）。
##
## 那一格原本有別張訂單的話，**那一張被擠下線但進度不歸零**——進度是玩家已經
## 付出的時間，任何會讓它憑空消失的設計都在製造「不敢動」的操作恐懼。
static func assign(state: Dictionary, index: int, line: int) -> bool:
	var orders: Array = state["orders"]
	if index < 0 or index >= orders.size():
		return false
	if line >= slots(int(state.get("level", 1))):
		return false
	if line >= 0:
		var occupant := order_on_line(state, line)
		if occupant >= 0 and occupant != index:
			(orders[occupant] as Dictionary)["line"] = -1
	(orders[index] as Dictionary)["line"] = maxi(-1, line)
	return true


## 推進 `seconds` 秒的生產。**只有已上線且未完成的訂單會動**，
## 而完成的那一張會**佔著產線位停在那裡**——這就是 §7.14 說的「倉儲上限」：
## 它不是一個要調的數字，是一個結構性的上限。離線三十天的收益上限
## ＝「每個產線位各完成一張」（RG-10）。
static func accrue(state: Dictionary, seconds: float) -> void:
	if seconds <= 0.0:
		return
	for o: Variant in state.get("orders", []):
		var order: Dictionary = o
		if int(order.get("line", -1)) < 0:
			continue
		var work := work_of(int(order.get("tier", 1)))
		order["done"] = minf(work, float(order.get("done", 0.0)) + seconds * RATE)


## 收成第 `index` 張訂單。沒做完就不收（回傳 false，什麼都不動）。
static func collect(state: Dictionary, index: int) -> bool:
	var orders: Array = state["orders"]
	if index < 0 or index >= orders.size():
		return false
	var order: Dictionary = orders[index]
	if not is_done(order):
		return false
	var tier := int(order.get("tier", 1))
	state["credits"] = int(state.get("credits", 0)) + reward_of(tier)
	state["components"] = int(state.get("components", 0)) + component_of(tier)
	state["tokens"] = int(state.get("tokens", 0)) + token_of(tier)
	orders.remove_at(index)
	return true


## 擴一級廠。資金不夠或已滿級就不動。
static func expand(state: Dictionary) -> bool:
	var level := int(state.get("level", 1))
	if level >= MAX_LEVEL:
		return false
	var cost := expand_cost(level)
	if int(state.get("credits", 0)) < cost:
		return false
	state["credits"] = int(state["credits"]) - cost
	state["level"] = level + 1
	return true


## ★ 離線結算。`now` ＝ Unix 秒，**由呼叫端傳進來**（見檔頭）。
##
## **時鐘倒退不獎不罰**（`50_QA_PLAN.md` §4.3）：`elapsed` 夾在 0 以上，
## 所以把系統時間調回去既不會倒扣進度、也不會因為「負的 elapsed」變成加速。
## 調回來之後也不會補償——`last_seen` 已經被推到那個較早的時間點了，
## 這正是「不獎不罰」：作弊沒好處，誠實也沒損失。
##
## 回傳這次結算推進了幾秒（畫面拿它講「你離開的這段時間做了多少」）。
static func settle(state: Dictionary, now: int) -> float:
	var last := int(state.get("last_seen", 0))
	# 第一次進來（`last_seen` 還是 0）不結算，否則會把 1970 年到現在全算進去。
	var elapsed := 0.0 if last <= 0 else maxf(0.0, float(now - last))
	state["last_seen"] = now
	accrue(state, elapsed)
	return elapsed
