extends SceneTree
## 難度層（`10_GDD.md` §3.11、§7.16；B2.6）。
##
## 這支測試守的是**憲法級的四件事**，不是數值好不好玩：
##   ① **第 3 層的敵人血量倍率就是等級軸滿級的鏡像**（憲法 B2 ② 的硬性配套：
##      「等級軸的增幅必須被難度層同步吃掉」）。兩個數字逐位元比對。
##   ② **每層只加一條新規則**——一層同時動三個數字的話，玩家唯一的心得會是
##      「這層難」，而難度層的全部價值是說得出**難在哪**。
##   ③ **統一配置榜恆為第 0 層**（憲法 B3）。難度層是進得了 `Loadout` 的第三軸，
##      也就是第三個有機會洩進那張榜的東西。
##   ④ **解鎖階梯是推導的**，而且跳不過去。
##
## 另有一段**實測**（`_maxed_levels_still_face_a_wall()`）：同一份佈局在
## 「第 0 層／零進度」與「第 3 層／等級軸滿級」下各跑一次，量出來的差距就是
## B2 ② 那句話的證據。**不是宣稱，是兩排數字。**
##
## 跑法：<godot> --headless --path godot --script res://tests/difficulty_test.gd

const T := preload("res://tests/_assert.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const Levels := preload("res://data/Levels.gd")
const Tech := preload("res://data/Tech.gd")
const Campaign := preload("res://data/Campaign.gd")
const Enemies := preload("res://data/Enemies.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Loadout := preload("res://scripts/sim/Loadout.gd")
const Score := preload("res://scripts/sim/Score.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")

const MAX_TICKS := 9000


func _initialize() -> void:
	var t := T.new("difficulty_test")
	_calibrated_to_the_level_axis(t)
	_one_new_rule_per_tier(t)
	_mods_actually_carry(t)
	_unlock_ladder(t)
	_records_are_per_tier(t)
	_save_migration(t)
	_uniform_board_is_always_tier_zero(t)
	_maxed_levels_still_face_a_wall(t)
	quit(t.report())


func _fresh() -> Dictionary:
	return SaveService.defaults()


# ── ① 校準：第 3 層 ＝ 等級軸滿級的鏡像 ────────────────────────────────

## 憲法 B2 ②：「等級軸的增幅必須被難度層同步吃掉——難度層 N 的敵人強度縮放
## 係數以『等級軸滿級』為基準校準」。
##
## **這一條是全案處理 P2W 數值膨脹的主要機制**（`00_CONCEPT.md` 風險 6），
## 所以它不能是一句寫在文件裡的話：兩個數字在這裡逐位元比對，
## 任一邊被調動（等級軸改成每級 +10%、或第 3 層改成 ×2.0）另一邊就變紅。
func _calibrated_to_the_level_axis(t: T) -> void:
	t.eq(Difficulty.count(), Difficulty.MAX_TIER + 1, "前 %d 層 ＋ 標準層" % Difficulty.MAX_TIER)
	var top: Dictionary = Difficulty.of(Difficulty.MAX_TIER)
	t.near(
		float(top["enemy_hp"]), Levels.mult(Levels.MAX_LEVEL),
		"★★ 第 %d 層的敵人血量倍率 ＝ 等級軸滿級的傷害倍率（憲法 B2 ②）" % Difficulty.MAX_TIER
	)
	# 反向：第 0 層什麼都不動（不然「標準」這兩個字是假的）。
	for key: String in ["enemy_hp", "enemy_damage", "engage"]:
		t.near(float(Difficulty.of(0)[key]), 1.0, "第 0 層的 %s 是 1.0" % key)


# ── ② 每層只加一條新規則 ──────────────────────────────────────────────

func _one_new_rule_per_tier(t: T) -> void:
	var keys := ["enemy_hp", "enemy_damage", "engage"]
	for tier in Difficulty.count():
		var now: Dictionary = Difficulty.of(tier)
		if tier > 0:
			var prev: Dictionary = Difficulty.of(tier - 1)
			for k: String in keys:
				# 逐層**只能更嚴或不變**：某一層放寬一個係數的話，「逐層疊加」就不成立。
				t.ok(
					float(now[k]) >= float(prev[k]),
					"第 %d 層的 %s 不比上一層寬鬆" % [tier, k]
				)
		# ★ 第 N 層有 N 條規則 ＝ 每層只多疊一條。
		t.eq(Difficulty.rules_of(tier).size(), tier, "★ 第 %d 層疊了 %d 條規則" % [tier, tier])
		# 規則卡要**逐條列**：玩家看到的規則數要跟真的生效的係數數對得上，
		# 否則會有一條沒有人告知的規則在暗地裡改局面。
		var active := 0
		for k: String in keys:
			if not is_equal_approx(float(now[k]), 1.0):
				active += 1
		t.eq(Difficulty.rules_of(tier).size(), active,
			"★ 第 %d 層的規則卡列出全部 %d 條生效中的規則（UI 明示）" % [tier, active])


# ── ③ 倍率真的進得了模擬 ─────────────────────────────────────────────

## 「規則寫在表上」與「規則作用在局面上」是兩件事。RG-142（以 type 為鍵的表
## 沒對到就靜靜什麼都不做）與 B2.7 的等級軸都教過同一課：**斷言要問模擬**。
func _mods_actually_carry(t: T) -> void:
	var s := SessionState.new()
	s.setup(Campaign.at(0)["map"], [], {"difficulty": Difficulty.MAX_TIER})
	t.eq(s.difficulty, Difficulty.MAX_TIER, "局面記得自己是第幾層")
	var top: Dictionary = Difficulty.of(Difficulty.MAX_TIER)
	t.near(float(s.mods["enemy_hp_mult"]), float(top["enemy_hp"]), "血量倍率進了 mods")
	t.near(float(s.mods["enemy_damage_mult"]), float(top["enemy_damage"]), "破壞倍率進了 mods")
	t.near(float(s.mods["engage_mult"]), float(top["engage"]), "耗能倍率進了 mods")

	# 敵人真的比較硬（`add_enemy` 讀的是 mods，不是 `Difficulty` 自己）。
	var id := s.add_enemy("drifter")
	var hp := 0.0
	for e: Dictionary in s.enemies:
		if int(e["id"]) == id:
			hp = float(e["hp"])
	t.near(
		hp, float(Enemies.of("drifter")["hp"]) * float(top["enemy_hp"]),
		"★ 出場的敵人帶著難度層的血量"
	)

	# 科技的「能量效率」與難度層的耗能**連乘**，不是後者蓋掉前者。
	var both := SessionState.new()
	both.setup(Campaign.at(0)["map"], [], {
		"tech": ["eff1"], "difficulty": Difficulty.MAX_TIER,
	})
	t.near(
		float(both.mods["engage_mult"]), 0.92 * float(top["engage"]),
		"★ 科技降耗能與難度層抬耗能連乘（沒有互相覆蓋）"
	)

	# 反向對照：沒帶難度層的局（戰役、測試圖、每日）三格全是 1.0。
	var plain := SessionState.new()
	plain.setup(Campaign.at(0)["map"], [], {})
	t.eq(plain.difficulty, 0, "★ 沒指定就是第 0 層（戰役與每日走的是這條）")
	for key: String in ["enemy_hp_mult", "enemy_damage_mult"]:
		t.near(float(plain.mods[key]), 1.0, "沒有難度層時 %s 是 1.0" % key)


# ── ④ 解鎖階梯 ───────────────────────────────────────────────────────

func _unlock_ladder(t: T) -> void:
	var save := _fresh()
	t.eq(Difficulty.unlocked(save), 0, "新存檔只有第 0 層")
	t.ok(Difficulty.why_locked(save, 1).contains("戰役"), "★ 鎖著時說得出要做什麼")
	t.eq(Difficulty.why_locked(save, 0), "", "第 0 層永遠是開的")

	# 戰役只差一關也不算通關（`open_count()` 那條規則回答的是別的問題）。
	var ids := Campaign.ids()
	var stars: Dictionary = (save["campaign"] as Dictionary)["stars"]
	for i in ids.size() - 1:
		stars[ids[i]] = 3
	t.eq(Difficulty.unlocked(save), 0, "★ 最後一關沒過就還不算通關（不是看開到第幾關）")

	stars[ids[ids.size() - 1]] = 1
	t.eq(Difficulty.unlocked(save), 1, "★ 戰役全通 → 第 1 層")
	t.ok(Difficulty.why_locked(save, 2).contains("波"), "第 2 層說得出要撐幾波")

	# 差一波不開。
	SaveService.apply_endless(save, Difficulty.UNLOCK_WAVE - 1, 1.0, 1)
	t.eq(Difficulty.unlocked(save), 1, "★ 差一波就還不開")
	SaveService.apply_endless(save, Difficulty.UNLOCK_WAVE, 1.0, 1)
	t.eq(Difficulty.unlocked(save), 2, "★ 在第 1 層撐過門檻 → 第 2 層")

	# ★ 跳級：第 2 層的紀錄補不了第 1 層的空缺。
	var skipper := _fresh()
	var st: Dictionary = (skipper["campaign"] as Dictionary)["stars"]
	for id: String in ids:
		st[id] = 3
	SaveService.apply_endless(skipper, 99, 9.0, 2)
	t.eq(Difficulty.unlocked(skipper), 1, "★★ 階梯跳不過去（第 2 層的紀錄開不了第 3 層）")

	# 越界一律夾回來——存檔裡出現一個 7 不該變成一局沒有任何倍率的遊戲。
	t.eq(Difficulty.of(99), Difficulty.of(Difficulty.MAX_TIER), "越界的層數夾回最高層")
	t.eq(Difficulty.of(-3), Difficulty.of(0), "負的層數夾回第 0 層")


# ── ⑤ 紀錄逐層各一筆 ─────────────────────────────────────────────────

func _records_are_per_tier(t: T) -> void:
	var save := _fresh()
	t.eq(int(Difficulty.best(save, 0)["wave"]), 0, "新存檔沒有紀錄")
	SaveService.apply_endless(save, 20, 5.0, 0)
	SaveService.apply_endless(save, 8, 2.0, 3)
	t.eq(int(Difficulty.best(save, 0)["wave"]), 20, "第 0 層記著 20 波")
	t.eq(int(Difficulty.best(save, 3)["wave"]), 8, "★ 第 3 層的 8 波沒有被第 0 層的 20 波洗掉")
	# 反向：低分不會蓋掉同一層的高分。
	SaveService.apply_endless(save, 5, 1.0, 0)
	t.eq(int(Difficulty.best(save, 0)["wave"]), 20, "同一層之內仍然只增不減")
	# 兩欄各自取最大值（`apply_endless` 從 B2.1a 起的規則，難度層不該改掉它）。
	var fresh := SaveService.apply_endless(save, 5, 9.9, 0)
	t.ok(not bool(fresh["wave"]) and bool(fresh["output"]),
		"★ 波次與產能各自比較（一局「波次 −15、產能新高」仍然記得住產能）")


func _save_migration(t: T) -> void:
	# sv2 的舊檔：紀錄在 `best_wave`／`best_output`。
	var old := {"sv": 2, "endless": {"best_wave": 17, "best_output": 4.5}}
	var moved := SaveService.normalize(old)
	t.eq(int(Difficulty.best(moved, 0)["wave"]), 17, "★ sv2 的舊紀錄搬進第 0 層")
	t.near(float(Difficulty.best(moved, 0)["output"]), 4.5, "★ 產能積分一起搬")
	t.ok(not (moved["endless"] as Dictionary).has("best_wave"), "舊欄位不留在存檔裡")
	t.eq(int(moved["sv"]), SaveService.SAVE_VERSION, "版本推到最新")

	# 從沒玩過無盡的舊檔**不該長出一筆 0 波的紀錄**（「打過但 0 波」看起來像輸過）。
	var virgin := SaveService.normalize({"sv": 2, "endless": {"best_wave": 0, "best_output": 0.0}})
	t.eq((((virgin["endless"] as Dictionary)["best"]) as Dictionary).size(), 0,
		"★ 沒紀錄的舊檔不會長出假的一筆")

	# sv1 的檔要能一路走到 sv3（`migrate()` 是鏈式的，不是「直達最新」）。
	var ancient := SaveService.normalize({"campaign": {"cleared": ["shoal_run"]}})
	t.eq(int(ancient["sv"]), SaveService.SAVE_VERSION, "★ sv1 的檔一路遷到最新版")
	t.eq(int(((ancient["campaign"] as Dictionary)["stars"] as Dictionary).get("shoal_run", 0)), 1,
		"sv1→sv2 的遷移沒有被 sv3 打斷")


# ── ⑥ 憲法 B3：統一配置榜恆為第 0 層 ─────────────────────────────────

## 難度層是 `Loadout` 的第三軸，也就是**第三個有機會洩進統一榜的東西**。
## `progress_test._uniform_board_ignores_levels()` 已經逐鍵列舉 `Loadout.KEYS`；
## 這裡補的是端到端那一段：帶著第 3 層的 loadout 進統一榜，`mods` 必須是中性的。
func _uniform_board_is_always_tier_zero(t: T) -> void:
	t.ok(Loadout.KEYS.has("difficulty"), "★ 難度層在 `Loadout.KEYS` 上（憲法閘涵蓋它）")
	var mine := Loadout.of(_fresh(), Difficulty.MAX_TIER)
	t.ok(not Loadout.is_neutral(mine), "★ 反向對照：帶著第 3 層的 loadout 不是中性的")

	var gated := Daily.meta_for(Daily.UNIFORM, mine)
	t.eq(Loadout.difficulty_of(gated), 0, "★★ 統一配置榜恆為第 0 層")

	var a := SessionState.new()
	var b := SessionState.new()
	a.setup(Campaign.at(0)["map"], [], gated)
	b.setup(Campaign.at(0)["map"], [], Daily.meta_for(Daily.UNIFORM, Loadout.of(_fresh())))
	t.eq(a.mods, b.mods, "★ 統一榜上，第 3 層與第 0 層的玩家拿到同一組 mods")
	t.eq(Loadout.difficulty_of(Daily.meta_for(Daily.FREE, mine)), Difficulty.MAX_TIER,
		"自由配置榜吃玩家自己選的那一層")


# ── ⑦ 實測：滿級等級軸撞得到牆嗎 ─────────────────────────────────────

## B2.6 DoD：「滿級等級軸在對應難度層下仍有挑戰性」。
##
## **量測台是第 5 關的參考解**（它是全案唯一一份「打得完」有證據的佈局，
## `campaign_test._reference_solutions_win()` 每一批都在跑它）。難度層本身
## 只掛在無盡上，所以這裡拿它當**固定佈局的對照組**，不是在改戰役的規則：
## 同一份佈局、同一批波次，只換兩邊的規則，量出來的差距才歸因得了。
func _maxed_levels_still_face_a_wall(t: T) -> void:
	var lv: Dictionary = Campaign.at(Campaign.count() - 1)
	var maxed := {"tower": Levels.MAX_LEVEL, "line": Levels.MAX_LEVEL}
	# 三腳：滿級應該**落在中間**。少了第三腳的話，上面那條斷言可以在「等級軸
	# 根本沒生效」的情況下一樣是綠的——那是 B2.7 量錯欄位的同一個形狀。
	var base := _play(lv, {})
	var buffed := _play(lv, {"levels": maxed, "difficulty": Difficulty.MAX_TIER})
	var naked := _play(lv, {"difficulty": Difficulty.MAX_TIER})
	for row: Array in [
		["第 0 層／零進度　　", base],
		["第 %d 層／等級軸滿級" % Difficulty.MAX_TIER, buffed],
		["第 %d 層／零進度　　" % Difficulty.MAX_TIER, naked],
	]:
		var r: Dictionary = row[1]
		print("  %s　核心 %.0f/%.0f　建築失血 %.0f　擊殺 %d　產能 %.2f　%d tick（%s）" % [
			row[0], r["core_hp"], r["core_max"], r["structure_lost"],
			r["kills"], r["throughput"], r["ticks"], r["phase"],
		])
	# 建造腳本只在**打得完的那兩局**才該是乾淨的。第三腳是輸的，而輸掉之後
	# 後面的建造當然失敗（核心沒了、線被啃斷）——對它斷言「沒有建造失敗」
	# 等於要求一局輸掉的遊戲照常施工。
	t.eq(base["failures"], [], "第 0 層／零進度的建造腳本沒有失敗")
	t.eq(buffed["failures"], [], "第 3 層／等級軸滿級的建造腳本沒有失敗")

	# ★★ 三腳量出來的就是憲法 B2 ② 那句話：
	#    **等級軸滿級買到的是「打得動第 3 層」，不是「把第 3 層打回第 0 層」。**
	t.eq(base["phase"], "won", "第 0 層／零進度：參考解通關（對照組成立）")
	t.eq(naked["phase"], "lost", "★★ 第 %d 層／零進度：同一份參考解**輸掉**" % Difficulty.MAX_TIER)
	t.eq(buffed["phase"], "won", "★★ 補上等級軸滿級之後才過得了第 %d 層" % Difficulty.MAX_TIER)
	t.ok(
		float(buffed["structure_lost"]) > float(base["structure_lost"]),
		"★★ 而且過得驚險：第 %d 層的建築損失仍然大於第 0 層（增幅被吃掉了）" % Difficulty.MAX_TIER
	)


## 跑一份參考解到底。與 `campaign_test._play()` 同一條路徑，多量一項
## **建築失血**——難度層 2+ 改的是敵人的破壞速度，而核心血量看不到那件事
## （敵人是 walk-by，只有核心會讓它們駐足）。
func _play(lv: Dictionary, meta: Dictionary) -> Dictionary:
	var s := SessionState.new()
	s.setup(lv["map"], lv["unlocked"], meta)
	var step := func(st: RefCounted) -> void: BattleController.step(st)
	var failures: Array = BuildController.apply_timeline(s, lv["demo"], step)
	while s.tick_count < MAX_TICKS and s.phase != "won" and s.phase != "lost":
		BattleController.step(s)
	# 「建築失血」＝ 現存節點與導管離滿血差多少 ＋ 已經被打掉的那些的滿血。
	var lost := 0.0
	var alive: Dictionary = {}
	for n: Dictionary in s.nodes:
		lost += maxf(0.0, NodeDefs.hp(String(n["type"])) - float(n["hp"]))
		alive[int(n["id"])] = true
	for c: Dictionary in s.conduits:
		lost += maxf(0.0, 40.0 - float(c["hp"]))
	return {
		"failures": failures,
		"phase": s.phase,
		"ticks": s.tick_count,
		"core_hp": s.core_hp(),
		"core_max": NodeDefs.hp("core"),
		"structure_lost": lost,
		"throughput": Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK),
		"kills": s.kills,
	}
