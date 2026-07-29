extends SceneTree
## 建造規則與局內迴圈（`10_GDD.md` §3.2／§7.2／§7.3、`50_QA_PLAN.md` §2）。
##
## 這支測試鎖住的設計承諾：
##   RG-16 的前半（**節點禁在路徑格、導管只能走跨越點**——敵人攻擊的部分在 B0.4）
##   §7.2 **基礎 cap 10 < 發電機輸出 20 是設計**，以及加粗幹線確實提升流量
##   §7.3 **核心＝礦砂銀行**：沒接到核心的採集器一毛錢也賺不到
##
## 跑法：<godot> --headless --path godot --script res://tests/build_test.gd

const T := preload("res://tests/_assert.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("build_test")
	_geometry(t)
	_placement_rules(t)
	_conduit_rules(t)
	_economy(t)
	_ore_banks_at_core(t)
	_generator_saturates_base_trunk(t)
	_preview_before_paying(t)
	quit(t.report())


# ── 預覽：**在花錢之前**就看得到後果（DoD）─────────────────────────────

func _preview_before_paying(t: T) -> void:
	var s := _session()
	var pv: Dictionary = BuildController.preview_place(s, "extractor", Vector2i(7, 10))
	t.ok(bool(pv["ok"]), "預覽：合法位置標示為可蓋")
	t.ok(_has(pv, "＋6 礦砂/秒"), "預覽：顯示 +X/秒")
	t.ok(_has(pv, "核心"), "預覽：講明「要接到核心才入帳」")

	pv = BuildController.preview_place(s, "generator", Vector2i(20, 10))
	t.ok(_has(pv, "總能量供給 0 → 20 /秒"), "預覽：總能量供給變化")
	t.ok(_has(pv, "−4 礦砂/秒"), "預覽：燃料支出")

	pv = BuildController.preview_place(s, "silo", Vector2i(20, 10))
	t.ok(_has(pv, "總能量需求 0 → 10 /秒"), "預覽：**總耗能 →Y/秒**（受導管 cap 約束）")

	pv = BuildController.preview_place(s, "relay", Vector2i(12, 4))
	t.ok(not bool(pv["ok"]), "預覽：路徑格標示為不可蓋")
	t.ok(_has(pv, "敵人路徑"), "預覽：**擋下時說明原因**，不是默默變灰")

	s.ore = 1.0
	pv = BuildController.preview_place(s, "extractor", Vector2i(7, 10))
	t.ok(not bool(pv["ok"]) and _has(pv, "礦砂不夠"), "預覽：錢不夠也講清楚")


func _has(preview: Dictionary, needle: String) -> bool:
	for line: String in preview["lines"]:
		if line.contains(needle):
			return true
	return false


# ── 幾何（純函式）──────────────────────────────────────────────────────

func _geometry(t: T) -> void:
	t.ok(Build.is_straight(Vector2i(0, 0), Vector2i(5, 0)), "走向：水平合法")
	t.ok(Build.is_straight(Vector2i(0, 0), Vector2i(0, -4)), "走向：垂直合法")
	t.ok(Build.is_straight(Vector2i(2, 2), Vector2i(5, 5)), "走向：正 45° 合法")
	t.ok(not Build.is_straight(Vector2i(0, 0), Vector2i(3, 1)), "走向：任意角度不合法（要用中繼轉折）")
	t.ok(not Build.is_straight(Vector2i(1, 1), Vector2i(1, 1)), "走向：零長度不合法")

	t.eq(Build.line_cells(Vector2i(0, 0), Vector2i(3, 3)).size(), 4, "佔格：45° 四格（含頭尾）")
	t.eq(Build.line_cells(Vector2i(0, 0), Vector2i(3, 1)).size(), 0, "佔格：走向不合法回空")
	t.eq(Build.conduit_cost(Vector2i(0, 0), Vector2i(5, 0)), 15, "造價：5 格 × 3 礦砂")

	t.near(Build.conduit_cap(0), 10.0, "cap：基礎 10")
	t.near(Build.conduit_cap(2), 22.0, "cap：升 2 級 22")
	t.near(Build.conduit_cap(3), 28.0, "cap：滿級 28")
	t.near(Build.conduit_cap(9), 28.0, "cap：超過上限仍是 28")
	t.eq(Build.upgrade_cost(0), 20, "升級造價：20 × 級數（第 1 級）")
	t.eq(Build.upgrade_cost(2), 60, "升級造價：20 × 級數（第 3 級）")
	t.eq(
		Build.conduit_key(Vector2i(3, 1), Vector2i(0, 0)),
		Build.conduit_key(Vector2i(0, 0), Vector2i(3, 1)),
		"導管鍵：A→B 與 B→A 是同一條"
	)


# ── 放置合法性 ────────────────────────────────────────────────────────

func _placement_rules(t: T) -> void:
	var s := _session()
	t.eq(
		BuildController.place(s, "relay", Vector2i(12, 4)), Build.ON_PATH,
		"路徑格禁節點"
	)
	t.eq(
		BuildController.place(s, "relay", Vector2i(10, 4)), Build.ON_PATH,
		"**跨越點也禁節點**（橋上只能鋪導管）"
	)
	t.eq(
		BuildController.place(s, "relay", Vector2i(-1, 5)), Build.OUT_OF_BOUNDS,
		"超出範圍"
	)
	t.eq(
		BuildController.place(s, "extractor", Vector2i(20, 10)), Build.NEEDS_ORE_CELL,
		"採集器只能蓋在礦點上"
	)
	t.eq(
		BuildController.place(s, "relay", Vector2i(7, 10)), Build.ORE_CELL_RESERVED,
		"礦點只留給採集器"
	)
	t.eq(BuildController.place(s, "extractor", Vector2i(7, 10)), Build.OK, "礦點上蓋採集器 OK")
	t.eq(
		BuildController.place(s, "relay", Vector2i(7, 10)), Build.OCCUPIED,
		"同一格不能蓋兩個"
	)
	t.eq(BuildController.demolish(s, s.map["core"]), Build.OCCUPIED, "核心拆不得")


# ── 導管合法性 ────────────────────────────────────────────────────────

func _conduit_rules(t: T) -> void:
	var s := _session()
	BuildController.place(s, "relay", Vector2i(20, 2))   # 路徑北岸
	BuildController.place(s, "relay", Vector2i(20, 6))   # 路徑南岸
	BuildController.place(s, "relay", Vector2i(22, 2))   # 跨越點 (22,4) 正上方
	BuildController.place(s, "relay", Vector2i(22, 6))   # 跨越點正下方

	t.eq(
		BuildController.lay_conduit(s, Vector2i(20, 2), Vector2i(20, 6)), Build.CROSSES_PATH,
		"★ 導管過路徑：非跨越點的那一格擋下"
	)
	t.eq(
		BuildController.lay_conduit(s, Vector2i(22, 2), Vector2i(22, 6)), Build.OK,
		"★ 導管過路徑：走跨越點（橋）就通"
	)
	t.eq(
		BuildController.lay_conduit(s, Vector2i(22, 2), Vector2i(22, 6)), Build.DUPLICATE,
		"同兩點之間只能有一條導管"
	)
	t.eq(
		BuildController.lay_conduit(s, Vector2i(20, 2), Vector2i(22, 6)), Build.NOT_STRAIGHT,
		"走向不合法要先放中繼轉折"
	)


# ── 經濟：造價、返還、升級 ────────────────────────────────────────────

func _economy(t: T) -> void:
	var s := _session()
	var start: float = s.ore
	t.eq(BuildController.place(s, "extractor", Vector2i(7, 10)), Build.OK, "蓋採集器")
	t.near(s.ore, start - 40.0, "扣款：採集器 40 礦砂")

	BuildController.place(s, "relay", Vector2i(11, 10))
	t.eq(BuildController.lay_conduit(s, Vector2i(7, 10), Vector2i(11, 10)), Build.OK, "拉導管")
	t.near(s.ore, start - 40.0 - 15.0 - 12.0, "扣款：中繼 15 ＋ 導管 4 格 ×3")

	# ★ 1 級純礦砂（B0.3 的教學動作不可被合金鎖掉），2/3 級要合金（§7.2）。
	t.eq(BuildController.upgrade(s, 0), Build.OK, "加粗 1 級：不用合金")
	t.eq(int(s.conduits[0]["level"]), 1, "加粗後 level = 1")
	t.eq(BuildController.upgrade(s, 0), Build.NO_ALLOY, "★ 加粗 2 級沒合金 → 擋下")
	t.eq(int(s.conduits[0]["level"]), 1, "被擋下就不會偷偷升級")
	s.alloy = 70.0
	var ore_before: float = s.ore
	t.eq(BuildController.upgrade(s, 0), Build.OK, "有合金了 → 加粗 2 級")
	t.near(s.alloy, 50.0, "扣款：2 級 20 合金")
	t.near(s.ore, ore_before - 40.0, "扣款：2 級 40 礦砂")
	t.eq(BuildController.upgrade(s, 0), Build.OK, "加粗 3 級")
	t.near(s.alloy, 0.0, "扣款：3 級 50 合金（70 − 20 − 50）")
	t.eq(BuildController.upgrade(s, 0), Build.MAX_LEVEL, "第 4 次加粗被擋（上限 3 級）")

	var before: float = s.ore
	t.eq(BuildController.demolish(s, Vector2i(7, 10)), Build.OK, "拆採集器")
	t.near(s.ore, before + 30.0, "返還 75%：40 × 0.75 = 30")
	t.eq(s.conduits.size(), 0, "拆節點會一併移除接在它上面的導管")


# ── ★ 核心＝礦砂銀行（`10_GDD.md` §7.3）────────────────────────────────

func _ore_banks_at_core(t: T) -> void:
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(25, 12))
	var before: float = s.ore
	for i in 10:
		BattleController.step(s)
	t.near(s.ore, before, "★ 沒接到核心的採集器一毛錢也賺不到", 0.001)
	t.near(float(s.rates["ore_in"]), 0.0, "★ 入帳速率為 0")

	# 接到核心（必須經跨越點 (30,9)，東岸的核心沒有別的路）
	for cell: Vector2i in [Vector2i(28, 9), Vector2i(33, 9), Vector2i(33, 13)]:
		BuildController.place(s, "relay", cell)
	t.eq(BuildController.lay_conduit(s, Vector2i(25, 12), Vector2i(28, 9)), Build.OK, "礦線：45° 上坡")
	t.eq(BuildController.lay_conduit(s, Vector2i(28, 9), Vector2i(33, 9)), Build.OK, "礦線：過橋 (30,9)")
	t.eq(BuildController.lay_conduit(s, Vector2i(33, 9), Vector2i(33, 13)), Build.OK, "礦線：南下")
	t.eq(BuildController.lay_conduit(s, Vector2i(33, 13), s.map["core"]), Build.OK, "礦線：接上核心")

	before = s.ore
	for i in 10:
		BattleController.step(s)
	t.near(float(s.rates["ore_in"]), 6.0, "★ 接上核心後入帳 6 礦砂/秒（＝採集器輸出）")
	t.near(s.ore, before + 6.0, "★ 10 個 tick（1 秒）正好入帳 6", 0.001)


