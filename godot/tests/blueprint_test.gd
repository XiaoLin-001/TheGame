extends SceneTree
## 藍圖庫（`10_GDD.md` §3.7、§7.12；B2.3）。
##
## 兩條 DoD：**存取往返正確**、**展開時資源不足有明確提示而非靜默失敗**。
## 後者的反面是這一批最該怕的事——花掉資源換到一個接不起來的殘骸。
##
## 跑法：<godot> --headless --path godot --script res://tests/blueprint_test.gd

const T := preload("res://tests/_assert.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Tech := preload("res://data/Tech.gd")


func _initialize() -> void:
	var t := T.new("blueprint_test", 51)
	_capture_is_relative_and_stable(t)
	_cost_matches_what_it_actually_charges(t)
	_expand_round_trips(t)
	_shortfall_is_reported_not_swallowed(t)
	_all_or_nothing(t)
	_slots_and_save(t)
	quit(t.report())


## 靜水沙盤是 **20×16、核心在 (10,10)、礦點在 (2,2) 與 (4,4)**。
## 佈局座標全部避開這三處——**第一版沒避開**，於是 `place()` 靜靜失敗、
## 藍圖少一個節點，而測試看起來像是藍圖模組壞了（`_built(t)` 沒有斷言自己
## 的前置條件，量測台自己也要驗）。
const A := Vector2i(14, 2)    # 發電機
const B := Vector2i(14, 4)    # 中繼（A 的正下方）
const C := Vector2i(17, 4)    # 中繼（B 的右邊）
## 框選矩形：把 A/B/C 都包進去，左上角是原點。
const SEL_LO := Vector2i(13, 1)
const SEL_HI := Vector2i(18, 5)
## 兩個空得下 5×4 的落點。
const DEST := Vector2i(1, 8)
const DEST2 := Vector2i(14, 8)


## 一張蓋了東西的沙盤：三個節點連成一條 L，兩條導管。
func _built(t: T) -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SANDBOX)
	s.ore = 99999.0
	s.alloy = 99999.0
	var fails: Array = BuildController.apply_ops(s, [
		["place", "generator", A], ["place", "relay", B], ["place", "relay", C],
		["conduit", A, B], ["conduit", B, C],
	])
	# ★ 前置條件要有斷言。少了它，佈局蓋不起來時後面每一條都會紅，
	#   而紅的原因看起來會像是被測模組的問題。
	t.ok(fails.is_empty(), "前置：測試佈局蓋得起來（失敗 %d）" % fails.size())
	return s


# ── ① 框選 ────────────────────────────────────────────────────────────

func _capture_is_relative_and_stable(t: T) -> void:
	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)
	t.eq((bp["nodes"] as Array).size(), 3, "三個節點都框到了")
	t.eq((bp["conduits"] as Array).size(), 2, "兩條導管都框到了")
	# 原點是矩形左上（9,9），所以採集器的相對位置是 (1,1)。
	t.eq((bp["nodes"] as Array)[0]["at"], [1, 1], "座標是相對的（矩形左上為原點）")
	t.eq(Blueprint.span(bp), Vector2i(5, 4), "尺寸 5×4")

	# ★ 核心不收——它蓋不出來，收進去只會讓每次展開都固定失敗一格。
	var whole := Blueprint.capture(
		s.nodes, s.conduits, Vector2i(0, 0), Vector2i(19, 15)
	)
	for n: Dictionary in whole["nodes"]:
		t.ok(String(n["type"]) != "core", "★ 核心不進藍圖")

	# ★ 一端在框外的導管不收：展開時另一端接不到任何節點。
	var half := Blueprint.capture(s.nodes, s.conduits, SEL_LO, Vector2i(15, 5))
	t.eq((half["nodes"] as Array).size(), 2, "前置：只框到兩個節點")
	t.eq(
		(half["conduits"] as Array).size(), 1,
		"★ 跨出框線的導管不收（它是接線，不是藍圖的一部分）"
	)

	# ★ 蓋的順序不影響框出來的藍圖——否則同一份佈局會存出兩張不同的藍圖。
	var s2: RefCounted = SessionState.new()
	s2.setup(Maps.SANDBOX)
	s2.ore = 99999.0
	s2.alloy = 99999.0
	BuildController.apply_ops(s2, [
		["place", "relay", C], ["place", "relay", B], ["place", "generator", A],
		["conduit", B, C], ["conduit", A, B],
	])
	var bp2 := Blueprint.capture(s2.nodes, s2.conduits, SEL_LO, SEL_HI)
	t.eq(bp2["nodes"], bp["nodes"], "★ 反序蓋出同一份佈局 → 同一張藍圖（節點）")
	t.eq(bp2["conduits"], bp["conduits"], "★ 同上（導管）")


