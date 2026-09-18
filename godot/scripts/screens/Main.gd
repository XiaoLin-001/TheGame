extends Control
## 標題畫面（目前的 main_scene）。
##
## B0.1 只需要它證明三件事：專案能開起來、版面走容器（P1）、CJK 字型不是豆腐字。
## 主選單與各面板排在 M1（B1.4）；`TL_PANEL` 的路由表也在那時才長出來。

const BattleScreen := preload("res://scripts/screens/Battle.gd")
const CampaignScreen := preload("res://scripts/screens/Campaign.gd")
const TechScreen := preload("res://scripts/screens/Tech.gd")
const SettingsScreen := preload("res://scripts/screens/Settings.gd")
const DailyScreen := preload("res://scripts/screens/DailyScreen.gd")
const RosterScreen := preload("res://scripts/screens/Roster.gd")
const TycoonScreen := preload("res://scripts/screens/TycoonOrders.gd")
const AchievementsScreen := preload("res://scripts/screens/Achievements.gd")
const TiersScreen := preload("res://scripts/screens/Tiers.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")
const AchievementsData := preload("res://data/Achievements.gd")
const CampaignData := preload("res://data/Campaign.gd")
const RosterData := preload("res://data/Roster.gd")
const MapsData := preload("res://data/Maps.gd")
const Enemies := preload("res://data/Enemies.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Glyphs := preload("res://scripts/render/Glyphs.gd")

# ── ★ 標題背景（B3.11）──────────────────────────────────────────────────
#
# 一幅靜物：潮從左上進來、繞過玩家的線、抵達核心。**全部用局內同一套語彙畫**
# （`Glyphs`、`Shapes.band_jitter`、橋、流動珠），所以標題畫面就是這款遊戲的
# 第一張截圖，不是另一套美術。**零 RNG**：佈局是常數，動態只由 `_bg_t` 驅動，
# `TL_SHOT` 時 `_bg_t` 不走（同局內模擬凍結的理由）。
#
# 背景是一個**沒有 script 的 `Control`**，畫在它的 `draw` 訊號裡：標題畫面的自檢
# 用 `_child_script()` 找「現在掛著哪個畫面」，一個帶 script 的背景會被當成畫面。

## 潮的轉折點（格）。第一點在畫面外，最後一點是核心。
const BG_PATH := [
	Vector2i(-1, 3), Vector2i(7, 3), Vector2i(7, 15), Vector2i(22, 15),
	Vector2i(22, 20), Vector2i(26, 20),
]
const BG_BRIDGES := [Vector2i(7, 8), Vector2i(10, 15), Vector2i(22, 18)]
## [型別, 格]。每一格都退開路徑 2 格以上（walk-by 的傷害半徑是 1）——背景也守規則。
const BG_NODES := [
	["core", Vector2i(26, 20)],
	["extractor", Vector2i(3, 8)], ["relay", Vector2i(10, 8)], ["smelter", Vector2i(13, 8)],
	["generator", Vector2i(10, 11)], ["silo", Vector2i(13, 11)],
	["relay", Vector2i(10, 18)], ["relay", Vector2i(18, 18)], ["relay", Vector2i(24, 18)],
	["prism", Vector2i(4, 12)], ["anchor", Vector2i(9, 13)], ["breaker", Vector2i(19, 13)],
	["reclaimer", Vector2i(13, 17)], ["knell", Vector2i(25, 17)],
	["extractor", Vector2i(33, 5)], ["generator", Vector2i(33, 9)], ["silo", Vector2i(36, 9)],
	["relay", Vector2i(33, 13)], ["longcall", Vector2i(35, 15)], ["ballast", Vector2i(31, 15)],
	["frostreef", Vector2i(33, 17)],
]
## [a, b, 珠子種類]：0 礦砂（近白）、1 能量（琥珀）、2 合金（紫）。只走 90°／45°，
## 過路徑一律走橋（`BG_BRIDGES`）——和局內同一條規則。
const BG_WIRES := [
	[Vector2i(3, 8), Vector2i(10, 8), 0], [Vector2i(10, 8), Vector2i(13, 8), 0],
	[Vector2i(10, 8), Vector2i(10, 11), 0], [Vector2i(10, 11), Vector2i(13, 11), 1],
	[Vector2i(10, 11), Vector2i(10, 18), 1], [Vector2i(10, 18), Vector2i(18, 18), 1],
	[Vector2i(18, 18), Vector2i(24, 18), 2], [Vector2i(24, 18), Vector2i(26, 20), 0],
	[Vector2i(33, 5), Vector2i(33, 9), 0], [Vector2i(33, 9), Vector2i(36, 9), 1],
	[Vector2i(33, 9), Vector2i(33, 13), 1], [Vector2i(33, 13), Vector2i(35, 15), 1],
	[Vector2i(33, 13), Vector2i(31, 15), 1], [Vector2i(33, 13), Vector2i(33, 17), 1],
]
## [型別, 起始進度（格）]。速度讀 `Enemies.DEFS`，走到底就從頭再來。
const BG_ENEMIES := [
	["drifter", 0.0], ["drifter", 1.6], ["carapace", 5.0], ["ember", 11.0],
	["drifter", 16.0], ["carapace", 24.0],
]
const BG_CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)
]
const BG_SIDES: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const BG_AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)
]

