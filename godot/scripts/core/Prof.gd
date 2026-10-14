extends RefCounted
## 逐段計時（`TL_PROF=1`，B3.15）。
##
## RG-183 之後渲染成本要量**牆上時鐘**，而量到「一幀 21 ms」只回答「慢」，不回答「慢在哪」——
## 慢在哪才決定要改哪一段。這支把每一幀拆成有名字的段落，`TL_STRESS` 跑完時印出每一段平均每幀花幾毫秒。
##
## 用法：一個回呼（`_draw()`、`_process()`）開頭 `Prof.mark()`，之後每段結束 `Prof.lap("名字")`——
## 那一段的耗時就記在名字底下。**關著的時候是一個布林判斷**，所以可以一直留在熱路徑上。
##
## ⚠ 它量的是 GDScript 這一側（指令生成、HUD 更新）。引擎把指令送去 GPU 的成本不在裡面——
##   那一半看 `TL_STRESS` 的整幀牆上時鐘，兩者相減就是引擎那一側。

## `Battle._ready()` 依 `Hooks.prof` 設定。
static var on: bool = false

static var _last_us: int = 0

static var _sum_us: Dictionary = {}


static func mark() -> void:
	if on:
		_last_us = Time.get_ticks_usec()


static func lap(label: String) -> void:
	if not on:
		return
	var now := Time.get_ticks_usec()
	_sum_us[label] = int(_sum_us.get(label, 0)) + (now - _last_us)
	_last_us = now


## 丟掉暖身幀累積的數字（著色器編譯與第一次配置都落在那裡）。
static func reset() -> void:
	_sum_us.clear()


## 每一段平均每幀的毫秒數，由大到小。
static func report(frames: int) -> void:
	if not on or _sum_us.is_empty():
		return
	var rows: Array = []
	var total := 0.0
	for k: String in _sum_us:
		var ms := float(_sum_us[k]) / 1000.0 / float(maxi(1, frames))
		rows.append([k, ms])
		total += ms
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	print("[TL_PROF] GDScript 側每幀合計 %.2f ms（%d 幀平均）" % [total, frames])
	for r: Array in rows:
		if float(r[1]) >= 0.005:
			print("[TL_PROF]   %-18s %6.2f ms" % [r[0], r[1]])