# ── ② 成本 ────────────────────────────────────────────────────────────

## 估價與實際扣款必須是同一個數字。**不同的話「缺口提示」講的是另一件事**，
## 而玩家會照著它去湊錢，湊到了還是蓋不起來。
func _cost_matches_what_it_actually_charges(t: T) -> void:
	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)
	var need: Dictionary = Blueprint.cost(bp)
	var fresh: RefCounted = SessionState.new()
	fresh.setup(Maps.SANDBOX)
	fresh.ore = 99999.0
	fresh.alloy = 99999.0
	var ore_before: float = fresh.ore
	var alloy_before: float = fresh.alloy
	t.eq(BuildController.blueprint_place(fresh, bp, DEST), "", "前置：展開成功")
	t.near(ore_before - fresh.ore, float(need["ore"]), "★ 估的礦砂＝實際扣的礦砂")
	t.near(alloy_before - fresh.alloy, float(need["alloy"]), "★ 估的合金＝實際扣的合金")
	# 成本與放在哪裡無關（導管造價只看相對位移）。
	var other: RefCounted = SessionState.new()
	other.setup(Maps.SANDBOX)
	other.ore = 99999.0
	other.alloy = 99999.0
	var o2: float = other.ore
	BuildController.blueprint_place(other, bp, DEST2)
	t.near(o2 - other.ore, float(need["ore"]), "★ 換一個位置展開，成本一樣")


# ── ③ 存取往返（DoD 第一條）──────────────────────────────────────────

func _expand_round_trips(t: T) -> void:
	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)

	# ★ 走一趟真的 JSON：藍圖要進 `user://save.json`，而 `Vector2i` 過不了 JSON。
	#   這一條就是「座標存成 [dx, dy]」那個決定的驗收條件。
	var text := JSON.stringify({"blueprints": [bp]})
	var back: Dictionary = JSON.parse_string(text)
	var bp2: Dictionary = (back["blueprints"] as Array)[0]
	t.eq((bp2["nodes"] as Array).size(), 3, "JSON 往返後節點數不變")

	var fresh: RefCounted = SessionState.new()
	fresh.setup(Maps.SANDBOX)
	fresh.ore = 99999.0
	fresh.alloy = 99999.0
	t.eq(BuildController.blueprint_place(fresh, bp2, DEST), "", "JSON 往返後展開得起來")
	t.eq(fresh.nodes.size(), 4, "三個節點 ＋ 核心")
	t.eq(fresh.conduits.size(), 2, "兩條導管")
	# ★ 形狀真的一樣：相對位置逐格比對。
	var again := Blueprint.capture(
		fresh.nodes, fresh.conduits, DEST, DEST + Vector2i(5, 4)
	)
	t.eq(again["nodes"], bp["nodes"], "★ 展開後再框一次 → 逐欄相同（節點）")
	t.eq(again["conduits"], bp["conduits"], "★ 同上（導管）")


# ── ④ 缺口提示（DoD 第二條）──────────────────────────────────────────

func _shortfall_is_reported_not_swallowed(t: T) -> void:
	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)
	var need: Dictionary = Blueprint.cost(bp)

	var poor: RefCounted = SessionState.new()
	poor.setup(Maps.SANDBOX)
	poor.ore = float(int(need["ore"]) - 25)
	poor.alloy = 99999.0
	var chk := BuildController.blueprint_check(poor, bp, DEST)
	t.ok(not bool(chk["ok"]), "錢不夠 → 檢查不過")
	t.eq(int(chk["ore_short"]), 25, "★ 缺口是**具體的數字**，不是「資源不足」")
	var msg := BuildController.blueprint_place(poor, bp, DEST)
	t.ok(msg.contains("礦砂差 25"), "★ 訊息把缺口講出來（%s）" % msg)
	t.eq(poor.nodes.size(), 1, "★ 失敗時一格都沒放（只剩核心）")
	t.near(poor.ore, float(int(need["ore"]) - 25), "★ 失敗時一塊錢都沒扣")