## ★ `TL_PANEL` → 要進的畫面。**這張表就是「認得哪些畫面」的唯一一份**（B1.9）。
##
## 舊版在這裡另外存了一份 `KNOWN_PANELS` 字串陣列，唯一的工作是在名字不認得時
## 印警告——而 `_ready()` 的 if 串本身就是那份名單，兩者遲早不同步。
## 現在名單只有一份：**能不能路由，就是認不認得**。
##
## `sandbox` ＝ 局內畫面但換成沙盤「靜水」（`data/Maps.gd`）：沒有敵人，
## 只有三種資源在跑，用來驗合金那一列流動珠（B1.1）。
## `campaign` ＝ 戰役關卡選擇；配 `TL_LEVEL=1..5` 直接進那一關（B1.2）。
## `title` 不在表上——它的語意就是「什麼都不進」。
## `endless` ＝ 局內畫面但換成程序生成圖（B2.1a）；種子走 `Rng.next_seed()`，
## 所以 `TL_SEED` 底下每次拿到的是同一張圖。
const PANEL_SCREENS := {
	"battle": BattleScreen,
	"sandbox": BattleScreen,
	"campaign": CampaignScreen,
	# ★ `endless` 仍然直達局內畫面（第 0 層），**不改**：B2.1a 起的截圖與
	#   大圖導引自檢全走它，而那些驗的是局內的東西，不該因為前面多一個選擇畫面
	#   就要多按一顆鈕。難度層選擇畫面自己是 `tiers`（B2.6）。
	"endless": BattleScreen,
	"tiers": TiersScreen,
	"daily": DailyScreen,
	"roster": RosterScreen,
	# ★ `tycoon` 指的是**訂單板**（第一個畫面）。產線編輯不在這張表上——
	#   它只從訂單板進得去，而那正是「UI 深度兩個畫面」的意思：
	#   **兩個畫面，一條路**，不是兩個各自可以從主選單直達的分頁。
	"tycoon": TycoonScreen,
	"tech": TechScreen,
	"achievements": AchievementsScreen,
	"settings": SettingsScreen,
}


## 主選單的七顆鈕（自檢要按得到）。
var _menu_buttons: Array[Button] = []
## 標題背景（B3.11）與它的時間。`null` ＝ 現在掛的是別的畫面。
var _backdrop: Control = null
var _bg_t: float = 0.0
## 主選單那一欄本身（自檢要量它每一個子節點的位置，不只是鈕）。
var _menu_col: VBoxContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	if PANEL_SCREENS.has(Hooks.panel):
		# 有些畫面進去之後還要再指定一件事。**這不是第二份畫面名單**——
		# 沒對上的 panel 只是沒有後續動作，路由本身仍然只由 `PANEL_SCREENS` 決定。
		var setup := Callable()
		match Hooks.panel:
			"campaign":
				setup = _campaign_level
			"endless":
				setup = _endless
			"daily":
				setup = _daily
		_enter(PANEL_SCREENS[Hooks.panel], setup)
		return
	_build()
	# 不當掉、不假裝成功：說清楚它還沒被實作，留在標題畫面。
	if Hooks.panel != "" and Hooks.panel != "title":
		push_warning("TL_PANEL=%s 尚未實作，停在標題畫面" % Hooks.panel)
		print("[TL_PANEL] unknown=%s known=%s" % [
			Hooks.panel, ", ".join(PANEL_SCREENS.keys())
		])
	if Hooks.click_test:
		_click_selftest.call_deferred()


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
	for b: Button in _menu_buttons:
		if b.text.begins_with(prefix):
			return b
	return _menu_buttons[0]


