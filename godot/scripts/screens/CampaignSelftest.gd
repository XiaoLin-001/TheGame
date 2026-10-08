extends RefCounted
## `Campaign.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Campaign.gd` 拆出（B3.14）：只改搬家，不改行為。

const CampaignData := preload("res://data/Campaign.gd")
const Host := preload("res://scripts/screens/Campaign.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=campaign`）。
##
## 這個畫面的全部價值就是**一顆鈕點得到**，而 B0.7.2 教過的事情是：
## 畫得出來不代表點得到（滿版 `Control` 的 `mouse_filter` 會把事件吃掉）。
## 用合成滑鼠事件真的走一次 Godot 的輸入路由，不是直接呼叫 `_enter()`。
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var five: bool = host._enter_buttons.size() == CampaignData.count()
	var first_open: bool = five and not host._enter_buttons[0].disabled
	# 新存檔：第 2 關必須是鎖著的，而且鈕上要寫出解鎖條件。
	var second_locked: bool = five and host._enter_buttons[1].disabled
	var says_why: bool = five and host._enter_buttons[1].text.contains("第 1 關")

	# ★★ **每一張卡都要真的看得到**（B3.3、RG-170）。
	#
	#   ⚠ 這一條在戰役從五關加到八關時**是紅的**：那一版是一條橫列，
	#     第 6 關被切一半、第 7／8 關整個在畫面外——而既有的每一條斷言都是綠的，
	#     因為它們問的是「鈕點得到嗎」，而畫面外的鈕照樣點得到
	#     （`UiKit.click()` 送的是合成事件，不看可見性）。
	#     RG-139／RG-149 的同一句話第三次：**按得到不等於看得到。**
	#
	#   量的是**橫向**：格線改成四欄之後橫向就不該再溢位，而縱向由捲動負責
	#   （最後一顆鈕捲得到，下面另外一條在量）。
	var all_visible := true
	var worst := ""
	for i in host._enter_buttons.size():
		var b: Button = host._enter_buttons[i]
		var l := b.global_position.x
		var r := l + b.size.x
		if l < -0.5 or r > float(host.size.x) + 0.5:
			all_visible = false
			worst = "第 %d 關 x %.0f–%.0f（視窗寬 %d）" % [i + 1, l, r, host.size.x]

	# ★ 最後一關捲得到嗎（科技樹 RG-47／RG-60 的同一條，抄它的做法）。
	if host._scroll != null:
		host._scroll.scroll_vertical = 999999
		await host.get_tree().process_frame
	var last: Button = host._enter_buttons[host._enter_buttons.size() - 1]
	var last_reachable: bool = (
		last.size.y >= 44.0
		and last.global_position.y + last.size.y <= float(host.size.y) + 0.5
		and last.global_position.y >= -0.5
	)
	# ⚠ **捲回頂端再往下測**。上面那一行把捲軸推到底，而第 1 關的卡因此
	#   離開了視野——接著的 `UiKit.click()` 送的是螢幕座標的合成事件，
	#   於是「點第 1 關」當場點空，`entered` 變成 false。
	#   量一件事的動作本身改變了下一件事的前提，這是自檢自己的副作用。
	if host._scroll != null:
		host._scroll.scroll_vertical = 0
		await host.get_tree().process_frame

	await UiKit.click(host._enter_buttons[0])
	# 真的進了局內畫面嗎？（卡片被清掉、Battle 掛上來了）
	var battle: Node = null
	for c: Node in host.get_children():
		if c.get_script() == BattleScreen:
			battle = c
	var entered: bool = battle != null

	# ★ ESC 的歸屬（B1.4.1）。局內畫面是**這個節點的子節點**，兩邊都接了 ESC——
	#   誰先拿到就決定了「戰鬥中按 ESC」是開選單還是被踢回關卡選擇。
	#   Godot 的 `_unhandled_key_input` 由深到淺傳遞，所以應該是 Battle 先吃掉；
	#   但這種「應該」正是 B0.7.2 那個 `mouse_filter` 教訓的形狀，**量一次**。
	var esc_to_battle: bool = false
	if entered:
		UiKit.press_escape()
		for _i in 3:
			await host.get_tree().process_frame
		esc_to_battle = is_instance_valid(battle) and battle.menu.menu_layer != null

	var ok: bool = (
		five and first_open and second_locked and says_why and entered and esc_to_battle
		and all_visible and last_reachable
	)
	print("[TL_CLICKTEST/campaign] cards=%s(%d 關) visible=%s%s last_reach=%s first_open=%s second_locked=%s says_why=%s entered=%s esc_to_battle=%s → %s" % [
		five, CampaignData.count(), all_visible, ("（%s）" % worst) if worst != "" else "",
		last_reachable, first_open, second_locked, says_why, entered, esc_to_battle,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
