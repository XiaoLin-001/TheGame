extends SceneTree
## 名冊與招募（`10_GDD.md` §3.9、§7.13；B2.4）。
##
## 這支測試守三件事，每一件都是規格裡的硬性文字：
##   ① **不重複、有畢業**——抽到的必定是尚未擁有的；抽完不再消耗券（§3.9）
##   ② **B6：全部都能純靠遊玩取得**——純戰役滿星就畢業得了，一毛錢都不用花
##   ③ **憲法 B3：統一配置榜不受名冊影響**——抽到什麼都不會改變那張榜
##
## 跑法：<godot> --headless --path godot --script res://tests/roster_test.gd

const T := preload("res://tests/_assert.gd")
const Roster := preload("res://data/Roster.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const CampaignData := preload("res://data/Campaign.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const Rng := preload("res://scripts/core/Rng.gd")

## 掃幾個種子驗「不論抽的順序如何，三次都畢業」。
const SWEEP := 200


func _initialize() -> void:
	var t := T.new("roster_test", 83)
	_owned_is_derived_from_campaign(t)
	_tokens_are_derived(t)
	_no_dupes_and_graduation(t)
	_free_to_play_can_graduate(t)
	_uniform_board_is_pinned(t)
	_buildable_and_priority_rows(t)
	_save_round_trip(t)
	quit(t.report())


## 進度到第 `n` 關（0 ＝ 全新）的存檔。
func _save_at(levels_cleared: int) -> Dictionary:
	var d := SaveService.defaults()
	var stars: Dictionary = (d["campaign"] as Dictionary)["stars"]
	for i in levels_cleared:
		stars[CampaignData.id_at(i)] = 3
	return d


# ── ① 擁有清單是推導的，不是存的 ──────────────────────────────────────

func _owned_is_derived_from_campaign(t: T) -> void:
	var fresh := _save_at(0)
	t.eq(Roster.owned(fresh), ["anchor"] as Array[String], "全新存檔只有第 1 關給的錨")

	# 每通一關就多拿到那一關新解鎖的角色——**這張表就是 `data/Campaign.gd`
	# 自己**，不是另一份會漂的清單。
	t.eq(Roster.owned(_save_at(1)).size(), 2, "通過第 1 關 → 第 2 關的稜鏡到手")
	t.eq(Roster.owned(_save_at(2)).size(), 4, "通過第 2 關 → 潮鳴與回收者到手")
	t.eq(Roster.owned(_save_at(4)).size(), 5, "通過第 4 關 → 碎浪到手（確定性五隻全到）")

	# ★ **只有塔進名冊**（§3.4「塔＝角色」）。採集器不是角色。
	for type: String in Roster.owned(_save_at(4)):
		t.ok(Roster.is_character(type), "名冊裡的 %s 是角色（塔）" % type)
	t.ok(not Roster.is_character("extractor"), "採集器不是角色，不進名冊")

	# ★ 紅得起來的那一條：解鎖階梯只有一份。改了 `Campaign` 的規則，
	#   名冊當場跟著動——兩邊各判一次的話這裡會綠而名冊會錯。
	var stars: Dictionary = (_save_at(0)["campaign"] as Dictionary)["stars"]
	t.eq(CampaignData.open_count(stars), 1, "零進度＝只開第 1 關")
	t.eq(
		CampaignData.open_count((_save_at(3)["campaign"] as Dictionary)["stars"]), 4,
		"通三關＝開到第 4 關（名冊與關卡選擇讀的是這同一條）"
	)


# ── ② 券是推導的 ─────────────────────────────────────────────────────

func _tokens_are_derived(t: T) -> void:
	t.eq(Roster.tokens(_save_at(0)), 0, "全新存檔零券")
	# 五關 × 3 星 ＝ 15 顆星 ÷ 5 ＝ 3 券。
	t.eq(Roster.earned(_save_at(5)), 3, "戰役滿星 ＝ 3 券")

	var d := _save_at(5)
	(d["endless"] as Dictionary)["best_wave"] = 25
	t.eq(Roster.earned(d), 5, "★ 無盡 25 波再加 2 券（兩條途徑各算各的）")

	# 花掉的要從手上扣。這裡直接塞 `recruited`，驗的是**推導**而不是招募流程。
	(d["roster"] as Dictionary)["recruited"] = ["longcall", "frostreef"]
	t.eq(Roster.tokens(d), 3, "★ 手上的券 ＝ 賺到的 5 − 花掉的 2（沒有第三份計數器）")
	t.eq(Roster.remaining(d), 1, "還剩 1 隻沒收集")

	# 券不會變負數——里程碑日後若下修，玩家不該看到「−1 張券」。
	var over := SaveService.defaults()
	(over["roster"] as Dictionary)["recruited"] = Roster.RECRUIT_POOL.duplicate()
	t.eq(Roster.tokens(over), 0, "花超過也不會是負數")


# ── ③ 不重複、有畢業 ─────────────────────────────────────────────────

func _no_dupes_and_graduation(t: T) -> void:
	# ★ **掃 200 個種子**：不重複這件事不能只在一個幸運的種子上成立。
	var orders: Dictionary = {}
	var all_ok := true
	var all_graduated := true
	for sd in range(1, SWEEP + 1):
		var d := _save_at(5)
		var rng := Rng.stream(sd)
		var got: Array[String] = []
		for _i in Roster.RECRUIT_POOL.size():
			var one := SaveService.apply_recruit(d, rng)
			if one == "" or got.has(one):
				all_ok = false
				break
			got.append(one)
		if got.size() != Roster.RECRUIT_POOL.size() or not Roster.graduated(d):
			all_graduated = false
		orders[", ".join(got)] = true
	t.ok(all_ok, "★★★ 掃 %d 個種子：每一次抽到的都是尚未擁有的（不重複）" % SWEEP)
	t.ok(all_graduated, "★★★ 掃 %d 個種子：抽滿池子必定畢業" % SWEEP)
	# **隨機的是順序，不是有沒有**（§3.9）——所以順序必須真的會變，
	# 否則「隨機」是假的，而玩家每次拿到的第一隻都一樣。
	t.ok(orders.size() > 1, "★ 抽到的順序會變（隨機的是順序）")

	# 畢業之後：再抽不給、也不扣券。
	var done := _save_at(5)
	var rng2 := Rng.stream(7)
	for _i in Roster.RECRUIT_POOL.size():
		SaveService.apply_recruit(done, rng2)
	var before: int = (done["roster"] as Dictionary)["recruited"].size()
	t.eq(SaveService.apply_recruit(done, rng2), "", "★ 畢業之後抽不到東西")
	t.eq(
		(done["roster"] as Dictionary)["recruited"].size(), before,
		"★ 畢業之後**一張券都不扣**（§3.9 明文）"
	)

	# 券不夠就不給。**規則在這一層**，不是在鈕的 disabled 上。
	var broke := _save_at(0)
	t.eq(SaveService.apply_recruit(broke, Rng.stream(3)), "", "★ 沒有券就抽不到")
	t.eq(Roster.recruited(broke).size(), 0, "沒有券時連記錄都不留")

	# ★ 稀有角色若日後由**別的途徑**到手（成就／商店，§3.9），
	#   「還剩幾隻」與抽卡池都要當場少一格——只看 `recruited` 的話兩邊都會錯。
	var gifted := _save_at(5)
	(gifted["roster"] as Dictionary)["recruited"] = ["ballast"]
	t.eq(Roster.remaining(gifted), Roster.RECRUIT_POOL.size() - 1, "已有的不再計入剩餘")
	for _i in 10:
		var one := Roster.pull(gifted, Rng.stream(_i + 1))
		t.ok(one != "ballast", "★ 已經有的那一隻不會被再抽出來")


# ── ④ B6：純靠遊玩就能畢業 ───────────────────────────────────────────

func _free_to_play_can_graduate(t: T) -> void:
	# ★★★★ §3.9 的硬性承諾：「6 隻稀有角色全部都能純靠遊玩取得」。
	#   這裡的證明是最強的形式——**只推戰役**（一場無盡都不玩、一毛錢都不花），
	#   滿星拿到的券剛好夠把池子抽乾。
	var d := _save_at(CampaignData.count())
	t.eq(
		Roster.tokens(d), Roster.RECRUIT_POOL.size(),
		"★★★★ 戰役滿星的券數 ＝ 招募池大小（純戰役就畢業得了，B6）"
	)
	var rng := Rng.stream(42)
	for _i in Roster.RECRUIT_POOL.size():
		t.ok(SaveService.apply_recruit(d, rng) != "", "純戰役的券抽得動")
	t.ok(Roster.graduated(d), "★★★★ 從未碰過無盡、從未付費 → 名冊全收集")
	t.eq(Roster.owned(d).size(), Roster.all().size(), "全部角色到手")


# ── ⑤ 憲法 B3：統一配置榜不受名冊影響 ────────────────────────────────

func _uniform_board_is_pinned(t: T) -> void:
	# ★ B2.2 記在 §7.11 的債：統一榜曾經是「空陣列＝全部」。
	#   名冊落地之後那等於把抽到才有的三隻發給榜上每一個人。
	t.ok(
		not Daily.UNIFORM_BUILD.is_empty(),
		"★★★ 統一配置榜是一份明列的清單，不是「空陣列＝全部」"
	)
	for type: String in Roster.RECRUIT_POOL:
		t.ok(
			not Daily.UNIFORM_BUILD.has(type),
			"★★★ 招募專屬的 %s **不在**統一配置榜上（憲法 B3）" % type
		)
	# 反過來也要對：確定性的五隻都在，否則統一榜會變成一張殘廢的榜。
	for type: String in Roster.owned(_save_at(5)):
		t.ok(Daily.UNIFORM_BUILD.has(type), "確定性角色 %s 在統一配置榜上" % type)

	# ★ **加角色不會動到這張榜**：清單是常數，不是從 `BUILDABLE` 算出來的。
	t.ok(
		Daily.UNIFORM_BUILD.size() < NodeDefs.BUILDABLE.size(),
		"★ 統一榜比全表短——它不會因為日後加一隻角色就跟著長"
	)
	# 課到頂的存檔（三隻全抽到）進統一榜，拿到的仍然是同一份清單。
	var maxed := _save_at(5)
	(maxed["roster"] as Dictionary)["recruited"] = Roster.RECRUIT_POOL.duplicate()
	t.eq(
		Daily.UNIFORM_BUILD.size(), 10,
		"★★★ 名冊全開的玩家在統一榜上仍然只有這十種"
	)


# ── ⑥ 建造欄與優先權列 ───────────────────────────────────────────────

func _buildable_and_priority_rows(t: T) -> void:
	# 沒有的角色不該出現在建造欄——否則名冊系統在局內是零效果的，
	# 而畫面上會看起來完全正常（B2.1a 假綠燈的同一種形狀）。
	var fresh := _save_at(0)
	for type: String in Roster.RECRUIT_POOL:
		t.ok(not Roster.buildable(fresh).has(type), "沒招募到的 %s 不在建造欄" % type)
	t.ok(Roster.buildable(fresh).has("extractor"), "★ 生產節點不受名冊限制（採集器恆在）")
	t.ok(not Roster.buildable(fresh).has("prism"), "還沒解鎖的稜鏡也不在")

	var full := _save_at(5)
	(full["roster"] as Dictionary)["recruited"] = Roster.RECRUIT_POOL.duplicate()
	t.eq(
		Roster.buildable(full).size(), NodeDefs.BUILDABLE.size(),
		"★ 全收集之後建造欄 ＝ 全表"
	)

	# ★★★ R-1：**滑桿數不隨角色數成長**（§3.1「5–8 條滑桿恆在同一位置」）。
	#   一隻角色一條滑桿的話，M3 的 24 隻就是 28 條——那個面板已經不是一個手勢。
	t.eq(
		NodeDefs.PRIORITY_ROWS.size(), 9,
		"★★★ 優先權面板恆定九列（新角色併進既有的列，不新增滑桿）"
	)
	# 每一隻角色都要有一條滑桿管得到它。**採集器與中繼刻意不在面板上**
	# （它們沒有需求，給滑桿只是假選項，`NodeDefs.PRIORITY_ROWS` 的原註）。
	for type: String in Roster.all():
		t.ok(
			NodeDefs.PRIORITY_ROWS.has(NodeDefs.priority_row(type)),
			"★ 角色 %s 的優先權由「%s」那一列控制得到" % [type, NodeDefs.priority_row(type)]
		)
		t.ok(
			NodeDefs.DEFAULT_PRIORITY.has(type),
			"★ %s 有預設優先權（缺的會被 FlowNetwork 當成 1 ＝ 最先餓死）" % type
		)
	# 併列的成員要能反查得回來，否則滑桿只推得動其中一個。
	t.eq(
		NodeDefs.priority_members("anchor"),
		["anchor", "longcall", "ballast"] as Array[String],
		"★ 「錨」那一條滑桿推的是整列三隻單體物理塔"
	)


# ── ⑦ 存檔 ───────────────────────────────────────────────────────────

func _save_round_trip(t: T) -> void:
	# 只增不破：舊存檔讀進來長出 `roster`，且不動原有資料。
	var old := {"sv": 2, "tech": {"unlocked": ["dmg1"], "data": 5.0}}
	var norm := SaveService.normalize(old)
	t.ok(norm.has("roster"), "舊存檔讀進來自動長出 roster 這一格")
	t.eq(Roster.recruited(norm).size(), 0, "初值是空的")
	t.eq(
		((norm["tech"] as Dictionary)["unlocked"] as Array).size(), 1,
		"★ 補鍵不動玩家原有的資料"
	)
	t.eq(int(norm["sv"]), SaveService.SAVE_VERSION, "加鍵不是結構改動，版本不變")

	# ★ 走一趟真的 JSON：`recruited` 是字串陣列＝JSON 原生型別，
	#   存進去讀出來要是原樣（藍圖庫那一批的同一條驗收）。
	var d := _save_at(5)
	SaveService.apply_recruit(d, Rng.stream(9))
	var round_trip: Variant = JSON.parse_string(JSON.stringify(d))
	t.eq(
		Roster.recruited(SaveService.normalize(round_trip as Dictionary)),
		Roster.recruited(d),
		"★ 招募結果走一趟真的 JSON 之後逐欄相同"
	)
	t.eq(
		Roster.owned(SaveService.normalize(round_trip as Dictionary)).size(),
		Roster.owned(d).size(),
		"★ 推導出來的擁有清單在往返之後也一樣"
	)
