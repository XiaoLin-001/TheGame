extends Control
## 名冊（`10_GDD.md` §3.9、§7.13；B2.4）。角色圖鑑 ＋ 招募入口。
##
## 這個畫面要回答的問題只有三個，版面就長成這三個問題的形狀：
##   ① **我有哪些角色、它們有什麼不同？**（每張卡把交戰耗能與射程寫死在臉上——
##      那兩個數字才是選塔的依據，dps 不是）
##   ② **沒有的那幾隻怎麼拿？**（鎖住的卡片寫條件，不寫「未解鎖」）
##   ③ **還剩幾隻沒收集？**（常駐顯示，§3.9）
##
## ── 不使用賭博語彙（§3.9 硬性）───────────────────────────────────────
## 沒有十連、沒有稀有度金光、沒有「差一點就中」的假張力，也沒有轉場動畫。
## **招募是一次結算，不是一場演出**：按下去，卡片當場變成已擁有。
## 「還剩 N 隻」是一個看得到終點的進度條；「稀有度 3%」是一個沒有終點的賭局。

const RosterData := preload("res://data/Roster.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

const CARD := Vector2(230, 168)


## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()

var _recruit_button: Button = null
## 招募鈕旁邊那句話（剩餘數／還差多少／畢業）。自檢斷言它真的說了具體的數字。
var _recruit_note: Label = null
var _scroll: ScrollContainer = null
## 供自檢檢查的卡片標題，與 `RosterData.all()` 同索引。
var _card_titles: Array[Label] = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test and Hooks.panel == "roster":
		_click_selftest.call_deferred()


## ESC ＝ 返回上一層（B1.4.1）。
func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


func _build() -> void:
	UiKit.clear(self)
	_card_titles.clear()

	var col := UiKit.screen(self, 12)
	col.add_child(UiKit.label("名冊", 32, Palette.ORDER_BRIGHT, false))

	var owned := RosterData.owned(GameState.data)
	var all := RosterData.all()
	col.add_child(UiKit.label(
		"已擁有 %d／%d 隻" % [owned.size(), all.size()], 16, Palette.ENERGY_AMBER, false
	))
	# ★ §3.9 明文：**券全部都能純靠遊玩取得**。這一行就是那句話的說明書——
	#   兩條途徑寫出來，玩家才規劃得了「我再推兩關就能拿到下一隻」。
	col.add_child(UiKit.label(
		"聲望券：戰役每 %d 顆星 1 張、無盡每 %d 波 1 張。招募池只有 %d 隻且不重複，"
		% [RosterData.STAR_PER_TOKEN, RosterData.WAVE_PER_TOKEN, RosterData.RECRUIT_POOL.size()]
		+ "收齊就畢業、不再消耗券。",
		13, Palette.TEXT_SECONDARY, false
	))

	# ★ **招募自己一塊，不和「返回」擠同一排**（使用者回饋）。第一版把它接在
	#   返回後面，於是這個畫面的**主要動作看起來像導覽列的一部分**——零進度時
	#   它還是灰的，更像一行狀態文字。使用者的原話是「我沒有看到抽卡畫面」。
	#
	#   招募**沒有第二個畫面**是刻意的（§3.9 不使用賭博語彙：沒有十連演出、
	#   沒有轉場）。但「不做演出」不等於「入口可以看不見」——它只表示這個動作
	#   當場結算，不表示它不重要。所以改成一塊有框、有標題的區域。
	if on_exit.is_valid():
		col.add_child(UiKit.back_row("返回", on_exit))
	col.add_child(_build_recruit())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	# `HFlowContainer`：卡片數會從 M2 的 8 隻長到 M3 的 24 隻（§5），
	# 固定欄數的 `GridContainer` 到時候要回來改一次列數，而換行本來就是排版的事。
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)
	for type: String in all:
		grid.add_child(_card(type, owned.has(type)))


