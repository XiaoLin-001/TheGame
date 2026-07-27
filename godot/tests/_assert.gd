extends RefCounted
## 極小斷言工具。
##
## `tests/*.gd` 以 `--script` 執行，**不載入 autoload**（30_TECH_DESIGN.md §4.2），
## 所以這裡不得引用任何 autoload，也不得 preload 任何會引用 autoload 的東西。
## 用 preload 取得：`const T := preload("res://tests/_assert.gd")`

var suite: String = ""
var checks: int = 0
var failures: PackedStringArray = []


func _init(suite_name: String) -> void:
	suite = suite_name


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures.append(what)


func eq(actual: Variant, expected: Variant, what: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s（得到 %s，預期 %s）" % [what, str(actual), str(expected)])


func near(actual: float, expected: float, what: String, eps: float = 0.0001) -> void:
	checks += 1
	if absf(actual - expected) > eps:
		failures.append("%s（得到 %f，預期 %f）" % [what, actual, expected])


## 尚未實作的測項。不算失敗，但一定要印出來——
## 沉默的空測試會讓後面的人誤以為這塊已經被守住了。
func pending(what: String, batch: String) -> void:
	print("  [待補 %s] %s" % [batch, what])


## 回傳行程結束碼：0 = 全過。
func report() -> int:
	if failures.is_empty():
		print("[PASS] %s：%d 項檢查全過" % [suite, checks])
		return 0
	print("[FAIL] %s：%d/%d 項失敗" % [suite, failures.size(), checks])
	for f: String in failures:
		print("  - " + f)
	return 1
