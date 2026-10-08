extends RefCounted
## `Tiers.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Tiers.gd` 拆出（B3.14）：只改搬家，不改行為。

const Difficulty := preload("res://data/Difficulty.gd")
const Host := preload("res://scripts/screens/Tiers.gd")
const Progress := preload("res://scripts/meta/Progress.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tiers`）。
##
## 存檔在有鉤子時是零進度 → 戰役一關都沒過 → **只有第 0 層是開的**。
## 所以自檢自己先把戰役塞成滿星、再塞一筆第 1 層的紀錄，逐段驗解鎖階梯
## 真的往前走（**不寫檔**——`SaveService.persist=false`）。
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var cards: bool = host._enter_buttons.size() == Difficulty.count()
	var first_open: bool = cards and not host._enter_buttons[0].disabled
	var rest_locked: bool = cards and host._enter_buttons[1].disabled
	var says_why: bool = cards and host._enter_buttons[1].text.contains("戰役")

	# 戰役全通 → 第 1 層開，第 2 層仍鎖著（它要的是第 1 層的波數）。
	var stars: Dictionary = (GameState.data["campaign"] as Dictionary)["stars"]
	for id: String in preload("res://data/Campaign.gd").ids():
		stars[id] = 3
	host._build()
	await host.get_tree().process_frame
	var tier1_open: bool = not host._enter_buttons[1].disabled
	var tier2_locked: bool = host._enter_buttons[2].disabled
	var says_wave: bool = host._enter_buttons[2].text.contains("波")

	# 第 1 層撐過門檻 → 第 2 層開。**走 `apply_endless`**，不是直接塞欄位：
	# 要驗的是「寫紀錄的那支函式與讀解鎖的那支函式對得上」。
	Progress.apply_endless(GameState.data, Difficulty.UNLOCK_WAVE, 1.0, 1)
	host._build()
	await host.get_tree().process_frame
	var tier2_open: bool = not host._enter_buttons[2].disabled

	# ESC 要在**進局之前**驗：進去之後 ESC 是局內選單的，而這個畫面已經被清掉了。
	var esc_back: bool = await UiKit.esc_reaches(host)

	await UiKit.click(host._enter_buttons[1])
	var battle: Node = null
	for c: Node in host.get_children():
		if c.get_script() == BattleScreen:
			battle = c
	# ★ 問的是**局面真的用了生成圖、而且真的帶著那一層的倍率**
	#   ——「畫面開起來了」在 B2.1a 是一個假綠燈（開的是淺灘測試圖）。
	var entered: bool = battle != null
	var generated: bool = entered and bool((battle.s.map as Dictionary).get("endless", false))
	var carried: bool = entered and int(battle.s.difficulty) == 1
	var scaled: bool = entered and is_equal_approx(
		float(battle.s.mods["enemy_hp_mult"]), float(Difficulty.of(1)["enemy_hp"])
	)

	var ok: bool = (
		cards and first_open and rest_locked and says_why and tier1_open and tier2_locked
		and says_wave and tier2_open and esc_back and entered and generated and carried and scaled
	)
	print("[TL_CLICKTEST/tiers] cards=%s(%d) t0_open=%s locked=%s says_why=%s t1_open=%s t2_locked=%s says_wave=%s t2_open=%s esc_back=%s entered=%s gen=%s tier=%s hp_mult=%s → %s" % [
		cards, host._enter_buttons.size(), first_open, rest_locked, says_why, tier1_open,
		tier2_locked, says_wave, tier2_open, esc_back, entered, generated, carried, scaled,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