func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var count: bool = _menu_buttons.size() == 9
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
	for c: Node in _menu_col.get_children():
		var ctl := c as Control
		if ctl == null:
			continue
		if ctl.global_position.y < 0.0 or ctl.global_position.y + ctl.size.y > float(size.y):
			on_screen = false
			if clipped == "（無）":
				clipped = ctl.name + "@" + str(int(ctl.global_position.y))

	await UiKit.click(_menu_button("戰役"))
	var to_campaign: bool = _child_script() == CampaignScreen

	await _escape()
	# 回到標題＝九顆鈕**重新長出來**（`_build()` 有跑），不是舊的那九顆還在。
	var back_home: bool = _child_script() == null and _menu_buttons.size() == 9

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
		for c: Node in get_children():
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
		get_tree().quit(0 if ok else 1)


## ESC ＝ 回標題（`_enter()` 把 `on_exit` 指成 `_back_to_title`）。
func _escape() -> void:
	UiKit.press_escape()
	for _i in 4:
		await get_tree().process_frame




## 現在掛在底下的是哪一個畫面？（標題畫面本身沒有 script 為 screen 的子節點）
func _child_script() -> Script:
	for c: Node in get_children():
		var sc := c.get_script() as Script
		if sc != null:
			return sc
	return null


## ★ 切到某個畫面（B1.9）。四支 `_enter_battle` / `_enter_campaign` /
## `_enter_tech` / `_enter_settings` 做的是同一件事——清子節點、new、指
## `on_exit`、掛上去——差別只有那個 script 與一個可選的後續動作。
##
## 順手修掉一個不一致：舊的四支只 `queue_free()` 不 `remove_child()`，
## 而 `_back_to_title()` 兩個都做。`queue_free()` 要到影格末才生效，中間那一幀
## 舊畫面還在畫也還在吃滑鼠——現在四條路都走 `UiKit.clear()` 的同一個順序。
## ★ **`setup` 要在 `add_child()` 之前跑**（B2.1a 修）。`add_child()` 當下
## `_ready()` 就跑完了，而 `Battle._ready()` 一進去就 `_setup_session()`——
## 設在後面的欄位它根本沒看到。`Battle.gd` 的 `level`／`endless_seed` 註解
## 從 B1.2 就寫著「由呼叫端在 `add_child()` 之前指派」，這裡一直是反的；
## 沒爆是因為戰役走 `Campaign.gd` 自己指派、而 `_campaign_level` 用的是
## `call_deferred`（延到 idle，那時已經在樹上了）。**無盡是第一個真的踩到的。**
func _enter(script: Script, setup: Callable = Callable()) -> void:
	UiKit.clear(self)
	var screen: Control = script.new()
	# 測試圖也要有回頭路：局內選單的「退出」就是這個 `on_exit`（B1.4.1）。
	screen.on_exit = _back_to_title
	if setup.is_valid():
		setup.call(screen)
	add_child(screen)


## `TL_LEVEL=N` 直接進第 N 關——**有些畫面只有進去才到得了**
## （局末星等要打完才有），截圖鉤子需要一條不用手點的路。
func _campaign_level(screen: Control) -> void:
	if Hooks.level >= 1 and Hooks.level <= CampaignData.count():
		screen._enter.call_deferred(Hooks.level - 1)


