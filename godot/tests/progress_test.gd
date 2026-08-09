extends SceneTree
## 進度整合：等級軸、成就、公司等級（`10_GDD.md` §1 B2、§7.15；B2.7）。
##
## 這支測試守的是**憲法級的五件事**，不是數值：
##   ① **等級軸的上限就是 +80%**（§1 B2 ②），兩軸各自量，不與科技軸混。
##   ② **B6：以一份「從沒開過 tycoon」的存檔可以把等級軸推到滿級**——
##      §4.1 明文「升級材料必須有三條路」，而不通就是違憲。
##   ③ **B3：統一配置榜吃不到等級軸**——它是可以課金加速的那一軸，
##      而統一榜是「對 P2W 的唯一制衡」。
##   ④ **材料的餘額是推導的**：等級與材料不可能互相矛盾（沒有餘額欄位）。
##   ⑤ **局末結算不退化**：撐得久必定拿得多，重刷第 1 關不會比打完第 5 關划算。
##
## 跑法：<godot> --headless --path godot --script res://tests/progress_test.gd

const T := preload("res://tests/_assert.gd")
const Levels := preload("res://data/Levels.gd")
const Achievements := preload("res://data/Achievements.gd")
const Tech := preload("res://data/Tech.gd")
const Roster := preload("res://data/Roster.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Loadout := preload("res://scripts/sim/Loadout.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const CampaignData := preload("res://data/Campaign.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("progress_test")
	_axis_cap(t)
	_axis_actually_moves_the_sim(t)
	_components_are_derived(t)
	_battle_payout_is_monotone(t)
	_achievements_are_derived(t)
	_achievement_table_is_consistent(t)
	_free_to_play_can_max_levels(t)
	_uniform_board_ignores_levels(t)
	_company_level_moves_from_both_layers(t)
	_save_round_trip(t)
	quit(t.report())


func _fresh() -> Dictionary:
	return SaveService.defaults()


# ── ① 上限 ────────────────────────────────────────────────────────────

func _axis_cap(t: T) -> void:
	t.near(Levels.mult(0), 1.0, "零級＝中性乘數")
	t.near(Levels.gain(Levels.MAX_LEVEL), 0.80, "★ 滿級增幅恰好 +80%（§1 B2 ②）")
	t.near(Levels.gain(5), 0.40, "半級線性（加法不是連乘）")
	# ★ **加法**：連乘的 10 級是 +115.9%，那不是 B2 寫的數字。這一條是它的紅線。
	t.ok(
		absf(Levels.mult(Levels.MAX_LEVEL) - pow(1.0 + Levels.PER_LEVEL, Levels.MAX_LEVEL)) > 0.3,
		"★ 等級軸是加法不是連乘（連乘會超出 +80% 上限）"
	)
	t.eq(Levels.level_of({"levels": {"tower": 99}}, Levels.TOWER), Levels.MAX_LEVEL,
		"級數超出範圍要夾住（壞存檔不該給出 ×8.9）")

	# 兩把尺各自獨立（§7.15）：科技軸的上限不因等級軸而變。
	var all_tech: Array = []
	for n: Dictionary in Tech.NODES:
		all_tech.append(n["id"])
	t.ok(Tech.combat_gain(all_tech) <= 0.35 + 0.0001, "★ 科技軸全解鎖 ≤ +35%（§1 B2 ①）")
	var mods := Levels.apply(Tech.mods(all_tech), {"tower": Levels.MAX_LEVEL})
	t.near(float(mods["damage_mult"]), Tech.mods(all_tech)["damage_mult"] * 1.8,
		"等級軸乘在科技軸之上，兩者不互相吃掉")


# ── ② 真的動到模擬 ────────────────────────────────────────────────────

## 斷言的是**局內量到的差異**，不是 `mods()` 的回傳值（`tech_test` 的同一條紀律：
## 一個沒有任何消費端的乘數，斷言它等於 1.8 只證明了那個常數還在）。
func _axis_actually_moves_the_sim(t: T) -> void:
	var base := _run(MapsData.SHOAL, MapsData.SHOAL_DEMO, {})
	var maxed := _run(MapsData.SHOAL, MapsData.SHOAL_DEMO, {"line": Levels.MAX_LEVEL})
	t.ok(float(base["power"]) > 0.0, "對照組真的有產出（不然下面那幾條沒有意義）")
	# **毛產出**恰好 ×1.80：發電機的 `power_out` 直接乘上去。
	t.near(float(maxed["power"]) / float(base["power"]), 1.8,
		"★ 生產軸滿級：局內能量供給 ×1.80", 0.001)

	# ⚠ **送達核心的量不是 ×1.80，而且不該是**：核心只收「採到的減掉發電機吃掉的」
	#   （`_solve_ore()` 的「只收剩下的」），而燃料需求是固定的。所以毛產出 ×1.8
	#   會讓淨入帳漲得**更多**（此處 240 → 300 是 ×1.25，因為分子分母都被平移過）。
	#   這一條只斷言方向：等級軸不會讓送達量變少。
	t.ok(float(maxed["delivered"]) > float(base["delivered"]),
		"★ 生產軸滿級：送達核心的礦砂變多（不必是 1.8 倍，燃料需求是固定的）")

	# 塔的那一軸走傷害。
	var mods := Levels.apply(Tech.mods([]), {"tower": Levels.MAX_LEVEL})
	t.near(float(mods["damage_mult"]), 1.8, "★ 塔軸滿級：傷害乘數 1.80")
	t.near(float(Levels.apply(Tech.mods([]), {})["damage_mult"]), 1.0,
		"沒有等級軸的局拿到的是中性值（測試圖、統一配置榜走這條）")
	# 生產軸不該碰到傷害，塔軸也不該碰到產出——兩軸買的是兩件事。
	var line_only := Levels.apply(Tech.mods([]), {"line": Levels.MAX_LEVEL})
	t.near(float(line_only["damage_mult"]), 1.0, "★ 生產軸不加傷害")
	t.near(float(Levels.apply(Tech.mods([]), {"tower": Levels.MAX_LEVEL})["produce_mult"]), 1.0,
		"★ 塔軸不加產出")


## 跑 300 tick，回傳毛能量供給與淨送達量。
func _run(map_def: Dictionary, ops: Array, levels: Dictionary) -> Dictionary:
	var s := SessionState.new()
	s.setup(map_def, [], {"levels": levels})
	s.ore = 99999.0
	s.alloy = 99999.0
	BuildController.apply_ops(s, ops)
	for _i in 300:
		BattleController.step(s)
	return {"delivered": float(s.delivered_total), "power": float(s.rates["power_supply"])}


# ── ④ 餘額是推導的 ───────────────────────────────────────────────────

func _components_are_derived(t: T) -> void:
	var d := _fresh()
	t.eq(SaveService.components(d), 0, "新存檔沒有材料")
	t.eq(SaveService.apply_components(d, 12), 12, "局末給的就是波數")
	t.eq(SaveService.components(d), 12, "進帳算進餘額")
	t.eq(SaveService.apply_components(d, 0), 0, "零波不給（測試圖與沙盤走這條）")
	t.eq(SaveService.apply_components(d, -5), 0, "負波不給（不該有，但不能倒扣）")

	# 買一級 → 餘額減掉那一級的價，**而且沒有任何欄位被減**。
	var before_battle := int((d["levels"] as Dictionary)["from_battle"])
	t.ok(SaveService.apply_level_up(d, Levels.TOWER), "材料夠就升得了級")
	t.eq(SaveService.components(d), 12 - Levels.cost(0), "★ 升級之後餘額扣掉那一級的價")
	t.eq(int((d["levels"] as Dictionary)["from_battle"]), before_battle,
		"★ 累計欄位沒被動過（花費是由等級反推的，不是扣出來的）")
	t.ok(not SaveService.apply_level_up(d, Levels.TOWER), "材料不夠就升不了")
	t.eq(Levels.level_of(d, Levels.TOWER), 1, "升不了就不動等級")
	t.ok(not SaveService.apply_level_up(d, "nonsense"), "不存在的軸不動任何東西")

	# 滿級之後不再收費、也不再升。
	var rich := _fresh()
	SaveService.apply_components(rich, 99999)
	for _i in Levels.MAX_LEVEL + 3:
		SaveService.apply_level_up(rich, Levels.LINE)
	t.eq(Levels.level_of(rich, Levels.LINE), Levels.MAX_LEVEL, "★ 滿級就停住")
	var at_max := SaveService.components(rich)
	SaveService.apply_level_up(rich, Levels.LINE)
	t.eq(SaveService.components(rich), at_max, "★ 滿級之後再按也不扣款")
	t.eq(Levels.cost(Levels.MAX_LEVEL), 0, "滿級的下一級無價")


# ── ⑤ 局末結算不退化 ─────────────────────────────────────────────────

## **撐得久必定拿得多。** 這一條擋的是「重刷第 1 關比打完第 5 關划算」——
## 只要公式裡出現星數、關卡獎勵之類的一次性項，最短的局就會付最多錢。
func _battle_payout_is_monotone(t: T) -> void:
	var prev := -1
	for waves in [0, 1, 3, 5, 10, 50]:
		var d := _fresh()
		var got := SaveService.apply_components(d, waves)
		t.ok(got > prev or waves == 0, "波數 %d 的材料不低於前一級" % waves)
		prev = got
	# 戰役五關各自的波數（`data/Enemies.gd`）：第 5 關必須不劣於第 1 關。
	var l1: Array = ((CampaignData.at(0)["map"] as Dictionary)["waves"] as Array)
	var l5: Array = ((CampaignData.at(4)["map"] as Dictionary)["waves"] as Array)
	t.ok(l5.size() >= l1.size(), "★ 第 5 關的波數不少於第 1 關（否則刷第 1 關會更划算）")


# ── ③ 成就是推導的 ───────────────────────────────────────────────────

func _achievements_are_derived(t: T) -> void:
	var d := _fresh()
	t.eq(Achievements.done(d).size(), 0, "★ 全新存檔一條成就都沒有（不該白送）")
	t.eq(Achievements.components(d), 0, "沒成就就沒材料")
	t.eq(Achievements.tokens(d), 0, "沒成就就沒券")

	# 達成 → 獎勵當場在餘額裡，**沒有領取這個動作**。
	((d["campaign"] as Dictionary)["stars"] as Dictionary)[CampaignData.id_at(0)] = 1
	t.ok(Achievements.done(d).has("clear1"), "通關一關 → 初次通關")
	t.eq(SaveService.components(d), 20, "★ 達成的當下獎勵就在餘額裡（沒有領取鈕）")
	# 再算一次不會變多——這就是「不可能重複發放」。
	t.eq(SaveService.components(d), 20, "★ 重算不重複發放（成就沒有 claimed 清單）")

	# 券的第四條路是**加法**：`Roster.earned()` 沒有因此少算別的來源。
	var stars_only := _fresh()
	for id: String in CampaignData.ids():
		((stars_only["campaign"] as Dictionary)["stars"] as Dictionary)[id] = 3
	var from_stars := 15 / Roster.STAR_PER_TOKEN
	t.ok(Roster.earned(stars_only) >= from_stars + Achievements.tokens(stars_only),
		"★ 成就的券是加在既有來源之上，不是取代")
	t.ok(Roster.graduated(stars_only) or Roster.tokens(stars_only) >= Roster.RECRUIT_POOL.size(),
		"★ 純戰役滿星仍然抽得乾招募池（B6，§7.13 的那條保證沒被動到）")


func _achievement_table_is_consistent(t: T) -> void:
	t.eq(Achievements.count(), 20, "M2 的內容矩陣：20 條成就（§5）")
	var m := Achievements.metrics(_fresh())
	var ids: Dictionary = {}
	for a: Dictionary in Achievements.LIST:
		var id := String(a["id"])
		t.ok(not ids.has(id), "成就 id 不重複：%s" % id)
		ids[id] = true
		# ★ **每一條的 metric 都要真的存在**。打錯一個字的成就永遠達不成，
		#   而畫面上它看起來只是「一條很難的成就」——沒有任何東西會報錯。
		t.ok(m.has(String(a["metric"])), "成就 %s 的 metric 存在：%s" % [id, a["metric"]])
		t.ok(int(a["need"]) > 0, "成就 %s 的門檻 > 0（0 門檻＝白送）" % id)
	# ⚠ `Achievements` 刻意不 preload `Roster`（會是個環），所以「名冊全滿」的
	#   門檻是抄過去的一個數字——這一條就是看著它的那雙眼睛。
	for a: Dictionary in Achievements.LIST:
		if a["id"] == "recruit_all":
			t.eq(int(a["need"]), Roster.RECRUIT_POOL.size(),
				"★ 名冊全滿的門檻＝招募池大小（兩邊沒有 preload 相連，只有這條斷言）")
	# 兩條滿級成就的門檻要跟著 `Levels.MAX_LEVEL` 走，不是寫死 10。
	for a: Dictionary in Achievements.LIST:
		if a["id"] in ["tower_max", "line_max"]:
			t.eq(int(a["need"]), Levels.MAX_LEVEL, "滿級成就的門檻＝ MAX_LEVEL")

	# ★★ **同一份進度不得發兩次券**（B2.7 的第一版就犯了，`roster_test` 抓到）。
	#
	# `Roster.earned()` 已經在數戰役星數、無盡波數與 tycoon 的券；成就再對著
	# 同一個量發一張，就是同一份進度領兩次——而它的症狀是「戰役滿星 ＝ 3 券」
	# （§7.13 刻意的對齊，也就是 B6 的證明）悄悄變成 5 券。
	#
	# 寫成**通則**而不是釘住那四個 id：日後加第 21 條成就時，這條會自己攔下來。
	var already_counted := ["cleared", "stars", "best_wave", "tycoon_tokens", "tycoon_level"]
	for a: Dictionary in Achievements.LIST:
		if int(a["token"]) > 0:
			t.ok(not already_counted.has(String(a["metric"])),
				"★★ 成就 %s 發券，但 `Roster.earned()` 已經在數 %s（同一份進度領兩次）"
				% [a["id"], a["metric"]])
	# 「名冊全滿」不發券：招募池已經空了，那是一張用不掉的券。
	for a: Dictionary in Achievements.LIST:
		if a["id"] == "recruit_all":
			t.eq(int(a["token"]), 0, "★ 名冊全滿不發券（畢業之後券沒有用途）")


# ── ② B6：不碰 tycoon 也能滿級 ───────────────────────────────────────

## §4.1 明文：**升級材料必須有三條路**，而且「以從未開啟 tycoon 的存檔可將
## 等級軸推至滿級」。慢是可以的，不通就是違憲。
func _free_to_play_can_max_levels(t: T) -> void:
	var d := _fresh()
	# 一份「只打塔防」的存檔：戰役滿星、無盡打到 50 波、科技全解鎖、藍圖、每日、招募。
	for id: String in CampaignData.ids():
		((d["campaign"] as Dictionary)["stars"] as Dictionary)[id] = 3
	d["endless"] = {"best_wave": 50, "best_output": 60.0}
	var all_tech: Array = []
	for n: Dictionary in Tech.NODES:
		all_tech.append(n["id"])
	(d["tech"] as Dictionary)["unlocked"] = all_tech
	(d["blueprints"] as Array).append({"nodes": []})
	((d["daily"] as Dictionary)["today"] as Dictionary)["uniform"] = {"wave": 8, "output": 3.0}
	(d["roster"] as Dictionary)["recruited"] = Roster.RECRUIT_POOL.duplicate()

	# ★ tycoon 一動也沒動。
	t.eq(d["tycoon"], (SaveService.defaults()["tycoon"] as Dictionary),
		"★ 這份存檔從沒開過潮汐公司")
	var tycoon_free := SaveService.components(d)
	t.ok(tycoon_free > 0, "純塔防的成就真的發得出材料（得到 %d）" % tycoon_free)

	# 剩下的缺口用局末波數補。**算得出來要打幾波**才是一條有意義的斷言。
	var need := Levels.total_cost() * Levels.AXES.size()
	var short := maxi(0, need - tycoon_free)
	SaveService.apply_components(d, short)
	for axis: String in Levels.AXES:
		for _i in Levels.MAX_LEVEL:
			SaveService.apply_level_up(d, axis)
	for axis: String in Levels.AXES:
		t.eq(Levels.level_of(d, axis), Levels.MAX_LEVEL,
			"★ 從沒開過 tycoon 的存檔把「%s」推到滿級（憲法 B6）" % axis)
	print("  [B6] 兩軸滿級共 %d 材料；純塔防成就給 %d，缺口 %d 波（≈ %d 局打到 50 波）" % [
		need, tycoon_free, short, int(ceil(float(short) / 50.0))
	])
	# 缺口要是**有限而且說得出數字**的。無上限的缺口等於這條路是假的。
	t.ok(short < 1000, "缺口在一千波以內（純遊玩滿級是慢，不是不可能）")

	# 反向對照：一份零進度的存檔**升不了任何一級**——上面那條不是因為到處白送。
	var virgin := _fresh()
	t.ok(not SaveService.apply_level_up(virgin, Levels.TOWER),
		"★ 反向對照：零進度的存檔一級都升不了")


# ── ③ B3：統一配置榜吃不到等級軸 ─────────────────────────────────────

## 憲法 B3：統一配置榜「與玩家的任何進度與課金完全無關」。等級軸是**可以課金
## 加速的那一軸**，所以它比科技軸更該被這道閘堵住。
func _uniform_board_ignores_levels(t: T) -> void:
	var rich := _fresh()
	var all_tech: Array = []
	for n: Dictionary in Tech.NODES:
		all_tech.append(n["id"])
	(rich["tech"] as Dictionary)["unlocked"] = all_tech
	rich["levels"] = {"tower": Levels.MAX_LEVEL, "line": Levels.MAX_LEVEL, "from_battle": 9999}
	var mine := Loadout.of(rich)

	# ★★ **逐鍵列舉**，不是釘住那兩軸（B2.7.1）。
	#
	# B2.6 加難度層、M4 加任何一根付費軸時，只要它進了 `Loadout.KEYS`，
	# 這一條就自動涵蓋它。一軸一條手寫斷言等於靠「記得寫」守住憲法。
	var gated := Daily.meta_for(Daily.UNIFORM, mine)
	t.ok(Loadout.is_neutral(gated), "★★ 統一配置榜：loadout 的每一個軸都是中性的（憲法 B3）")
	for key: String in Loadout.KEYS:
		var v: Variant = gated.get(key, null)
		t.ok(v == null or (v is Array and (v as Array).is_empty())
			or (v is Dictionary and (v as Dictionary).is_empty()),
			"★ 統一配置榜上「%s」被歸零" % key)
	t.eq(Daily.meta_for(Daily.FREE, mine), mine, "自由配置榜吃玩家自己的全部成長")

	# 反向對照：那份 loadout 本來真的不中性（不然上面兩條是空跑的）。
	t.ok(not Loadout.is_neutral(mine), "★ 反向對照：玩家那份 loadout 確實不中性")

	# 端到端：兩份天差地遠的存檔在統一榜上開局，`mods` 必須一模一樣。
	var a := SessionState.new()
	var b := SessionState.new()
	a.setup(MapsData.SANDBOX, [], Daily.meta_for(Daily.UNIFORM, mine))
	b.setup(MapsData.SANDBOX, [], Daily.meta_for(Daily.UNIFORM, Loadout.of(_fresh())))
	t.eq(a.mods, b.mods, "★ 統一配置榜上，滿級滿科技與零進度拿到同一組 mods")
	t.eq(a.mods, Levels.apply(Tech.mods([]), {}), "★ 而那一組就是中性值")


# ── 公司等級 ─────────────────────────────────────────────────────────

func _company_level_moves_from_both_layers(t: T) -> void:
	var base := _fresh()
	t.eq(Achievements.company_level(base), 1, "新存檔是公司等級 1")
	t.eq(Achievements.company_points(base), 0,
		"★ 新存檔 0 點（廠等從 1 起跳，不該白送那 12 點）")

	# 只推塔防。
	var tower_only := _fresh()
	for id: String in CampaignData.ids():
		((tower_only["campaign"] as Dictionary)["stars"] as Dictionary)[id] = 3
	t.ok(Achievements.company_points(tower_only) > 0, "★ 只玩塔防也推得動公司等級")

	# 只推 tycoon。
	var tycoon_only := _fresh()
	(tycoon_only["tycoon"] as Dictionary)["level"] = 6
	t.ok(Achievements.company_points(tycoon_only) > 0, "★ 只玩潮汐公司也推得動公司等級")

	var p := Achievements.company_progress(base)
	t.eq(p[1], Achievements.COMPANY_STEP, "進度條的分母是常數本身")
	t.ok(p[0] >= 0 and p[0] < p[1], "進度條的分子落在 [0, 分母)")


# ── 存檔 ─────────────────────────────────────────────────────────────

func _save_round_trip(t: T) -> void:
	# 舊存檔（沒有 `levels` 鍵）讀進來要長出零級，**而且不是壞檔**。
	var legacy := {"sv": 2, "campaign": {"stars": {}}}
	var fixed := SaveService.normalize(legacy)
	t.ok(fixed.has("levels"), "★ B2.5 以前的存檔補得出 levels 這一格")
	t.eq(Levels.level_of(fixed, Levels.TOWER), 0, "補出來的是零級")
	t.eq(SaveService.components(fixed), 0, "補出來的是零材料")

	var d := _fresh()
	SaveService.apply_components(d, 40)
	SaveService.apply_level_up(d, Levels.TOWER)
	var text := JSON.stringify(d)
	var back: Dictionary = SaveService.normalize(JSON.parse_string(text) as Dictionary)
	t.eq(Levels.level_of(back, Levels.TOWER), 1, "等級存得回來")
	t.eq(SaveService.components(back), SaveService.components(d), "餘額存得回來")