# ── ★ 基礎 cap 10 < 發電機輸出 20（`10_GDD.md` §7.2）───────────────────

func _generator_saturates_base_trunk(t: T) -> void:
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(16, 8))
	BuildController.place(s, "generator", Vector2i(16, 11))
	BuildController.place(s, "silo", Vector2i(20, 15))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 11))
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(20, 15))
	var trunk: int = s.conduits[1]["id"]  # 發電機 → 儲槽

	BattleController.step(s)
	t.near(
		float(s.rates["conduit_flow"][trunk]), 10.0,
		"★ 發電機輸出 20，基礎 cap 10 的線只送得出 10——**一半的電出不來**"
	)
	t.near(
		float(s.rates["power_supply"]), 20.0,
		"★ 供給仍是 20：瓶頸在線上，不是在發電機（頂欄要誠實）"
	)

	# 加粗幹線 → 流量提升（§7.2 的取捨表）
	BuildController.upgrade(s, 1)
	BattleController.step(s)
	t.near(float(s.rates["conduit_flow"][trunk]), 16.0, "★ 升 1 級 → 16")
	# ★ 「第一台發電機的一半電出不來」這一課，**在合金之前只能解到 16**——
	# 要真的送滿 20 得先蓋熔爐（§7.2）。這一步發合金是為了驗 cap 22 的流量，
	# 合金經濟本身在 `_economy` 與 `flow_test` 裡驗。
	s.alloy = 20.0
	BuildController.upgrade(s, 1)
	BattleController.step(s)
	t.near(float(s.rates["conduit_flow"][trunk]), 20.0, "★ 升 2 級（cap 22）→ 送滿 20，瓶頸解除")

	# 儲槽確實充到電了（能量有去處，不是憑空消失）
	t.ok(float(s.rates["silo_charge"]) > 0.0, "儲槽充能中")
	t.near(float(s.rates["silo_capacity"]), 300.0, "儲槽容量 300")


# ── 小工具 ────────────────────────────────────────────────────────────

func _session() -> RefCounted:
	var s := SessionState.new()
	s.setup(Maps.SHOAL)
	s.ore = 100000.0  # 規則測試不該被錢卡住；扣款本身另有測項
	return s
