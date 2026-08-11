extends SceneTree
## 開發用的單關試跑台（B3.3）。**不是回歸測試**——回歸是 `campaign_test.gd`。
##
## 它存在的理由只有一個：`campaign_test` 跑完五關要三分鐘，而調一關的參考解
## 要跑十幾次。拿三分鐘的迴圈去調參考解，實務上的結果是「少調幾次就宣稱好了」。
##
## 跑法：TL_LEVELS=6,7 <godot> --headless --path godot --script res://tests/_play_one.gd
##       不給 TL_LEVELS 就跑全部。

const Campaign := preload("res://data/Campaign.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Score := preload("res://scripts/sim/Score.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")

const MAX_TICKS := 9000


func _initialize() -> void:
	var want: Array = []
	var env := OS.get_environment("TL_LEVELS")
	if env != "":
		for part: String in env.split(","):
			want.append(int(part.strip_edges()))

	var bad := 0
	for i in Campaign.count():
		if not want.is_empty() and not want.has(i + 1):
			continue
		var lv: Dictionary = Campaign.at(i)
		var s: RefCounted = SessionState.new()
		s.setup(lv["map"], lv["unlocked"])
		var step := func(st: RefCounted) -> void: BattleController.step(st)
		var failures: Array = BuildController.apply_timeline(s, lv["demo"], step)
		while s.tick_count < MAX_TICKS and s.phase != "won" and s.phase != "lost":
			BattleController.step(s)
		var tp := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
		var maxhp := NodeDefs.hp("core")
		var mark := "✔" if s.phase == "won" and failures.is_empty() else "✕"
		print("%s 第 %d 關「%s」 phase=%s tick=%d 核心 %.0f/%.0f 擊殺 %d 產能 %.2f（門檻 %.2f）礦 %.0f" % [
			mark, i + 1, (lv["map"] as Dictionary)["name"], s.phase, s.tick_count,
			s.core_hp(), maxhp, s.kills, tp, lv["star_throughput"], s.ore,
		])
		if not failures.is_empty():
			print("    建造失敗 %d 筆：" % failures.size())
			for f: Variant in failures:
				print("      %s　← %s" % [f, _resolve(lv["demo"], f)])
		if s.phase != "won" or not failures.is_empty():
			bad += 1
	quit(bad)


## ★ 失敗索引 → 那一筆真正的指令。
##
## ⚠ `apply_timeline()` 回傳的索引是**該段（兩個 `wait` 之間）之內**的索引，
## 不是整份腳本的索引——它自己的註解就寫著這件事。第一版直接拿它去索引整份
## `demo`，於是**第一段以後的每一筆失敗都指到別的指令上**：我照著它給的座標
## 去查一格明明是空的地圖，查了三輪。
## 一個會說謊的診斷比沒有診斷更貴。
static func _resolve(demo: Array, f: Variant) -> String:
	var fd: Dictionary = f
	var want := int(fd.get("index", -1))
	var seg := 1
	var i := 0
	for op: Array in demo:
		if String(op[0]) == "wait":
			seg += 1
			i = 0
			continue
		if i == want and String(op[0]) == String(fd.get("op", "")):
			return "第 %d 段第 %d 筆 = %s" % [seg, want, op]
		i += 1
	return "（對不上，第 %d 段之內的第 %d 筆）" % [seg, want]
