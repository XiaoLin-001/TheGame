extends RefCounted
## `Tech.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Tech.gd` 拆出（B3.14）：只改搬家，不改行為。

const Host := preload("res://scripts/screens/Tech.gd")
const Levels := preload("res://data/Levels.gd")
const Tech := preload("res://data/Tech.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tech`）。
##
## 和關卡選擇同一個理由：這個畫面的全部價值就是「一顆鈕點得到、而且真的扣款」。
## 存檔在有鉤子時是預設值（研究數據 0），所以先塞一筆數據進去再點——
## **不寫檔**（`SaveService.persist=false`），玩家的真實進度碰不到。
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var twelve: bool = host._buttons.size() == Tech.count()
	# 新存檔：研究數據 0 → 每一顆都買不起；第二階還要前置。
	var all_broke: bool = twelve and host._buttons[0].disabled
	# ★ 等級軸（B2.7）也一樣：零材料 → 兩顆都是關的。
	#
	# ⚠ **這一條要在買科技之前量。** 第一版放在後面，量到的是 `disabled=false`
	#   ——因為買下 `cap1` 當場達成了成就「第一項科技」，15 材料立刻進帳。
	#   斷言是錯的，程式是對的：那正是「成就沒有領取鈕」該有的樣子。
	var broke_levels: bool = host._level_buttons.size() == 2 and host._level_buttons[0].disabled

	var tech: Dictionary = GameState.data["tech"]
	tech["data"] = 500.0
	host._build()
	await host.get_tree().process_frame
	var first_open: bool = host._buttons[0].text.contains("解鎖")and not host._buttons[0].disabled
	# 第二階（cap2）在第一階還沒買之前必須是鎖著的，而且要說出原因。
	var tier2_locked: bool = host._buttons[1].disabled and host._buttons[1].text.contains("導管擴容 I")

	await UiKit.click(host._buttons[0])
	var unlocked: Array = tech["unlocked"]
	var bought: bool = unlocked.has("cap1")
	var charged: bool = is_equal_approx(float(tech["data"]), 500.0 - float(Tech.cost("cap1")))
	# 買完第一階，第二階就該開了——路線圖要當場往前走一格。
	var tier2_open: bool = not host._buttons[1].disabled

	# ★ **最後一顆鈕到得了嗎**（RG-47／RG-60）。捲到底之後它必須整顆在畫面內——
	#   第一版沒有捲動容器，最長那一支的第 5 張卡直接被推到 720 以外，
	#   而畫面上看起來只是「這一欄比較短」。
	host._scroll.scroll_vertical = 999999
	await host.get_tree().process_frame
	var last: Button = host._buttons[host._buttons.size() - 1]
	var reachable: bool = (
		last.size.y >= 44.0
		and last.global_position.y + last.size.y <= float(host.size.y)
		and last.global_position.y >= 0.0
	)

	# ★ 等級軸（B2.7）。存檔在有鉤子時是零級零材料 → 兩顆都該是關的；
	#   塞一筆局末材料進去（**不寫檔**）之後才點得下去。
	(GameState.data["levels"] as Dictionary)["from_battle"] = 500
	host._build()
	await host.get_tree().process_frame
	var lv_open: bool = not host._level_buttons[0].disabled
	var before := host._components()
	await UiKit.click(host._level_buttons[0])
	var lv_up: bool = Levels.level_of(GameState.data, Levels.TOWER) == 1
	# **餘額是推導的**（`Progress.components()`），所以「有沒有真的扣款」
	# 問的是那一支——不是去看某個欄位有沒有被減。
	var lv_charged: bool = host._components() == before - Levels.cost(0)

	# ★ ESC ＝ 返回（B1.4.1）。**不能真的呼叫 `on_exit`**（那會把這個畫面拆掉，
	#   後面的 print 就落在一個正在被釋放的節點上），所以暫時換成一個只翻旗標的
	#   Callable：要驗的是「事件到不到得了這支處理器」，不是返回本身。
	var esc_back: bool = await UiKit.esc_reaches(host)

	var ok: bool = (
		twelve and all_broke and first_open and tier2_locked
		and bought and charged and tier2_open and reachable and esc_back
		and broke_levels and lv_open and lv_up and lv_charged
	)
	print("[TL_CLICKTEST/tech] twelve=%s broke=%s first_open=%s tier2_locked=%s bought=%s charged=%s tier2_open=%s last_reachable=%s esc_back=%s lv_broke=%s lv_open=%s lv_up=%s lv_charged=%s → %s" % [
		twelve, all_broke, first_open, tier2_locked, bought, charged, tier2_open, reachable,
		esc_back, broke_levels, lv_open, lv_up, lv_charged, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