## 招募區。**剩餘數常駐**（§3.9 DoD），不藏在按下去之後的彈窗裡。
##
## 三個狀態各自要說完整的一句話：**能招募**（幾張券）、**還不能**（還差多少，
## 具體到湊得出來）、**畢業**（一個要被說出來的狀態，不是一顆變灰的鈕）。
func _build_recruit() -> Control:
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiKit.hbox(12)
	box.add_child(row)

	var left := RosterData.remaining(GameState.data)
	var tokens := RosterData.tokens(GameState.data)
	var b := Button.new()
	var note := ""
	var tone := Palette.TEXT_SECONDARY
	if left <= 0:
		b.text = "已收集完畢"
		b.disabled = true
		note = "招募池的 %d 隻全在你手上了，聲望券不會再被消耗。" % RosterData.RECRUIT_POOL.size()
		tone = Palette.OK_GREEN
	elif tokens <= 0:
		b.text = "招募"
		b.disabled = true
		# 差多少要講具體的（藍圖庫缺口提示的同一條）：「還差 3 顆星」玩家湊得到，
		# 「聲望券不足」湊不到。
		note = "還剩 %d 隻未收集・聲望券 0——%s" % [left, _next_token_hint()]
		tone = Palette.WARN_ORANGE
	else:
		b.text = "招募（1 張券）"
		b.pressed.connect(_recruit)
		note = "還剩 %d 隻未收集・聲望券 %d。抽到的必定是你還沒有的那幾隻。" % [left, tokens]
		tone = Palette.ENERGY_AMBER
	# 能按的時候字大一級——這是這個畫面唯一會改變存檔的動作。
	b.add_theme_font_size_override("font_size", 16 if b.disabled else 22)
	_recruit_button = b
	row.add_child(UiKit.touchable(b))
	_recruit_note = UiKit.label(note, 13, tone, false)
	_recruit_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_recruit_note)
	return box


## 下一張券還差多少。兩條途徑各報各的，**取近的那一條講在前面**。
func _next_token_hint() -> String:
	var stars := 0
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	for v: Variant in best.values():
		stars += int(v)
	var wave := int((GameState.data.get("endless", {}) as Dictionary).get("best_wave", 0))
	var need_star := RosterData.STAR_PER_TOKEN - stars % RosterData.STAR_PER_TOKEN
	var need_wave := RosterData.WAVE_PER_TOKEN - wave % RosterData.WAVE_PER_TOKEN
	return "還差 %d 顆星或 %d 波" % [need_star, need_wave]


## 一張角色卡。已擁有與未擁有走同一個版面——圖鑑同時是路線圖，
## 看得見後面有什麼才知道要往哪走（科技樹卡片的同一條）。
func _card(type: String, owned: bool) -> Control:
	var def := NodeDefs.of(type)
	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	if not owned:
		box.modulate = Color(1, 1, 1, 0.5)
	var col := UiKit.vbox(4)
	box.add_child(col)

	var title := UiKit.label(
		NodeDefs.label(type), 22,
		Palette.ENERGY_AMBER if owned else Palette.TEXT_DISABLED, false
	)
	col.add_child(title)
	_card_titles.append(title)

	# ★ **交戰耗能排第一行**（§7.4：那一欄是全案的心臟）。選塔的問題是
	#   「這一座要吃我多少電」，不是「它一秒打幾點」。
	col.add_child(UiKit.label(
		"交戰耗能　%.0f ／秒" % float(def.get("engage_power", 0.0)), 16,
		Palette.ENERGY_AMBER, false
	))
	col.add_child(UiKit.label(
		"造價　%d 礦砂%s" % [
			NodeDefs.cost(type),
			"　＋ %d 合金" % NodeDefs.alloy_cost(type) if NodeDefs.alloy_cost(type) > 0 else ""
		], 13, Palette.TEXT_SECONDARY, false
	))
	col.add_child(UiKit.label(
		"射程 %.0f 格　生命 %.0f" % [float(def.get("range", 0.0)), NodeDefs.hp(type)],
		13, Palette.TEXT_SECONDARY, false
	))
	var trait_label := UiKit.label(_trait(type, def), 13, Palette.ORDER_CYAN, false)
	trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_label.custom_minimum_size = Vector2(CARD.x - 24, 0)
	col.add_child(trait_label)

	# 已擁有就說「已擁有」，沒有的說**怎麼拿到**——鎖住要說清楚條件。
	col.add_child(UiKit.label(
		"已擁有" if owned else RosterData.unlock_hint(type), 13,
		Palette.OK_GREEN if owned else Palette.WARN_ORANGE, false
	))
	return box


