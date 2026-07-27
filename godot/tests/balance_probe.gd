extends SceneTree
## 平衡探針（30_TECH_DESIGN.md §4.2、50_QA_PLAN.md §2）。
##
## 這**不是斷言型測試**——它跑標準關卡 N 波，把經濟曲線輸出成 JSON 供人工核對。
## 用途：GDD §7 的數值校準、R-12（P2W 數值膨脹）的「等級軸滿級 × 各難度層」驗證。
##
## **B1.3 才有東西可跑**（需要模擬層與科技樹）。現在只驗證輸出格式可被解析，
## 讓下游工具現在就能接上。
##
## 跑法：<godot> --headless --path godot --script res://tests/balance_probe.gd

const T := preload("res://tests/_assert.gd")


func _initialize() -> void:
	var t := T.new("balance_probe")

	var report := {
		"schema": "tl.balance_probe/1",
		"waves": [],
		"peak_power": {},
		"note": "B0.1：模擬層尚未建立，此為輸出格式骨架",
	}
	var round_trip: Variant = JSON.parse_string(JSON.stringify(report))
	t.ok(round_trip is Dictionary, "輸出格式可被 JSON 往返解析")
	t.eq((round_trip as Dictionary).get("schema"), "tl.balance_probe/1", "schema 版本標記正確")

	t.pending("跑標準關卡 N 波，輸出每波的礦砂／能量收支曲線", "B1.3")
	t.pending("峰值電力表：對照 GDD §7.4 的四種配置情境", "B1.3")
	t.pending("等級軸滿級 × 各難度層的碾壓檢定（R-12）", "B2.6")

	quit(t.report())
