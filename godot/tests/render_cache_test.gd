extends SceneTree
## 渲染快取的失效規則（B3.15，RG-184）。
##
## `Stage2D` 的導管層與節點層只在內容簽章 `（局, tick, s.rev, 縮放）` 變了才重畫。
## **簽章漏掉一個會改動畫面的動作，症狀是畫面停在上一個 tick（最多 0.1 秒）**——
## 蓋了塔卻看不見它、升了級外型沒變，而且沒有任何東西報錯、其他測試全是綠的。
## 所以這支測試對每一支 `BuildController` 動詞釘一條：**成功的動作必須讓 `rev` 變大**。
##
## 這支測試鎖住的設計承諾：
##   ★ 每個會改動「畫面上畫得出來的東西」的動作都讓 `rev` 加一（蓋、拉線、升級、拆除、敵人出場）
##   ★ 失敗的動作**不**讓 `rev` 動（畫面不該為一個被拒絕的點擊白白重畫）
##   ★ `rev` 不是遊戲狀態：不進 `state_hash()`（重播與每日挑戰的公平性不能被「畫面要不要重畫」影響）
##   ★ 快取層：簽章沒變不重畫、變了就畫、`invalidate()` 之後一定畫；視野沒變不動 transform
##
## 實機那一半（連點擊都走完整輸入路由、畫面真的跟上）在 `TL_CLICKTEST` 的 `cache` 段落。
##
## 跑法：<godot> --headless --path godot --script res://tests/render_cache_test.gd

const T := preload("res://tests/_assert.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const StageLayer := preload("res://scripts/screens/battle/StageLayer.gd")


func _initialize() -> void:
	var t := T.new("render_cache_test", 40)
	_every_build_verb_bumps_rev(t)
	_refused_actions_do_not_bump(t)
	_rev_is_not_game_state(t)
	_layer_redraws_only_when_the_key_changes(t)
	_layer_follows_the_view(t)
	quit(t.report())


func _session() -> RefCounted:
	var s := SessionState.new()
	s.setup(Maps.SHOAL)
	s.ore = 100000.0
	s.alloy = 100000.0
	return s


## 每一支成功的動詞都讓 `rev` 變大。順序就是一局裡的順序：蓋 → 拉線 → 升級 → 拆。
func _every_build_verb_bumps_rev(t: T) -> void:
	var s := _session()
	t.ok(s.rev > 0, "開局就算一次（核心也是一個節點）")

	var r: int = s.rev
	t.eq(BuildController.place(s, "relay", Vector2i(6, 12)), Build.OK, "前置：中繼蓋得下")
	t.ok(s.rev > r, "place：蓋節點")
	r = s.rev
	BuildController.place(s, "relay", Vector2i(6, 14))
	t.ok(s.rev > r, "place：第二座")

	r = s.rev
	t.eq(BuildController.lay_conduit(s, Vector2i(6, 12), Vector2i(6, 14)), Build.OK, "前置：導管拉得起來")
	t.ok(s.rev > r, "lay_conduit：拉線")

	r = s.rev
	t.eq(BuildController.upgrade(s, 0), Build.OK, "前置：導管升得了級")
	t.ok(s.rev > r, "upgrade：幹線加粗（線寬與刻度會變）")

	r = s.rev
	t.eq(BuildController.upgrade_node(s, Vector2i(6, 12)), Build.OK, "前置：節點升得了級")
	t.ok(s.rev > r, "upgrade_node：節點升級（體積與零件會變）")

	r = s.rev
	t.eq(BuildController.demolish_conduit(s, 0), Build.OK, "前置：導管拆得掉")
	t.ok(s.rev > r, "demolish_conduit：拆導管")

	r = s.rev
	t.eq(BuildController.demolish(s, Vector2i(6, 14)), Build.OK, "前置：節點拆得掉")
	t.ok(s.rev > r, "demolish：拆節點")

	r = s.rev
	var failures := BuildController.apply_ops(s, [["place", "relay", Vector2i(8, 12)]])
	t.ok(failures.is_empty() and s.rev > r, "apply_ops（藍圖與示範佈局走的路）：每一步都經過同一支 place")

	r = s.rev
	s.add_enemy("drifter")
	t.ok(s.rev > r, "add_enemy：敵人出場（受威脅的格與光環會變）")


func _refused_actions_do_not_bump(t: T) -> void:
	var s := _session()
	var r: int = s.rev
	# 路徑格不能蓋；升級不存在的導管；拆一個空格。
	t.ok(BuildController.place(s, "relay", Vector2i(12, 4)) != Build.OK, "前置：路徑格蓋不下")
	t.ok(BuildController.upgrade(s, 99) != Build.OK, "前置：不存在的導管升不了")
	t.ok(BuildController.upgrade_node(s, Vector2i(30, 2)) != Build.OK, "前置：空格升不了")
	t.eq(s.rev, r, "被拒絕的動作不讓畫面重畫")


## 同樣的操作、不同的 `rev` → 同一個 `state_hash()`。
func _rev_is_not_game_state(t: T) -> void:
	var a := _session()
	var b := _session()
	BuildController.place(a, "relay", Vector2i(6, 12))
	BuildController.place(b, "relay", Vector2i(6, 12))
	t.eq(a.rev, b.rev, "同一組操作得到同一個 rev（它是操作的函式，不是計時）")
	b.rev += 1000
	t.eq(a.state_hash(), b.state_hash(), "rev 不進 state_hash")


func _layer_redraws_only_when_the_key_changes(t: T) -> void:
	var l := StageLayer.new()
	t.ok(l.refresh([1, 2]), "第一次一定畫")
	t.eq(l.redraws, 1, "第一次：重畫 1 次")
	t.ok(not l.refresh([1, 2]), "簽章沒變：不重畫")
	t.ok(not l.refresh([1, 2]), "簽章沒變：連續幾幀都不重畫")
	t.eq(l.redraws, 1, "沒變的那幾幀：仍是 1 次")
	t.ok(l.refresh([1, 3]), "簽章變了：重畫")
	t.eq(l.redraws, 2, "變了：2 次")
	l.invalidate()
	t.ok(l.refresh([1, 3]), "invalidate 之後：同一個簽章也重畫")
	t.eq(l.redraws, 3, "invalidate 之後：3 次")
	l.repaint()
	t.eq(l.redraws, 4, "repaint：不問簽章，直接畫")
	# 簽章裡有浮點（縮放）與巢狀陣列也要比得對。
	t.ok(l.refresh([7, 1.5, true]), "換成另一種形狀的簽章：重畫")
	t.ok(not l.refresh([7, 1.5, true]), "浮點簽章相同：不重畫")
	t.ok(l.refresh([7, 1.5000001, true]), "縮放只差一點點也算變了（刻度寬度跟著倍率走）")
	l.free()


func _layer_follows_the_view(t: T) -> void:
	var l := StageLayer.new()
	l.place(Vector2(10, 20), 2.0)
	t.eq(l.position, Vector2(10, 20), "place：地圖原點")
	t.eq(l.scale, Vector2(2, 2), "place：縮放")
	# 視野沒變時什麼都不做（不去碰 transform，引擎就不必重算那一層的矩陣）。
	l.position = Vector2(1, 1)
	l.place(Vector2(10, 20), 2.0)
	t.eq(l.position, Vector2(1, 1), "place：視野沒變 ＝ 空操作")
	l.place(Vector2(10, 25), 2.0)
	t.eq(l.position, Vector2(10, 25), "place：平移了就跟上")
	l.place(Vector2(10, 25), 3.0)
	t.eq(l.scale, Vector2(3, 3), "place：縮放了就跟上")
	l.free()
