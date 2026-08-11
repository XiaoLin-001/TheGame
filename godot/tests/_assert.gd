extends RefCounted
## 極小斷言工具。
##
## `tests/*.gd` 以 `--script` 執行，**不載入 autoload**（30_TECH_DESIGN.md §4.2），
## 所以這裡不得引用任何 autoload，也不得 preload 任何會引用 autoload 的東西。
## 用 preload 取得：`const T := preload("res://tests/_assert.gd")`

var suite: String = ""
var checks: int = 0
var failures: PackedStringArray = []
## ★ 這一支測試至少要跑幾條斷言（B3.2、RG-164）。
##
## **為什麼需要這個數字**：GDScript 的執行期錯誤（例：讀一個已經不存在的鍵）
## 會**中止那一支函式**，而不是讓斷言變紅。後面的斷言於是整段沒有跑到，
## 而 `report()` 看到「沒有失敗」就印 PASS——**一支被攔腰截斷的測試，
## 和一支全過的測試，長得一模一樣**，差別只有一個沒有人在看的數字。
##
## B2.6 把 `endless.best_wave` 改成 `endless.best` 之後，`endless_test._best()`
## 就是這樣安靜地少跑了九條斷言，而且**連跑三批都是綠的**。
##
## 下限只擋「變少」，不擋「變多」——加內容本來就會讓數字長上去。
var min_checks: int = 0


func _init(suite_name: String, minimum: int = 0) -> void:
	suite = suite_name
	min_checks = minimum


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
	if checks < min_checks:
		failures.append(
			"★ 斷言數 %d < 下限 %d——有一支函式提早中止了（執行期錯誤不會變紅，只會少跑）"
			% [checks, min_checks]
		)
	if failures.is_empty():
		print("[PASS] %s：%d 項檢查全過" % [suite, checks])
		return 0
	print("[FAIL] %s：%d/%d 項失敗" % [suite, failures.size(), checks])
	for f: String in failures:
		print("  - " + f)
	return 1