## 無盡（B2.1a）：每按一次換一張圖，`TL_SEED` 底下則恆定（`Rng.next_seed()`）。
func _endless(screen: Control) -> void:
	screen.endless_seed = Rng.next_seed()


## 每日挑戰（B2.2）。畫面自己不知道怎麼開一局——它只回報「哪一榜、哪一天、
## 哪個種子」，由這裡翻譯成一個局內畫面。**每日就是無盡跑在日種子上**
## （§3.10），所以進的是同一個 `BattleScreen`、走同一條 `endless_seed`。
func _daily(screen: Control) -> void:
	screen.on_start = func(board: String, date: String, sd: int) -> void:
		_enter(BattleScreen, func(battle: Control) -> void:
			battle.endless_seed = sd
			battle.daily_board = board
			battle.daily_date = date
		)


func _back_to_title() -> void:
	UiKit.clear(self)
	_build()


func _build() -> void:
	AudioBus.music("menu")
	# ★ 背景先掛，選單疊在上面（B3.11）。不吃滑鼠、沒有 script（理由見 `BG_PATH` 上方）。
	_backdrop = Control.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate = Palette.mod_alpha(0.85)
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)
	# 全部走容器與錨點，不寫死像素位置 —— 手機移植預留條款 P1。
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# ★ 間隔 16 → 12（B2.5）→ 8（B2.7）。這個版面一直在 720px 的邊緣上：
	#   九顆鈕實際各 56px（主題的內距），加上標題／英文／標語／版本就是 700 出頭，
	#   每加一行字都會把版本號推出畫面。B2.7 又踩了一次（截圖抓到），所以這一批
	#   除了縮間隔，還把「公司等級」併進標語那一行、拿掉純留白的間隔物。
	#
	#   ⚠ **斷言從此量的是這一欄的每一個子節點，不只是鈕**——B2.5 加上位置檢查時
	#   只走 `_menu_buttons`，於是版本號被切掉兩次都沒變紅（RG-139 的第三次）。
	var col := UiKit.vbox(8)
	_menu_col = col
	center.add_child(col)

	col.add_child(UiKit.label(GameState.GAME_NAME, 48, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label(GameState.GAME_NAME_EN, 22, Palette.ORDER_CYAN))

	# ★ 公司等級（B2.7）。**兩層的進度彙總在一個數字上**（§7.15）。
	#   併在標語**同一行**而不是自己一行：它不是一個入口，是一句「你到哪了」，
	#   而這個版面沒有一整行的空間可以給它（見上面那段）。
	col.add_child(UiKit.label(
		"%s　　公司等級 %d" % [
			GameState.TAGLINE, AchievementsData.company_level(GameState.data)
		], 16, Palette.TEXT_SECONDARY
	))

	# ★ 主選單（B1.4）。**戰役排第一顆**：它是這款遊戲；科技樹與設定是它的周邊，
	#   測試圖是給我自己用的。順序就是「玩家最可能想按的東西」由上而下。
	_menu_buttons.clear()
	for entry: Array in [
		["戰役　%s" % _campaign_progress(), _enter.bind(CampaignScreen, _campaign_level)],
		["無盡　%s" % _endless_best(), _enter.bind(TiersScreen)],
		["每日挑戰", _enter.bind(DailyScreen, _daily)],
		["名冊　%s" % _roster_progress(), _enter.bind(RosterScreen)],
		["潮汐公司　%s" % _tycoon_progress(), _enter.bind(TycoonScreen)],
		["局外成長　%s" % _growth_progress(), _enter.bind(TechScreen)],
		["成就　%s" % _achievement_progress(), _enter.bind(AchievementsScreen)],
		["設定", _enter.bind(SettingsScreen)],
		["離開遊戲", _quit],
	]:
		var b := Button.new()
		b.text = String(entry[0])
		b.pressed.connect(entry[1] as Callable)
		_menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))

	# TL_NAKED 的語意是「隱藏所有數值標籤，只留圖形」（30_TECH_DESIGN.md §4.1）。
	# 本批還沒有 HUD 可遮，先把版本／鉤子這行納管，證明這條路徑真的接通了；
	# 它真正的工作對象（頂欄數字、節點數值、優先權刻度）在 B0.6 出現。
	if Hooks.naked:
		print("[TL_NAKED] 版本列已隱藏；version=%s" % GameState.VERSION)
		return

	col.add_child(UiKit.label("v%s" % GameState.VERSION, 13, Palette.TEXT_DISABLED))

	# 只列名稱不列值 —— 值（例如 TL_SHOT 的絕對路徑）會撐爆版面，細節在 stdout。
	var hooks := Env.active()
	if hooks != "":
		col.add_child(UiKit.label(hooks, 11, Palette.WARN_ORANGE))


