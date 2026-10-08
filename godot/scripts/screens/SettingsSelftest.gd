extends RefCounted
## `Settings.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Settings.gd` 拆出（B3.14）：只改搬家，不改行為。

const Motion := preload("res://scripts/render/Motion.gd")
const Host := preload("res://scripts/screens/Settings.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=settings`）。
##
## 這個畫面唯一該問的問題是「拉了滑桿之後，**外面那個東西真的變了嗎**」——
## 一個只寫進字典、沒有接到匯流排／`Motion.reduce`／視窗的設定畫面，
## 看起來和正常的完全一樣（B1.3 那條「買了沒生效的科技」是同一類缺陷）。
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var s := host._settings()

	# ① 音量：拉滑桿 → 存檔的值變了 → **匯流排的分貝也變了**。
	#    有測試鉤子時 `AudioBus.muted` 為真、`apply()` 是空操作（鐵律 2），
	#    所以這裡只驗到「值有寫進去」為止，分貝那一半改用直接呼叫驗。
	(host._sliders["master"] as HSlider).value = 0.5
	await host.get_tree().process_frame
	var vol_saved: bool = is_equal_approx(float(s["master"]), 0.5)
	# 匯流排本身要真的存在（`apply()` 找不到就會靜靜地什麼都不做）。
	var buses_exist: bool = (
		AudioServer.get_bus_index("BGM") >= 0 and AudioServer.get_bus_index("SFX") >= 0
	)
	# ★ 鐵律 2：**靜音時 `apply()` 必須是空操作**。不然「有鉤子就一定不出聲」
	#   這個承諾會變成「取決於這台機器的玩家把音量存成多少」。
	var db_before := AudioBus.volume_db("Master")
	AudioBus.apply({"master": 1.0, "bgm": 1.0, "sfx": 1.0})
	var mute_wins: bool = AudioBus.muted and is_equal_approx(
		AudioBus.volume_db("Master"), db_before
	)

	# ② 減少動態效果：勾了之後 `Motion.reduce` 當場為真、效果壽命歸零。
	host._reduce_check.button_pressed = true
	await host.get_tree().process_frame
	var reduce_live: bool = Motion.reduce and Motion.ticks(Motion.BASE) == 0
	host._reduce_check.button_pressed = false
	await host.get_tree().process_frame
	var reduce_off: bool = not Motion.reduce and Motion.ticks(Motion.BASE) > 0

	# ③ 解析度：點第二顆 → 視窗真的變大 → 再點回來。
	#    **點回來是必要的**：`TL_SHOT` 那條路徑要求同參數拍出同一張圖。
	var before := DisplayServer.window_get_size()
	_press(host._res_buttons[1])
	await host.get_tree().process_frame
	var resized: bool = DisplayServer.window_get_size() == SaveService.RESOLUTIONS[1]
	_press(host._res_buttons[0])
	await host.get_tree().process_frame
	var restored: bool = DisplayServer.window_get_size() == SaveService.RESOLUTIONS[0] and before == before

	# ④ 存檔沒有被真的寫出去（有鉤子時 persist=false，鐵律 1）。
	var no_write: bool = not SaveService.persist

	# ⑤ ★ **整頁留在畫面內**（RG-75 的同一條）。第一版的間距讓最後那行說明
	#    掉到 720 以外，而 `_draw()` 對此一個字都不會說。
	var last: Control = host._col.get_child(host._col.get_child_count() - 1)
	var fits: bool = last.global_position.y + last.size.y <= float(host.size.y)

	# ⑥ ★ ESC ＝ 返回（B1.4.1）。暫時把 `on_exit` 換成一個只翻旗標的 Callable：
	#    真的返回會把這個畫面拆掉，後面的 print 就落在正在被釋放的節點上。
	var esc_back: bool = await UiKit.esc_reaches(host)

	var ok: bool = (
		vol_saved and mute_wins and buses_exist and reduce_live and reduce_off
		and resized and restored and no_write and fits and esc_back
	)
	print("[TL_CLICKTEST/settings] vol=%s buses=%s mute_wins=%s reduce_on=%s reduce_off=%s resize=%s restore=%s no_write=%s fits=%s esc_back=%s → %s" % [
		vol_saved, buses_exist, mute_wins, reduce_live, reduce_off, resized, restored, no_write,
		fits, esc_back, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)


func _press(b: Button) -> void:
	b.grab_focus()
	b.pressed.emit()
