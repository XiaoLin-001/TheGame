extends RefCounted
## `Main.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Main.gd` 拆出（B3.14）：只改搬家，不改行為。

const AchievementsScreen := preload("res://scripts/screens/Achievements.gd")
const BattleScreen := preload("res://scripts/screens/Battle.gd")
const CampaignScreen := preload("res://scripts/screens/Campaign.gd")
const DailyScreen := preload("res://scripts/screens/DailyScreen.gd")
const RosterScreen := preload("res://scripts/screens/Roster.gd")
const TechScreen := preload("res://scripts/screens/Tech.gd")
const TiersScreen := preload("res://scripts/screens/Tiers.gd")
const TycoonScreen := preload("res://scripts/screens/TycoonOrders.gd")
const Host := preload("res://scripts/screens/Main.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=title`，B1.9）。
##
## **這一支是 B1.9 重構自己逼出來的**：主選單那幾顆鈕原本各接一支 `_enter_*`，
## 改成 `_enter.bind(Screen)` 之後——`Callable.bind()` 把參數綁在**尾端**，
## 綁錯位置就是一顆按了沒反應的鈕，而 `_draw()` 一個字都不會說（B0.7.2 同一課）。
## 其餘三條 clicktest 全走 `TL_PANEL`，**完全繞過主選單**，所以這條路是零覆蓋。
##
## 驗一圈完整往返：戰役（bind 帶 setup）→ ESC 回標題 → 科技樹（bind 不帶 setup）
## → ESC → **無盡**（bind 帶 setup，B2.1a）。
##
## ★ 無盡那一顆是這條自檢現在最該守的東西：它和戰役一樣走 `_enter.bind(Screen, setup)`
## 的兩參數形式，而 `endless_seed` 沒被 setup 指到的話**畫面照樣開得起來**——
## 只是開出淺灘測試圖。那種缺陷 `_draw()` 一個字都不會說，所以斷言直接看種子。
## 依**按鈕上的字**找鈕，不依索引。
##
## ⚠ B2.2 插進一顆「每日挑戰」，索引整個往後挪一格——原本寫死 `_menu_buttons[2]`
##   的那一行於是去按了科技樹以外的東西，`tech=false`。**選單順序是會動的**，
##   而測試不該因為多一個入口就變紅（它要驗的是「這顆鈕通到那個畫面」，
##   不是「它排第三」）。
func _menu_button(prefix: String) -> Button:
	for b: Button in host._menu_buttons:
		if b.text.begins_with(prefix):
			return b
	return host._menu_buttons[0]


func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var count: bool = host._menu_buttons.size() == 9
	# ★★ 鐵律 1（`30_TECH_DESIGN.md` §4.1）：**有測試鉤子時絕不寫真存檔。**
	#   B2.8 的 G2 勾稽發現這條全案最重要的安全規則**一條斷言都沒有**——
	#   它一直只是一行 `print`。而這支自檢每一次都跑在鉤子底下，
	#   所以它是這條規則唯一天生就在對的地方（`50_QA_PLAN.md` §2）。
	var persist_off: bool = not SaveService.persist
	# ★ **這一欄的每一個子節點都要整個在畫面內**（RG-139：按得到不等於看得到）。
	#
	#   B2.5 加這條檢查時只走 `_menu_buttons`，於是 B2.7 多一行字把版本號推出
	#   畫面時它照樣是綠的——**沒有被列舉的東西不會被守住**。現在問的是容器：
	#   日後再加任何一行，這條會自己攔下來。
	var on_screen := true
	var clipped := "（無）"
	for c: Node in host._menu_col.get_children():
		var ctl := c as Control
		if ctl == null:
			continue
		if ctl.global_position.y < 0.0 or ctl.global_position.y + ctl.size.y > float(host.size.y):
			on_screen = false
			if clipped == "（無）":
				clipped = ctl.name + "@" + str(int(ctl.global_position.y))

	await UiKit.click(_menu_button("戰役"))
	var to_campaign: bool = _child_script() == CampaignScreen

	await _escape()
	# 回到標題＝九顆鈕**重新長出來**（`_build()` 有跑），不是舊的那九顆還在。
	var back_home: bool = _child_script() == null and host._menu_buttons.size() == 9

	await UiKit.click(_menu_button("局外成長"))
	var to_tech: bool = _child_script() == TechScreen

	await _escape()
	await UiKit.click(_menu_button("成就"))
	var to_ach: bool = _child_script() == AchievementsScreen

	await _escape()
	await UiKit.click(_menu_button("每日挑戰"))
	var to_daily: bool = _child_script() == DailyScreen

	await _escape()
	await UiKit.click(_menu_button("名冊"))
	var to_roster: bool = _child_script() == RosterScreen

	await _escape()
	await UiKit.click(_menu_button("潮汐公司"))
	var to_tycoon: bool = _child_script() == TycoonScreen

	await _escape()
	await UiKit.click(_menu_button("無盡"))
	# ★ B2.6 起「無盡」先開難度層選擇（`screens/Tiers.gd`），不是直接開局。
	#   這裡按到底：選擇畫面 → 第 0 層出擊 → 局內。
	#
	# ★ **不是看 `endless_seed` 有沒有值**——那個欄位在畫面已經用錯地圖之後
	#   才被設上一樣是 true（B2.1a 第一版斷言就是這樣綠的，截圖才抓到打開的
	#   是淺灘）。要問的是「這一局真的用了生成圖嗎」，所以看局面裡的地圖。
	var to_tiers: bool = _child_script() == TiersScreen
	var seeded := 0
	var generated := false
	if to_tiers:
		var tiers: Node = null
		for c: Node in host.get_children():
			if c.get_script() == TiersScreen:
				tiers = c
		await UiKit.click(tiers._enter_buttons[0])
		for c: Node in tiers.get_children():
			if c.get_script() == BattleScreen:
				seeded = int(c.endless_seed)
				generated = bool((c.s.map as Dictionary).get("endless", false))
	var to_endless: bool = to_tiers and seeded != 0 and generated

	var ok: bool = (
		count and persist_off and on_screen and to_campaign and back_home and to_tech and to_ach
		and to_daily and to_roster and to_tycoon and to_endless
	)
	print("[TL_CLICKTEST/title] buttons=%s persist_off=%s on_screen=%s(切到 %s) campaign=%s esc_home=%s tech=%s ach=%s daily=%s roster=%s tycoon=%s tiers=%s endless=%s(seed=%d gen=%s) → %s" % [
		count, persist_off, on_screen, clipped, to_campaign, back_home, to_tech, to_ach, to_daily,
		to_roster, to_tycoon, to_tiers, to_endless, seeded, generated, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)


## ESC ＝ 回標題（`_enter()` 把 `on_exit` 指成 `_back_to_title`）。
func _escape() -> void:
	UiKit.press_escape()
	for _i in 4:
		await host.get_tree().process_frame


## 現在掛在底下的是哪一個畫面？（標題畫面本身沒有 script 為 screen 的子節點）
func _child_script() -> Script:
	for c: Node in host.get_children():
		var sc := c.get_script() as Script
		if sc != null:
			return sc
	return null