## 戰役進度：滿星是 15 顆。**主選單上就看得到「還差幾顆」**——
## 回來的理由要在按下去之前就成立，不是進了關卡選擇才發現。
func _campaign_progress() -> String:
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	var got := 0
	for id: String in CampaignData.ids():
		got += int(best.get(id, 0))
	var total := CampaignData.count() * 3
	return "%d／%d ★" % [got, total]


## 無盡個人最佳。**沒有紀錄時就說沒有**，不顯示「0 波」——
## 0 波看起來像一個很爛的成績，而事實是還沒玩過（同 `_campaign_progress` 的精神）。
##
## ★ 逐難度層各一筆紀錄（B2.6）。主選單只有一行，所以顯示的是**最高的那一層
## 打出來的最好成績**——它比「所有層裡波數最大的那一筆」更接近玩家的自我認知
## （在深潮撐 8 波的人不會覺得自己的紀錄是標準層的 20 波）。
func _endless_best() -> String:
	var top := Difficulty.unlocked(GameState.data)
	while top > 0 and int(Difficulty.best(GameState.data, top)["wave"]) <= 0:
		top -= 1
	var best := int(Difficulty.best(GameState.data, top)["wave"])
	if best <= 0:
		return "尚無紀錄"
	return "最高 %d 波%s" % [best, "・%s" % Difficulty.of(top)["name"] if top > 0 else ""]


## 名冊進度。**有券的時候就在主選單上說**（同 `_campaign_progress` 的精神：
## 回來的理由要在按下去之前就成立）——一張沒用掉的券在名單裡是看不到的。
func _roster_progress() -> String:
	var owned := RosterData.owned(GameState.data).size()
	var total := RosterData.all().size()
	var tokens := RosterData.tokens(GameState.data)
	return "%d／%d 隻%s" % [owned, total, "・聲望券 %d" % tokens if tokens > 0 else ""]


## 公司進度。**有東西可收的時候就在主選單上說**（同 `_roster_progress` 的精神：
## 回來的理由要在按下去之前就成立）——一張做完的訂單躺在產線位上是看不到的。
func _tycoon_progress() -> String:
	var s: Dictionary = GameState.data.get("tycoon", {})
	var ready := 0
	for o: Variant in s.get("orders", []):
		if TycoonSim.is_done(o as Dictionary):
			ready += 1
	return "廠等 %d%s" % [
		int(s.get("level", 1)), "・%d 張可收成" % ready if ready > 0 else ""
	]


func _research_data() -> float:
	return float((GameState.data.get("tech", {}) as Dictionary).get("data", 0))


## 局外成長的兩種貨幣（B2.7）。同 `_roster_progress()` 的精神：
## **回來的理由要在按下去之前就成立**——躺著沒花的材料在主選單上是看不到的。
func _growth_progress() -> String:
	return "%s 研究數據・%s 材料" % [
		UiKit.commas(int(_research_data())), UiKit.commas(SaveService.components(GameState.data))
	]


func _achievement_progress() -> String:
	return "%d／%d" % [
		AchievementsData.done(GameState.data).size(), AchievementsData.count()
	]


## 離開。**存一次再走**——設定畫面雖然改一次存一次，但戰役結算那條路徑
## 是在 `Battle` 裡寫的，留一個出口統一收尾比較不會漏。
func _quit() -> void:
	SaveService.save_from(GameState.data)
	get_tree().quit()


# ── ★ 標題背景的繪製（B3.11）──────────────────────────────────────────────

