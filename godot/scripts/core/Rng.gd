extends Node
## 種子的唯一擁有者（autoload）。
##
## 為什麼要有這一層：`scripts/sim/` 禁用 `randf()`／`randi()`（30_TECH_DESIGN.md §2.4），
## 一律使用「注入的、有種子的」產生器。種子要能被 TL_SEED 覆寫，才能重現特定局面；
## 每日挑戰的公平性、重播、可驗證榜單都踩在這件事上。
##
## 用法：模擬層**不要**直接用這個 autoload（那是隱性全域狀態，會破壞純函式性）。
## 呼叫 `Rng.stream(seed)` 拿一個獨立產生器，當參數傳進去。

var seed_value: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var s := Env.int_of("TL_SEED", 0)
	if s == 0:
		_rng.randomize()
		s = int(_rng.seed)
	set_seed(s)
	if Env.has("TL_SEED"):
		print("[TL_SEED] seed=%d" % seed_value)


func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s


## 取得一個獨立的、確定性的產生器。同 seed 必產生同序列。
## 模擬層要用隨機時，一律拿這個當參數傳入，不要碰全域狀態。
static func stream(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## UI／演出用的非確定性隨機（粒子抖動之類）。
## **絕對不要**在 scripts/sim/ 裡呼叫它。
func cosmetic() -> RandomNumberGenerator:
	return _rng
