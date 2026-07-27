extends SceneTree
## 確定性（30_TECH_DESIGN.md §2.4、50_QA_PLAN.md §2）。
##
## 最終形態是「同一組 (seed, ops) 跑兩次，最終狀態雜湊完全相同」，
## 那要等 B0.2 的 FlowNetwork 與 B0.7 的完整局。
##
## 但**整個確定性故事踩在的那條性質現在就可以測**：有種子的產生器必須
## 同種子同序列、不同種子不同序列。先把它守住，B0.2 起再往上疊。
##
## 跑法：<godot> --headless --path godot --script res://tests/determinism_test.gd

const T := preload("res://tests/_assert.gd")
const RngLib := preload("res://scripts/core/Rng.gd")
const Shp := preload("res://scripts/render/Shapes.gd")


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

	t.pending("同 (seed, ops) 的完整局狀態雜湊比對", "B0.7")

	quit(t.report())


func _sequence(r: RandomNumberGenerator, n: int) -> PackedInt64Array:
	var out: PackedInt64Array = []
	for i in n:
		out.append(r.randi())
	return out