# ── ⑤ 全有全無 ────────────────────────────────────────────────────────

## 藍圖是一個單位。半套展開＝花掉資源換到一個接不起來的殘骸，
## 而拆掉只退 75%——那是玩家沒有辦法補救的損失。
func _all_or_nothing(t: T) -> void:
	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)
	var target: RefCounted = SessionState.new()
	target.setup(Maps.SANDBOX)
	target.ore = 99999.0
	target.alloy = 99999.0
	# 先在藍圖會用到的其中一格放一個東西，讓那一格蓋不下去。
	var origin := DEST
	var occupied_cell: Vector2i = Blueprint.cells_at(bp, origin)[1]
	BuildController.place(target, "relay", occupied_cell)
	var nodes_before: int = target.nodes.size()
	var ore_before: float = target.ore

	var chk := BuildController.blueprint_check(target, bp, origin)
	t.ok(not bool(chk["ok"]), "有一格被佔住 → 檢查不過")
	t.eq((chk["blocked"] as Array).size(), 1, "★ 指出的是**那一格**，不是「失敗了」")
	t.eq((chk["blocked"] as Array)[0], occupied_cell, "★ 而且是對的那一格")
	var msg := BuildController.blueprint_place(target, bp, origin)
	t.ok(msg.contains("蓋不下"), "訊息說得出是位置的問題（%s）" % msg)
	t.eq(target.nodes.size(), nodes_before, "★ 一格都沒放")
	t.near(target.ore, ore_before, "★ 一塊錢都沒扣")

	# 換一個空位就放得下——證明上面擋掉的是那一格，不是整張藍圖壞了。
	t.eq(BuildController.blueprint_place(target, bp, DEST2), "", "換個位置就成功")
	t.eq(target.nodes.size(), nodes_before + 3, "三個節點都放上去了")


# ── ⑥ 槽數與存檔 ──────────────────────────────────────────────────────

func _slots_and_save(t: T) -> void:
	t.eq(Blueprint.slots(Tech.NO_MODS), Blueprint.BASE_SLOTS, "沒有科技時是免費槽數")
	var all: Array = []
	for i in Tech.count():
		all.append(String(Tech.NODES[i]["id"]))
	t.eq(
		Blueprint.slots(Tech.mods(all)), Blueprint.BASE_SLOTS + 2,
		"★ 後勤科技兩級各 +1 槽（§7.8）"
	)

	var s := _built(t)
	var bp := Blueprint.capture(s.nodes, s.conduits, SEL_LO, SEL_HI)
	var d := SaveService.defaults()
	t.ok(d.has("blueprints"), "新存檔有 blueprints 這一格")
	t.eq(SaveService.add_blueprint(d, bp, 2), "", "存第一張")
	t.eq(SaveService.add_blueprint(d, bp, 2), "", "存第二張")
	var full := SaveService.add_blueprint(d, bp, 2)
	t.ok(full.contains("槽已滿"), "★ 槽滿了要說出來（%s）" % full)
	t.eq((d["blueprints"] as Array).size(), 2, "★ 槽滿時沒有偷偷多存一張")
	# 自動命名認得出是哪一種產線。
	t.eq(String((d["blueprints"] as Array)[0]["name"]), "5×4・3 節點", "自動命名帶尺寸與節點數")
	# 空框選存不進去。
	var blank := Blueprint.capture(s.nodes, s.conduits, Vector2i(0, 12), Vector2i(3, 15))
	t.ok(SaveService.add_blueprint(d, blank, 9).contains("沒有可存的節點"), "空框選有話說")

	# 舊存檔讀進來要長出這一格，且不動原有資料（只增不破）。
	var norm := SaveService.normalize({"sv": 2, "tech": {"unlocked": ["dmg1"], "data": 5.0}})
	t.ok(norm.has("blueprints"), "舊存檔補得出 blueprints")
	t.eq(((norm["tech"] as Dictionary)["unlocked"] as Array).size(), 1, "不動玩家原有資料")
