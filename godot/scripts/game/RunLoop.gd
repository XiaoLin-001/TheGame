extends RefCounted
## 固定時間步的驅動（`30_TECH_DESIGN.md` §2.4）。B3.14 自 `screens/Battle.gd` 的 `_process()` 抽出。
##
## 畫面每幀把 `delta` 餵進來，這裡決定要推幾個 tick。**模擬永遠不吃 `delta`**——
## 同一組操作在 30fps 與 144fps 下必須跑出同一個結果，所以 `delta` 只進累加器。
##
## 純函式、零副作用、不引用 autoload：3D 畫面與 headless 測試共用這一份。

const BattleController := preload("res://scripts/game/BattleController.gd")


## 推進模擬，回傳新的累加器。
##
## 快進＝**多跑幾個 tick**，不是把 tick 拉長。固定時間步不能動，否則同一組操作在
## 不同倍率下會跑出不同結果（§2.4 確定性）。快進只在準備期有效，戰鬥期恆為 1。
## `guard` 是單幀的 tick 上限：卡頓一次補太多 tick 會讓下一幀更卡（死亡螺旋）。
static func advance(s: RefCounted, accum: float, delta: float) -> float:
	accum += delta
	var mult: int = s.speed_mult if s.phase == "prep" else 1
	var guard := 0
	while accum >= BattleController.TICK and guard < 8 * mult:
		for _i in mult:
			BattleController.step(s)
		accum -= BattleController.TICK
		guard += mult
	return accum
