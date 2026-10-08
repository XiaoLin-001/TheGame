extends RefCounted
## 渲染壓力量測（TL_STRESS）。開發用。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

## `TL_STRESS`：丟掉的暖身幀數與實際量測幀數。
const STRESS_WARMUP := 30

const STRESS_FRAMES := 240

## `TL_STRESS` 的量測狀態。
var _stress_frames: int = 0

var _stress_total: float = 0.0

var _stress_worst: float = 0.0

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ 渲染壓力量測（`TL_STRESS=1`，B1.7）。
##
## **模擬是凍結的**，所以這裡量到的是純粹的「畫 547 個節點 ＋ 2045 條導管 ＋
## 200 隻敵人要多久」。前 30 幀丟掉（著色器編譯與第一次配置都落在那裡），
## 之後取平均與最壞值——**最壞值才是玩家感覺得到的那一下卡頓**。
func frame(delta: float) -> void:
	_stress_frames += 1
	if _stress_frames <= STRESS_WARMUP:
		return
	_stress_total += delta
	_stress_worst = maxf(_stress_worst, delta)
	var n := _stress_frames - STRESS_WARMUP
	if n < STRESS_FRAMES:
		return
	var avg := _stress_total / float(n)
	print("[TL_STRESS] 節點 %d／導管 %d／敵人 %d　→　平均 %.2f ms（%.0f FPS）／最壞 %.2f ms　量了 %d 幀" % [
		battle.s.nodes.size(), battle.s.conduits.size(), battle.s.enemies.size(),
		avg * 1000.0, 1.0 / maxf(avg, 0.000001), _stress_worst * 1000.0, n
	])
	# 60 FPS ＝ 16.7ms；45 FPS（§5 的最低可接受）＝ 22.2ms。
	print("[TL_STRESS] 60FPS 目標 16.67ms／45FPS 底線 22.22ms → %s" % (
		"通過（60FPS）" if avg <= 0.01667
		else ("勉強（45FPS 以上）" if avg <= 0.02222 else "不通過")
	))
	battle.get_tree().quit(0)
