extends RefCounted
## `TycoonOrders.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `TycoonOrders.gd` 拆出（B3.14）：只改搬家，不改行為。

const TycoonLinesScreen := preload("res://scripts/screens/TycoonLines.gd")
const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")
const Host := preload("res://scripts/screens/TycoonOrders.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tycoon`）。
##
## 走完整條循環：**接單 → 產線編輯指派 → 回來 → 快轉 → 收成 → 擴廠**。
## 每一步都用合成滑鼠事件，因為要驗的是事件路由得到（B0.7.2 那一課）。
##
## 存檔在有鉤子時是預設值（廠等 1、零資金），所以：
##   · 接單與指派靠真的點鈕
##   · **「時間過去了」直接呼叫 `accrue()`**——合成不出一分鐘的等待，
##     而那一段本來就由 `tycoon_test` 驗（含離線上限與時鐘倒退）
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var s := host._state()

	var starts_clean: bool = (
		int(s["level"]) == 1 and int(s["credits"]) == 0 and (s["orders"] as Array).is_empty()
	)
	# 廠等 1 只接得到第 1 階，而且接單上限是 3。
	var offers_one_tier: bool = host._accept_buttons.size() == 1

	await UiKit.click(host._accept_buttons[0])
	var accepted: bool = (s["orders"] as Array).size() == 1

	# 產線編輯：進得去、指派得了、回得來。
	await UiKit.click(host._lines_button)
	var lines_screen := _lines_child()
	var opened: bool = lines_screen != null
	var assigned := false
	if opened:
		await UiKit.click(lines_screen._assign_buttons[0])
		assigned = TycoonSim.order_on_line(s, 0) == 0
		await UiKit.click(lines_screen._back_button)
	# ★ 回來之後**訂單板要重畫**——`_build()` 沒被呼叫的話畫面會停在舊資料上，
	#   而它看起來完全正常（就是不會更新）。斷言看的是「有沒有收成鈕」。
	var returned: bool = _lines_child() == null and host._accept_buttons.size() == 1

	# 快轉到做完（見上：這一段的規則由 `tycoon_test` 驗）。
	TycoonSim.accrue(s, TycoonSim.work_of(1))
	host._build()
	await host.get_tree().process_frame
	var collectable: bool = host._collect_buttons.size() == 1

	await UiKit.click(host._collect_buttons[0])
	var collected: bool = (
		int(s["credits"]) == TycoonSim.reward_of(1) and (s["orders"] as Array).is_empty()
	)

	# 擴廠：**先確認它是灰的**（零資金買不起），塞夠錢之後才變得可按。
	var expand_gated: bool = host._expand_button.disabled
	s["credits"] = TycoonSim.expand_cost(1)
	host._build()
	await host.get_tree().process_frame
	await UiKit.click(host._expand_button)
	var expanded: bool = int(s["level"]) == 2 and int(s["credits"]) == 0

	var esc_back: bool = await UiKit.esc_reaches(host)

	var ok: bool = (
		starts_clean and offers_one_tier and accepted and opened and assigned and returned
		and collectable and collected and expand_gated and expanded and esc_back
	)
	print("[TL_CLICKTEST/tycoon] clean=%s one_tier=%s accept=%s lines_open=%s assign=%s back=%s collectable=%s collect=%s expand_gated=%s expand=%s esc=%s → %s" % [
		starts_clean, offers_one_tier, accepted, opened, assigned, returned, collectable,
		collected, expand_gated, expanded, esc_back, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
		return
	# ★ 配 `TL_SHOT` 時把畫面留在「有訂單在跑、有東西可收」那一格——
	#   零進度的訂單板是空的，而要看的正是它忙起來的樣子。
	TycoonSim.accept(s, 1)
	TycoonSim.accept(s, 2)
	TycoonSim.assign(s, 0, 0)
	TycoonSim.assign(s, 1, 1)
	TycoonSim.accrue(s, TycoonSim.work_of(1))
	host._build()
	# ★ `TL_LEVEL=2` 時再往前一步，把畫面留在**產線編輯**（第二個畫面）。
	#   產線編輯不在 `Main.PANEL_SCREENS` 上是刻意的（兩個畫面、一條路），
	#   所以它沒有自己的 `TL_PANEL`——而「從來沒有人看過那張圖」正是 RG-142
	#   的成因。借一個既有的鉤子（這裡 `TL_LEVEL` 的語意剛好是「第幾個畫面」）
	#   比多開一個入口便宜。
	#   ⚠ 第一版寫 `Hooks.seed`，而**那個欄位不存在**（`TL_SEED` 走的是
	#     `Rng.seed_value`）。截圖跑出來和沒加一樣，而畫面沒有任何錯誤徵兆——
	#     和 RG-142 是同一個形狀：**沒有讀那張圖就不會發現**。
	if Hooks.level == 2:
		await host.get_tree().process_frame
		host._open_lines()


func _lines_child() -> Control:
	for c: Node in host.get_children():
		if c.get_script() == TycoonLinesScreen:
			return c as Control
	return null