func _process(delta: float) -> void:
	if _backdrop == null or not is_instance_valid(_backdrop) or not _backdrop.is_inside_tree():
		return
	# `TL_SHOT` 下時間不走：同參數在任何機器上拍出同一張圖（局內模擬凍結的同一條）。
	if Hooks.shot_path == "":
		_bg_t += delta
	_backdrop.queue_redraw()


func _bg_center(c: Vector2i) -> Vector2:
	return Shapes.to_world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 一格的四角；`jitter` 為真時外緣格點走 `Shapes.band_jitter`（路徑帶），
## 否則貼格線（侵蝕暈）——和局內同一個分工（`Battle._draw_path()` 的原註）。
func _bg_quad(c: Vector2i, solid: Dictionary, jitter: bool) -> PackedVector2Array:
	var quad := PackedVector2Array()
	for corner: Vector2i in BG_CORNERS:
		var g := c + corner
		var w := Shapes.to_world(g)
		if jitter:
			var interior := true
			for d: Vector2i in BG_AROUND:
				if not solid.has(g + d):
					interior = false
			if not interior:
				w += Shapes.band_jitter(g.x, g.y)
		quad.append(w)
	return quad


func _draw_backdrop() -> void:
	var ci := _backdrop
	var tick := int(_bg_t / Motion.TICK)
	Shapes.draw_grid(ci, Rect2(Vector2.ZERO, ci.size))

	# ── 潮：侵蝕暈 → 路徑帶 → 箭羽 → 橋 ──
	var path: Array = MapsData.path_of({"waypoints": BG_PATH})
	var pset: Dictionary = {}
	for c: Vector2i in path:
		pset[c] = true
	var solid: Dictionary = {}
	for c: Vector2i in path:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				solid[c + Vector2i(dx, dy)] = true
	var halo := Palette.alpha(Palette.TIDE_DEEP, 0.13)
	var edge := Palette.alpha(Palette.TIDE_DEEP, 0.5)
	for c: Vector2i in solid:
		var q := _bg_quad(c, solid, false)
		ci.draw_colored_polygon(q, halo)
		for side in 4:
			if not solid.has(c + BG_SIDES[side]):
				ci.draw_line(q[side], q[(side + 1) % 4], edge, 1.0)
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in path:
		ci.draw_colored_polygon(_bg_quad(c, solid, true), band)
	var arrow := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var k := 2
	while k < path.size() - 1:
		var here: Vector2i = path[k]
		var dir := Vector2(path[k + 1] - here).normalized()
		var tip := _bg_center(here) + dir * 4.0
		ci.draw_line(tip, tip - dir * 5.0 + dir.orthogonal() * 5.0, arrow, 2.0)
		ci.draw_line(tip, tip - dir * 5.0 - dir.orthogonal() * 5.0, arrow, 2.0)
		k += 4
	for b: Vector2i in BG_BRIDGES:
		_bg_bridge(ci, b, pset)

	# ── 線：導管 ＋ 流動珠 ──
	for wire: Array in BG_WIRES:
		_bg_wire(ci, wire[0], wire[1], int(wire[2]))

	# ── 節點：兩趟（落影先、塔身後），和局內一樣 ──
	var rows: Array = []
	for entry: Array in BG_NODES:
		var at := _bg_center(entry[1])
		rows.append([at, Glyphs.build_for({"type": String(entry[0])}, at, tick)])
	for row: Array in rows:
		Glyphs.paint_shadows(ci, row[1])
	for row: Array in rows:
		Glyphs.paint_bodies(ci, row[1], row[0])

	# ── 潮的本體：在帶子上走 ──
	var total := float(maxi(path.size() - 1, 1))
	for idx in BG_ENEMIES.size():
		var entry: Array = BG_ENEMIES[idx]
		var def := Enemies.of(String(entry[0]))
		var speed := float(def.get("speed", 1.0))
		var prog := fposmod(float(entry[1]) + (0.0 if Motion.reduce else _bg_t) * speed, total)
		var i0 := clampi(int(floor(prog)), 0, path.size() - 1)
		var i1 := mini(i0 + 1, path.size() - 1)
		var pos := _bg_center(path[i0]).lerp(_bg_center(path[i1]), prog - float(i0))
		var dir2 := Vector2.RIGHT if i0 == i1 else Vector2(path[i1] - path[i0]).normalized()
		_bg_blob(ci, idx, pos, dir2, def, tick)


