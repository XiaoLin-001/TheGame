extends RefCounted
## `DailyScreen.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `DailyScreen.gd` 拆出（B3.14）：只改搬家，不改行為。

const Daily := preload("res://scripts/sim/Daily.gd")
const Host := preload("res://scripts/screens/DailyScreen.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=daily`）。
##
## 這個畫面的價值就是「兩顆鈕點得到，而且點下去進的是**今天那張圖**」，
## 所以斷言看的是實際開出來的局面，不是回呼有沒有被叫到（B2.1a 的假綠燈：
## 印 `endless=true` 而遊戲開的是淺灘）。
func run() -> void:
	await host.get_tree().process_frame
	var two: bool = host._buttons.size() == 2
	var d := host.today()
	var want_seed := Daily.seed_of(d["year"], d["month"], d["day"])
	# 誠實註記真的在畫面上——它是規格的一部分（§3.10），不是可有可無的裝飾。
	var honest := false
	for node: Node in host.find_children("*", "Label", true, false):
		if (node as Label).text.contains("還沒有對手"):
			honest = true
	# ⚠ **GDScript 的 lambda 對區域變數是傳值捕捉**：在裡面寫 `started = {...}`
	#   改的是它自己那一份副本，外面永遠讀到空字典（斷言會恆為 false）。
	#   一律**變更同一個字典**，中間清空也要用 `clear()` 而不是重新賦值。
	var started: Dictionary = {}
	host.on_start = func(board: String, date: String, sd: int) -> void:
		started["board"] = board
		started["date"] = date
		started["seed"] = sd
	if two:
		host._buttons[0].emit_signal("pressed")
	await host.get_tree().process_frame
	var uniform_ok: bool = (
		String(started.get("board", "")) == Daily.UNIFORM
		and int(started.get("seed", 0)) == want_seed
	)
	started.clear()
	if two:
		host._buttons[1].emit_signal("pressed")
	await host.get_tree().process_frame
	var free_ok: bool = String(started.get("board", "")) == Daily.FREE
	var ok: bool = two and honest and uniform_ok and free_ok
	print("[TL_CLICKTEST/daily] two=%s honest=%s uniform=%s(seed=%d) free=%s → %s" % [
		two, honest, uniform_ok, want_seed, free_ok, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