## 這一隻和別隻差在哪。**一句話講它解什麼問題**，不是把資料表逐欄印一次。
func _trait(type: String, def: Dictionary) -> String:
	if float(def.get("rof", 0.0)) <= 0.0:
		return "光環：減速 %d%%%s　（不疊加，取最強的一座）" % [
			roundi(float(def.get("slow", 0.0)) * 100.0),
			"、破甲 %d%%" % roundi(float(def.get("armor_break", 0.0)) * 100.0)
				if float(def.get("armor_break", 0.0)) > 0.0 else ""
		]
	var line := "%s　%.0f 傷害 × %.2f ／秒" % [
		"能量" if String(def.get("dmg_type", "physical")) == "energy" else "物理",
		float(def.get("dmg", 0.0)), float(def.get("rof", 0.0))
	]
	if def.get("pierce", false):
		line += "　貫穿整條軸線"
	if def.has("splash"):
		line += "　濺射 %.1f 格" % float(def["splash"])
	if def.has("reclaim"):
		line += "　射程內任何死亡回收 %d%% 為能量" % roundi(float(def["reclaim"]) * 100.0)
	return line


## 招募。**規則判定在 `SaveService.apply_recruit()`**，不在這顆鈕的 `disabled`
## 上——後者是畫面狀態；只信它的話，任何一條讓鈕變成可按的路（自檢、日後的
## 鍵盤操作）都會繞過檢查（`Tech._unlock()` 的同一條）。
func _recruit() -> void:
	var got := SaveService.apply_recruit(GameState.data, Rng.stream(Rng.next_seed()))
	if got == "":
		return
	# 解鎖音沿用科技樹那一顆：招募與解鎖科技是同一種事件（得到一個永久的東西）。
	# **不另做一顆「中獎音」**——那是賭博語彙的聽覺版本（§3.9）。
	AudioBus.play("ui_unlock")
	SaveService.save_from(GameState.data)
	_build()


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=roster`）。
##
## 這個畫面的全部價值是「招募鈕點得到、真的扣券、而且抽不到重複的」。
## 存檔在有鉤子時是預設值（零進度＝零券），所以先塞進度再點——**不寫檔**
## （`SaveService.persist=false`），玩家的真實進度碰不到（`Tech` 的同一條）。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 零進度：只有第 1 關給的那一隻（錨），招募鈕買不起且說得出還差多少。
	var start_owned: Array = RosterData.owned(GameState.data)
	var starts_with_anchor: bool = start_owned.size() == 1 and start_owned.has("anchor")
	# ★ 「差多少」要在**畫面上**說得具體。斷言看的是那句話，不是鈕的 disabled
	#   ——灰掉的鈕只說「不行」，湊不出下一步。
	var broke: bool = _recruit_button.disabled and _recruit_note.text.contains("還差")

	# 塞滿星戰役（15 顆星 ＝ 3 券 ＝ 剛好畢業，§7.13）。
	var stars: Dictionary = (GameState.data["campaign"] as Dictionary)["stars"]
	for id: String in preload("res://data/Campaign.gd").ids():
		stars[id] = 3
	_build()
	await get_tree().process_frame
	# 五關全通＝五隻確定性角色全到手；招募池那三隻仍然一隻都沒有。
	var deterministic: bool = RosterData.owned(GameState.data).size() == 5
	var three_tokens: bool = RosterData.tokens(GameState.data) == 3
	var open: bool = not _recruit_button.disabled and _recruit_note.text.contains("還剩 3 隻")

	# ★ 連按三次＝抽完全池。**每一次都必須是新的一隻**（§3.9 不重複）。
	var pulls: Array[String] = []
	for _i in 3:
		var before: Array = RosterData.recruited(GameState.data).duplicate()
		await UiKit.click(_recruit_button)
		var after: Array = RosterData.recruited(GameState.data)
		if after.size() == before.size() + 1:
			pulls.append(String(after[after.size() - 1]))
	var no_dupes: bool = pulls.size() == 3 and _unique(pulls)
	var all_pool: bool = no_dupes and _covers_pool(pulls)

	# 畢業：鈕變成「已收集完畢」，而且**再按也不會扣券**（§3.9 明文）。
	var graduated: bool = RosterData.graduated(GameState.data) and _recruit_button.disabled
	# ★ 兩層都要驗：鈕按不下去（畫面層），**而且直接呼叫規則層也不會給**。
	#   只驗鈕的話，「畢業後不再消耗券」這條規則其實是靠一顆 `disabled` 撐著的
	#   ——那不是規則，那是版面。
	var spent_before: int = RosterData.recruited(GameState.data).size()
	await UiKit.click(_recruit_button)
	var rule_refuses: bool = SaveService.apply_recruit(
		GameState.data, Rng.stream(1)
	) == ""
	var no_overdraw: bool = (
		RosterData.recruited(GameState.data).size() == spent_before and rule_refuses
	)

	# 抽到的三隻真的進得了建造欄——名冊不進 `buildable()` 的話，這整個系統
	# 在局內是零效果的，而畫面上會看起來完全正常。
	var into_battle: bool = RosterData.buildable(GameState.data).size() == NodeDefs.BUILDABLE.size()

	# 捲到底之後最後一張卡整張在畫面內（RG-47／RG-60 的同一條）。
	_scroll.scroll_vertical = 999999
	await get_tree().process_frame
	var last: Label = _card_titles[_card_titles.size() - 1]
	var reachable: bool = (
		last.global_position.y >= 0.0
		and last.global_position.y + last.size.y <= float(size.y)
	)

	var esc_back: bool = await UiKit.esc_reaches(self)

	var ok: bool = (
		starts_with_anchor and broke and deterministic and three_tokens and open
		and no_dupes and all_pool and graduated and no_overdraw and into_battle
		and reachable and esc_back
	)
	print("[TL_CLICKTEST/roster] start=%s broke=%s deterministic=%s tokens=%s open=%s no_dupes=%s(%s) pool=%s graduated=%s no_overdraw=%s buildable=%s last_reachable=%s esc_back=%s → %s" % [
		starts_with_anchor, broke, deterministic, three_tokens, open, no_dupes,
		", ".join(pulls), all_pool, graduated, no_overdraw, into_battle, reachable,
		esc_back, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)
		return
	# ★ **配 `TL_SHOT` 時把畫面留在「有券可招募」那一格**（CLAUDE.md「拍只有
	#   互動才到得了的狀態」）。零進度拍出來招募鈕是灰的、抽完拍出來是「已收集
	#   完畢」——而要看的正是中間那個狀態，它在沒有進度的存檔上到不了。
	#   放在全部斷言跑完之後，所以一項都沒有被跳過。
	((GameState.data["roster"] as Dictionary)["recruited"] as Array).clear()
	_build()


func _unique(list: Array[String]) -> bool:
	var seen: Dictionary = {}
	for s: String in list:
		if seen.has(s):
			return false
		seen[s] = true
	return true


func _covers_pool(list: Array[String]) -> bool:
	for type: String in RosterData.RECRUIT_POOL:
		if not list.has(type):
			return false
	return true