## 橋：`Battle._draw_crossing()` 的同一套（落影往側邊偏、雙線橋面、45° 引道）。
func _bg_bridge(ci: Control, cell: Vector2i, pset: Dictionary) -> void:
	var p := Shapes.to_world(cell)
	var g := Shapes.GRID
	var horizontal := pset.has(cell + Vector2i(1, 0)) or pset.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	var drop := Vector2(0, 4) if horizontal else Vector2(4, 0)
	ci.draw_rect(Rect2(p + drop, Vector2(g, g)), Palette.alpha(Palette.BG_DEEP, 0.55))
	if horizontal:
		for dx: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		for dy: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
			var away := signf(dy)
			for dx: float in [7.0, g - 7.0]:
				var out_x := -6.0 if dx < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + out_x, dy + away * 6.0), c, 2.0
				)
	else:
		for dy: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)
			var away := signf(dx)
			for dy: float in [7.0, g - 7.0]:
				var out_y := -6.0 if dy < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + away * 6.0, dy + out_y), c, 2.0
				)


## 導管 ＋ 流動珠（`20_ART_DIRECTION.md` §1.4a 的簡化版：固定線寬、固定速度）。
## `reduce` 時珠子**仍然畫、但不動**——關動效不丟資訊（§1.4a）。
func _bg_wire(ci: Control, a: Vector2i, b: Vector2i, kind: int) -> void:
	var pa := _bg_center(a)
	var pb := _bg_center(b)
	ci.draw_line(pa, pb, Palette.ORDER_CYAN, 4.0)
	var col: Color = Palette.TEXT_PRIMARY
	if kind == 1:
		col = Palette.ENERGY_AMBER
	elif kind == 2:
		col = Palette.ALLOY_VIOLET
	var span := pa.distance_to(pb)
	if span < 1.0:
		return
	var u := (pb - pa) / span
	var x := fposmod((0.0 if Motion.reduce else _bg_t) * 48.0, 20.0)
	while x < span:
		var q := pa + u * x
		ci.draw_circle(q, 2.4, Palette.BG_DEEP)
		ci.draw_circle(q, 1.6, col)
		x += 20.0


## 一隻敵人（`Battle._enemy_shape()` 的同一套規則：由機制欄位推導，會走的波動）。
func _bg_blob(ci: Control, id: int, p: Vector2, dir: Vector2, def: Dictionary, tick: int) -> void:
	var r := float(def.get("radius", 9.0))
	var armored: bool = float(def.get("armor", 0.0)) > 0.0
	var fast: bool = float(def.get("speed", 1.0)) > 1.2
	var sides := 6 if armored else 9
	var amp := 0.07 if armored else 0.15
	var pulse := Motion.pulse(tick, Motion.AMBIENT, 0.12, float(id))
	var flow: float = 0.0 if Motion.reduce else _bg_t * 2.6
	var pts := PackedVector2Array()
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var wobble := (
			1.0 + amp * sin(float(id) * 3.7 + a * 2.0 + flow)
			+ amp * 0.45 * sin(a * 3.0 - flow * 1.7 + float(id))
		)
		var v := Vector2(cos(a), sin(a)) * r * pulse * wobble
		if fast:
			var perp := Vector2(-dir.y, dir.x)
			v -= perp * v.dot(perp) * 0.45
		pts.append(p + v)
	ci.draw_colored_polygon(pts, Palette.TIDE_MAGENTA)
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_polyline(rim, Palette.alpha(Palette.TIDE_DEEP, 0.9), 1.0)
	if armored:
		ci.draw_polyline(rim, Palette.TIDE_DEEP, 3.0)
	elif fast:
		ci.draw_circle(p, maxf(1.0, r * pulse * 0.45), Palette.TIDE_BRIGHT)
