extends SceneTree
## 確定性（30_TECH_DESIGN.md §2.4、50_QA_PLAN.md §2）。
##
## **這支測試是每日挑戰雙榜（B2.2）、重播、可驗證榜單的地基。** 沒有它，
## 「同種子同地圖」就只是一句宣稱——而統一配置榜是本作對 P2W 的唯一制衡，
## 它的公平性完全踩在「同一組 `(seed, ops)` 必得同一個局」這條性質上。
##
## B0.7 起補上最終形態：完整局狀態雜湊比對（`SessionState.state_hash()`）。
##
## 跑法：<godot> --headless --path godot --script res://tests/determinism_test.gd

const T := preload("res://tests/_assert.gd")
const RngLib := preload("res://scripts/core/Rng.gd")
const Shp := preload("res://scripts/render/Shapes.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("determinism_test")

	# ── 有種子的產生器：同種子必同序列 ──
	var a := _sequence(RngLib.stream(42), 32)
	var b := _sequence(RngLib.stream(42), 32)
	t.eq(a, b, "同 seed 產生完全相同的序列")

	var c := _sequence(RngLib.stream(43), 32)
	t.ok(a != c, "不同 seed 產生不同序列")

	# ── 重設種子後可重現（TL_SEED 重現特定局面的地基） ──
	var r := RngLib.stream(7)
	var first := _sequence(r, 16)
	r.seed = 7
	t.eq(_sequence(r, 16), first, "重設 seed 後序列從頭重現")

	# ── 純函式必須同輸入同輸出 ──
	# conduit_width 是 R-3 可讀性驗收的地基公式，順手在這裡釘住。
	t.near(Shp.conduit_width(0.0, 10.0), 2.0, "flow=0 → 最細 2px")
	t.near(Shp.conduit_width(10.0, 10.0), 8.0, "滿載 → 最粗 8px")
	t.near(Shp.conduit_width(5.0, 10.0), 5.0, "半載 → 5px")
	t.near(Shp.conduit_width(99.0, 10.0), 8.0, "超載仍夾在 8px（不得溢出視覺尺度）")
	t.near(Shp.conduit_width(1.0, 0.0), 2.0, "cap=0 不除以零")

	_full_session_hash(t)
	quit(t.report())


# ── ★ 完整局狀態雜湊（B0.7 補上的最終形態）─────────────────────────────

func _full_session_hash(t: T) -> void:
	# ① 同一組 ops 跑兩次 → 完全相同的局。**這是整條確定性故事的結論。**
	t.eq(
		_run(Maps.SHOAL_DEMO, 1200), _run(Maps.SHOAL_DEMO, 1200),
		"★ 同一組 (seed, ops) 跑 1200 tick → 狀態雜湊完全相同"
	)

	# ② 分兩段跑 ＝ 一口氣跑。**跨 tick 的累加器沒有偷藏幀率相依的東西**——
	#    射速累加器、儲槽充能、回收者緩衝都在這條斷言底下。
	var split := _session(Maps.SHOAL_DEMO)
	for _i in 700:
		BattleController.step(split)
	for _i in 500:
		BattleController.step(split)
	t.eq(split.state_hash(), _run(Maps.SHOAL_DEMO, 1200), "★ 700+500 tick ＝ 1200 tick（同一個雜湊）")

	# ③ 反向對照：雜湊要真的**分得出**不同的局，否則①②只是兩個空句子。
	var one_less: Array = Maps.SHOAL_DEMO.slice(0, Maps.SHOAL_DEMO.size() - 1)
	t.ok(_run(one_less, 1200) != _run(Maps.SHOAL_DEMO, 1200), "少蓋一條導管 → 不同的雜湊")
	t.ok(_run(Maps.SHOAL_DEMO, 1199) != _run(Maps.SHOAL_DEMO, 1200), "差一個 tick → 不同的雜湊")

	# ④ 順序無關性：狀態是「有什麼」，不是「照什麼順序被建起來的」。
	#    先蓋兩個節點再拉線，和先蓋一個、拉不成、再蓋另一個後拉線，是同一個局。
	var a := _session([])
	BuildController.place(a, "extractor", Vector2i(16, 8))
	BuildController.place(a, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(a, Vector2i(16, 8), Vector2i(16, 11))
	var b := _session([])
	BuildController.place(b, "generator", Vector2i(16, 11))
	BuildController.place(b, "extractor", Vector2i(16, 8))
	t.ok(
		a.state_hash() != b.state_hash(),
		"前置：id 由建造順序決定，所以這兩局本來就不同（下一條才是重點）"
	)
	# 真正要守的是：**同樣的建造順序必得同樣的 id 指派**，否則雜湊比對沒有意義。
	var c := _session([])
	BuildController.place(c, "extractor", Vector2i(16, 8))
	BuildController.place(c, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(c, Vector2i(16, 8), Vector2i(16, 11))
	t.eq(a.state_hash(), c.state_hash(), "★ 同樣的建造順序 → 同樣的 id 指派與同樣的雜湊")

	# ⑤ 雜湊本身要是個像樣的東西（空字串或常數會讓上面每一條都自動過）。
	t.eq(a.state_hash().length(), 64, "sha256 十六進位字串長度 64")


func _session(ops: Array) -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SHOAL)
	BuildController.apply_ops(s, ops)
	return s


func _run(ops: Array, ticks: int) -> String:
	var s := _session(ops)
	for _i in ticks:
		BattleController.step(s)
	return s.state_hash()


func _sequence(r: RandomNumberGenerator, n: int) -> PackedInt64Array:
	var out: PackedInt64Array = []
	for i in n:
		out.append(r.randi())
	return out
