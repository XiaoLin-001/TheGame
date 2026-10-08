extends RefCounted
## 提示列的規則：「下一步」與「這條線連不連得成」。B3.14 自 `screens/Battle*.gd` 抽出。
##
## **純函式、零副作用、不引用 autoload。** 這不是教學系統——沒有進度旗標、沒有步驟機、
## 不持久化，全部是讀當前局面算出來的一句話（`50_QA_PLAN.md` §4.4）。
## 改成 3D 之後這份規則原封不動：它問的是「這局現在缺什麼」，與畫面是平面還是立體無關。

const Build := preload("res://scripts/sim/Build.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")




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
static func next_step(s: RefCounted, buildable: Array) -> String:
	if s.count_of("extractor") == 0:
		return "左欄點「採集器」→ 左鍵點地圖上任一個青色空心圓（礦點）。這是所有東西的源頭。"
	if float(s.rates["ore_in"]) <= 0.0:
		return "礦砂要「送達核心」才入帳：從採集器按住左鍵，拖到下一個節點放開，一路接到右下角的核心。"
	if s.count_of("generator") == 0:
		return "有礦砂了（看頂欄 ▲/秒）。左欄點「發電機」蓋一台，再從採集器拖一條線給它：4 礦砂/秒 → 20 能量/秒。"
	if towers(s) == 0:
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方。貼太近會被走過的敵人打壞。"
	if unpowered_tower(s):
		return "那座塔還沒接進電網，交戰時一發都打不出：從那座塔按住拖到發電機那一側的節點。"
	# 合金是第三資源，但它排在「防線先站得住」之後才提——B0.7 的教訓是
	# 提示列一次只能給一件事做，塞第二條路線只會讓玩家兩件都不做。
	#
	# ★ **這一關沒解鎖熔爐就不准提它**（B1.2）：叫人去點一顆畫面上不存在的鈕，
	#   比不給提示更糟——玩家會以為是自己看漏了，然後花掉整個準備期在找。
	if buildable.has("smelter") and s.count_of("smelter") == 0 and s.alloy <= 0.0:
		return "防線站住了。想加粗幹線到 2 級以上%s，都要合金：左欄點「熔爐」，它吃 8 礦砂/秒 ＋ 10 能量/秒，產 2 合金/秒。" % (
			"、或蓋「碎浪」" if buildable.has("breaker") else ""
		)
	if s.count_of("smelter") > 0 and float(s.rates["alloy_in"]) <= 0.0:
		return "熔爐產的合金也要「送達核心」才入帳：從熔爐拖一條線出去，一路接到核心；同時它的礦砂與電也都要接得到。"
	if s.phase == "prep":
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開。倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
static func connect_hint(s: RefCounted, from: Vector2i, to: Vector2i) -> String:
	if s.node_at(to).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var cf := from
	var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, to, s.conduit_cells()
	)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = to - cf
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(cf, to)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		label_at(s, cf), label_at(s, to), cost, afford
	]


static func label_at(s: RefCounted, cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


static func towers(s: RefCounted) -> int:
	var n := 0
	for node: Dictionary in s.nodes:
		if NodeDefs.of(String(node["type"])).get("tower", false):
			n += 1
	return n


## 有沒有塔完全沒接上任何導管？（接了但電不夠是另一回事，那由三態徽章講。）
static func unpowered_tower(s: RefCounted) -> bool:
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
