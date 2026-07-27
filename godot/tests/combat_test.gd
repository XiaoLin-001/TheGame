extends SceneTree
## 戰鬥計算（30_TECH_DESIGN.md §4.2、50_QA_PLAN.md §2）。
##
## **B0.5 才會有東西可測**（`scripts/sim/Combat.gd` 尚未存在）。
## 現在先把待測清單釘在這裡，其中「礦砂↔能量匯率 1:5」是 grilling 定案的
## 硬性數字（CLAUDE.md 鎖定設計）——照字面 1:1 的話回收者是淨耗電，
## 「打破峰值約束的鑰匙」會是假的，所以那條斷言不能漏。
##
## 跑法：<godot> --headless --path godot --script res://tests/combat_test.gd

const T := preload("res://tests/_assert.gd")


func _initialize() -> void:
	var t := T.new("combat_test")

	t.pending("護甲：物理傷害減法減免", "B0.5")
	t.pending("屏障：能量傷害百分比減免", "B0.5")
	t.pending("交戰耗能每秒扣除、待機耗能為 0", "B0.5")
	t.pending("能量不足：實際射速 = 基礎射速 × 滿足率（線性、不停火）", "B0.5")
	t.pending("潮鳴光環強度同樣按滿足率縮放", "B0.5")
	t.pending("全域擊殺回收：任何塔擊殺回收敵人價值 25% 為礦砂", "B0.5")
	t.pending("回收者：射程內任何死亡（不限自己擊殺）回收價值 60%", "B0.5")
	t.pending("★ 匯率斷言：礦砂→能量為 1:5（價值 ×0.6 ×5 才是注入電網的能量）", "B0.5")

	quit(t.report())
