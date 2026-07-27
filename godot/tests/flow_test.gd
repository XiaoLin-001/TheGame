extends SceneTree
## 流量網路解算器（30_TECH_DESIGN.md §2.5、50_QA_PLAN.md §2）。
##
## **B0.2 才會有東西可測**（`scripts/sim/FlowNetwork.gd` 尚未存在）。
## 這支檔案現在的職責是：可執行、退出碼 0、並且**把待測清單印出來**——
## 沉默的空測試會讓後面的人誤以為這塊已經被守住了。
##
## 跑法：<godot> --headless --path godot --script res://tests/flow_test.gd

const T := preload("res://tests/_assert.gd")


func _initialize() -> void:
	var t := T.new("flow_test")

	t.pending("單線滿載：supply 20 / cap 10 → flow 恆為 10", "B0.2")
	t.pending("容量削減：請求超過 cap 時下游按優先權等比例削減", "B0.2")
	t.pending("三方競爭：priority 讀的是「節點類型」的值，不是節點自己的欄位", "B0.2")
	t.pending("環路收斂：3 次迭代上限，結果穩定不抖動", "B0.2")
	t.pending("飢餓：satisfaction = 實得/需求，產出與射速線性縮放（不停機）", "B0.2")
	t.pending("儲槽充放電受自身導管 cap 約束（300 容量接 cap 10 → 最多放 10/秒）", "B0.2")
	t.pending("無全域資源池：斷開儲槽後網路即無任何緩衝", "B0.2")
	t.pending("不變量：採集器無輸入需求 → 任意拓樸下產出恆 > 0，網路永不死鎖", "B0.2")

	quit(t.report())
