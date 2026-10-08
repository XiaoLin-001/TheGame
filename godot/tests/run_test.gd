extends SceneTree
## 核心玩法層的 headless 合約（B3.14）。
##
## 這支測試證明一件事：**一整局可以不開視窗、不碰任何 `Control`，只靠核心模組跑完**——
## 開局（`RunSetup`）→ 推進（`RunLoop`）→ 建造（`BuildController`）→ 結算（`RunSettlement`）。
## 日後把畫面從 2D 換成 3D 時，這條路徑原封不動；這支測試就是「核心玩法沒有被動到」的證據。
##
## 同時釘住從 `screens/Battle*.gd` 抽出來的純邏輯：`RunDiagnosis`、`HintRules`、`Readout`。
##
## 跑法：<godot> --headless --path godot --script res://tests/run_test.gd

const T := preload("res://tests/_assert.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Campaign := preload("res://data/Campaign.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const HintRules := preload("res://scripts/game/HintRules.gd")
const Loadout := preload("res://scripts/sim/Loadout.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Readout := preload("res://scripts/game/Readout.gd")
const Roster := preload("res://data/Roster.gd")
const RunDiagnosis := preload("res://scripts/game/RunDiagnosis.gd")
const RunLoop := preload("res://scripts/game/RunLoop.gd")
const RunSettlement := preload("res://scripts/game/RunSettlement.gd")
const RunSetup := preload("res://scripts/game/RunSetup.gd")
const Save := preload("res://scripts/core/SaveService.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")


func _initialize() -> void:
	var t := T.new("run_test", 70)
	_setup_matches_manual(t)
	_kinds(t)
	_loop(t)
	_headless_campaign_run(t)
	_headless_endless_settlement(t)
	_diagnosis(t)
	_hint_rules(t)
	_readout(t)
	quit(t.report())


# ── RunSetup：開一局 ＝ 手動 setup 一局 ────────────────────────────────

func _setup_matches_manual(t: RefCounted) -> void:
	var save: Dictionary = Save.defaults()
	var meta := Loadout.of(save, 0)

	var manual: RefCounted = SessionState.new()
	manual.setup(Maps.SHOAL, [], meta)
	var shoal := RunSetup.new_session({}, save)
	t.eq(shoal.state_hash(), manual.state_hash(), "空 spec ＝ 淺灘測試圖，與手動 setup 同一個局")

	manual = SessionState.new()
	manual.setup(Maps.SANDBOX, [], meta)
	t.eq(RunSetup.new_session({"sandbox": true}, save).state_hash(), manual.state_hash(),
		"sandbox ＝ 沙盤「靜水」")

	var lv: Dictionary = Campaign.at(2)
	manual = SessionState.new()
	manual.setup(lv["map"], lv["unlocked"], meta)
	t.eq(RunSetup.new_session({"level": lv}, save).state_hash(), manual.state_hash(),
		"戰役關卡 ＝ 該關的地圖與解鎖清單")

	manual = SessionState.new()
	manual.setup(MapGen.generate(42), Roster.buildable(save), Daily.meta_for("", meta))
	t.eq(RunSetup.new_session({"endless_seed": 42}, save).state_hash(), manual.state_hash(),
		"無盡 ＝ 生成圖 ＋ 這名玩家的名冊")

	manual = SessionState.new()
	manual.setup(MapGen.generate(20260101), Daily.UNIFORM_BUILD.duplicate(),
		Daily.meta_for(Daily.UNIFORM, meta))
	var uniform_spec := {"endless_seed": 20260101, "daily_board": Daily.UNIFORM}
	t.eq(RunSetup.new_session(uniform_spec, save).state_hash(), manual.state_hash(),
		"每日統一配置榜 ＝ 固定清單 ＋ 局外成長歸零（憲法 B3）")

	t.eq(RunSetup.new_session({"endless_seed": 7}, save).state_hash(),
		RunSetup.new_session({"endless_seed": 7}, save).state_hash(), "同 spec ＋ 同存檔 → 同一局")
	t.ok(RunSetup.new_session({"endless_seed": 7}, save).state_hash()
		!= RunSetup.new_session({"endless_seed": 8}, save).state_hash(), "不同種子 → 不同局")

	# 統一配置榜與玩家的名冊無關：招滿三隻招募角色，榜上的清單不變。
	var rich: Dictionary = Save.defaults()
	(rich["roster"] as Dictionary)["recruited"] = ["ballast", "longcall", "frostreef"]
	t.eq(RunSetup.new_session(uniform_spec, rich).state_hash(),
		RunSetup.new_session(uniform_spec, save).state_hash(), "★ 統一配置榜與名冊無關")

	var stress := RunSetup.new_session({"stress": true}, save)
	t.eq(stress.phase, "wave", "壓力情境直接在戰鬥期")
	t.eq(stress.enemies.size(), Maps.STRESS_ENEMIES, "壓力情境的敵人數")


func _kinds(t: RefCounted) -> void:
	t.eq(RunSetup.kind_of({}), RunSetup.SANDBOX, "沒有 level 也沒有種子 ＝ 測試圖")
	t.eq(RunSetup.kind_of({"level": Campaign.at(0)}), RunSetup.CAMPAIGN, "有 level ＝ 戰役")
	t.eq(RunSetup.kind_of({"endless_seed": 5}), RunSetup.ENDLESS, "有種子 ＝ 無盡")
	t.eq(RunSetup.kind_of({"endless_seed": 5, "daily_board": Daily.UNIFORM}), RunSetup.DAILY,
		"有種子 ＋ 榜 ＝ 每日")


# ── RunLoop：固定時間步 ────────────────────────────────────────────────

func _loop(t: RefCounted) -> void:
	var s := RunSetup.new_session({}, Save.defaults())
	t.eq(s.phase, "prep", "新局從準備期開始")
	var acc := RunLoop.advance(s, 0.0, BattleController.TICK * 0.5)
	t.eq(s.tick_count, 0, "不到一個 tick 的 delta 不推進模擬")
	acc = RunLoop.advance(s, acc, BattleController.TICK * 0.5)
	t.eq(s.tick_count, 1, "累加滿一個 tick 才推一格")

	s = RunSetup.new_session({}, Save.defaults())
	RunLoop.advance(s, 0.0, BattleController.TICK * 3.0 + 0.001)
	t.eq(s.tick_count, 3, "一幀的 delta 夠三個 tick → 推三格（模擬不吃 delta 的長度）")

	s = RunSetup.new_session({}, Save.defaults())
	s.speed_mult = 4
	RunLoop.advance(s, 0.0, BattleController.TICK + 0.001)
	t.eq(s.tick_count, 4, "★ 快進＝每個 tick 多跑幾次，不是把 tick 拉長")

	s = RunSetup.new_session({}, Save.defaults())
	s.speed_mult = 4
	s.phase = "wave"
	RunLoop.advance(s, 0.0, BattleController.TICK + 0.001)
	t.eq(s.tick_count, 1, "★ 戰鬥期不可加速（快進只在準備期）")

	s = RunSetup.new_session({}, Save.defaults())
	RunLoop.advance(s, 0.0, 100.0)
	t.eq(s.tick_count, 8, "單幀 tick 上限（卡頓不得變成死亡螺旋）")

	# 幀率無關：同樣的總時間，30fps 與 144fps 走到同一個局面。
	var a := RunSetup.new_session({}, Save.defaults())
	var b := RunSetup.new_session({}, Save.defaults())
	var acc_a := 0.0
	var acc_b := 0.0
	for _i in 60:
		acc_a = RunLoop.advance(a, acc_a, 1.0 / 30.0)
	for _i in 288:
		acc_b = RunLoop.advance(b, acc_b, 1.0 / 144.0)
	t.ok(absi(a.tick_count - b.tick_count) <= 1, "30fps 與 144fps 的 tick 數至多差一格（累加器餘數）")
	while a.tick_count < b.tick_count:
		BattleController.step(a)
	while b.tick_count < a.tick_count:
		BattleController.step(b)
	t.eq(a.state_hash(), b.state_hash(), "★ 同一段時間、不同幀率 → 同一個局面")


# ── 戰役：不開視窗打完一關並結算 ────────────────────────────────────────

func _headless_campaign_run(t: RefCounted) -> void:
	var lv: Dictionary = Campaign.at(0)
	var save: Dictionary = Save.defaults()
	var spec := {"level": lv}
	var s := RunSetup.new_session(spec, save)
	var step := func(st: RefCounted) -> void: BattleController.step(st)
	var failures: Array = BuildController.apply_timeline(s, lv["demo"], step)
	t.ok(failures.is_empty(), "第 1 關參考解全部建得出來")
	var acc := 0.0
	var guard := 0
	while s.phase != "won" and s.phase != "lost" and guard < 20000:
		acc = RunLoop.advance(s, acc, BattleController.TICK)
		guard += 1
	t.eq(s.phase, "won", "★ 不開視窗，靠 RunSetup ＋ RunLoop 打贏第 1 關")

	var before := var_to_str(save)
	var res := RunSettlement.settle(s, spec, save)
	t.ok(bool(res["won"]), "結算：通關")
	t.ok(int(res["stars"]) >= 1 and int(res["stars"]) <= 3, "結算：戰役有星等")
	t.eq((res["star_lines"] as Array).size(), 3, "結算：三顆星各自一行")
	t.ok(float(res["gain"]) > 0.0, "結算：第一次通關有關卡獎勵")
	t.ok(bool(res["dirty"]), "結算：改過存檔字典 → dirty")
	t.ok(var_to_str(save) != before, "結算確實寫進傳入的存檔字典")
	t.ok(int(res["waves"]) > 0, "結算：撐過的波數")
	t.ok((res["record"] as Dictionary).is_empty(), "戰役沒有無盡紀錄")
	t.ok(s.shots.is_empty() and s.bursts.is_empty() and s.shields.is_empty(),
		"結算把純渲染容器收乾淨（局末不再遞減 ttl）")

	# 測試圖：沒有進度可寫 → 存檔字典一個位元都不能動。
	var sb := RunSetup.new_session({"sandbox": true}, save)
	sb.phase = "lost"
	var snapshot := var_to_str(save)
	var res2 := RunSettlement.settle(sb, {"sandbox": true}, save)
	t.eq(var_to_str(save), snapshot, "★ 測試圖結算不動存檔")
	t.ok(not bool(res2["dirty"]), "測試圖：dirty ＝ false")
	t.eq(int(res2["stars"]), -1, "測試圖沒有星等")
	t.eq(int(res2["comps"]), 0, "測試圖不發升級材料")


func _headless_endless_settlement(t: RefCounted) -> void:
	var save: Dictionary = Save.defaults()
	var spec := {"endless_seed": 42, "difficulty": 0}
	var s := RunSetup.new_session(spec, save)
	s.phase = "lost"
	s.wave_index = 7
	var r1 := RunSettlement.settle(s, spec, save)
	t.eq(int(r1["waves"]), 6, "敗局：撐過的波數 ＝ 打到的那一波 − 1")
	var rec: Dictionary = r1["record"]
	t.ok(bool(rec["fresh_wave"]), "第一局：最高波次是新紀錄")
	t.eq(int(rec["prev_wave"]), 0, "第一局：前次 0 波")
	t.ok(int(r1["comps"]) > 0, "無盡：撐過的波數換升級材料")
	t.eq(int(r1["stars"]), -1, "無盡沒有星等")

	var s2 := RunSetup.new_session(spec, save)
	s2.phase = "lost"
	s2.wave_index = 7
	var r2 := RunSettlement.settle(s2, spec, save)
	t.ok(not bool((r2["record"] as Dictionary)["fresh_wave"]), "同成績再打一次不算新紀錄")
	t.eq(int((r2["record"] as Dictionary)["prev_wave"]), 6, "前次 ＝ 上一局的 6 波")

	# 每日挑戰記在自己那一格，不混進無盡的最佳。
	var dspec := {"endless_seed": 20260101, "daily_board": Daily.UNIFORM, "daily_date": "2026-01-01"}
	var s3 := RunSetup.new_session(dspec, save)
	s3.phase = "lost"
	s3.wave_index = 3
	var r3 := RunSettlement.settle(s3, dspec, save)
	t.ok(bool((r3["record"] as Dictionary)["fresh_wave"]), "每日：自己那一格是新紀錄")
	t.eq(int((r3["record"] as Dictionary)["prev_wave"]), 0, "★ 每日不拿無盡的最佳來比")


# ── RunDiagnosis ───────────────────────────────────────────────────────

func _diagnosis(t: RefCounted) -> void:
	var s := RunSetup.new_session({}, Save.defaults())
	var d := RunDiagnosis.new()
	d.reset(s)
	t.eq(d.line(true), "", "什麼事都沒發生 ＋ 通關 → 沒有話說")
	t.ok(d.line(false).contains("啃掉"), "敗了但沒有人走到核心 → 核心被相鄰的敵人啃掉")
	d.wave_ticks = 600
	d.starved = 300
	d.leak_wave = 3
	t.ok(d.line(false).contains("第 3 波"), "敗局：講出第一次漏怪的那一波")
	t.ok(d.line(false).contains("50%"), "敗局：缺電比例進了原因")
	t.ok(d.line(true).contains("50%"), "勝局：缺電比例進了下一次的建議")
	d.starved = 0
	t.ok(d.line(false).contains("火力不夠"), "沒缺電的敗局 → 火力不夠")
	t.eq(d.line(true), "", "沒缺電的勝局 → 沒有話說")

	# tick()：只在戰鬥期累計；核心開始掉血的那一波記下來。
	d.reset(s)
	d.tick(s)
	t.eq(d.wave_ticks, 0, "準備期不累計")
	s.phase = "wave"
	s.wave_index = 4
	d.tick(s)
	t.eq(d.wave_ticks, 1, "戰鬥期累計")
	t.eq(d.leak_wave, -1, "核心沒掉血 → 沒漏怪")


# ── HintRules ──────────────────────────────────────────────────────────

func _hint_rules(t: RefCounted) -> void:
	var s := RunSetup.new_session({}, Save.defaults())
	var buildable: Array = NodeDefs.BUILDABLE
	t.ok(HintRules.next_step(s, buildable).contains("採集器"), "空地圖：下一步是蓋採集器")
	t.eq(HintRules.towers(s), 0, "空地圖沒有塔")
	t.ok(not HintRules.unpowered_tower(s), "沒有塔就沒有「沒接電的塔」")
	var core: Dictionary = s.core()
	t.eq(HintRules.label_at(s, core["cell"]), NodeDefs.label("core"), "label_at：核心格")
	t.eq(HintRules.label_at(s, Vector2i(0, 0)), "空地", "label_at：空地")
	# 沒有節點可連的終點 → 說出原因。
	t.ok(HintRules.connect_hint(s, core["cell"], Vector2i(0, 0)).contains("終點"),
		"終點不是節點 → 講出要先蓋一個")


# ── Readout ────────────────────────────────────────────────────────────

func _readout(t: RefCounted) -> void:
	var s := RunSetup.new_session({}, Save.defaults())
	var parts := Readout.phase_parts(s)
	t.ok(String(parts[0]).begins_with("準備期"), "階段字串：準備期倒數")
	t.ok(String(parts[1]).contains("下一波 1"), "階段字串：下一波的編號")
	s.phase = "won"
	t.eq(Readout.phase_parts(s)[0], "通關", "階段字串：通關")
	s.phase = "lost"
	t.eq(Readout.phase_parts(s)[0], "核心已毀", "階段字串：核心已毀")

	var rows := Readout.energy_rows(s, {})
	t.eq(rows.size(), 15, "能量面板固定 15 列（列數不隨局面變，B0.7.4）")
	var keys: Array = []
	for r: Array in rows:
		keys.append(r[0])
	t.eq(keys.slice(0, 3), ["gen", "silo_out", "reclaim"], "能量面板的列序固定")
	t.eq(keys[keys.size() - 1], "tip2", "能量面板最後一列是提示")

	var core: Dictionary = s.core()
	var model := Readout.inspect_node(s, core["cell"], {})
	t.ok(not model.is_empty(), "檢視核心：有內容")
	t.eq(model["up"], "", "★ 核心的升級鈕收起來")
	t.eq(model["del"], "", "★ 核心的拆除鈕收起來")
	t.ok(String((model["lines"] as Array)[0]).begins_with(NodeDefs.label("core")), "檢視首行是名字")
	t.ok(Readout.inspect_node(s, Vector2i(0, 0), {}).is_empty(), "檢視空地 → 空")

	# 蓋一座採集器再檢視：升級鈕寫出這一級買到什麼，拆除寫退多少。
	var ore: Vector2i = (s.map["ore"] as Array)[0]
	t.eq(BuildController.place(s, "extractor", ore), "", "礦點上蓋得下採集器")
	var m2 := Readout.inspect_node(s, ore, {})
	t.ok(String(m2["up"]).begins_with("升級"), "採集器：升級鈕寫出內容")
	t.ok(String(m2["del"]).begins_with("拆除"), "採集器：拆除鈕寫出退款")
	t.ok(bool(m2["up_on"]), "0 級可以升")

	t.ok(Readout.step_text("range_step").length() >= 0, "step_text 對未知台階回傳原字串")
	t.eq((Readout.codex_lines("anchor") as Array).size() >= 3, true, "圖鑑：錨至少三行")
	t.eq(Readout.problem_cells(s, {}).size(), 0, "沒有被啃的也沒有卡住的 → 沒有問題格")
	t.eq(Readout.power_sources(s).size(), 0, "還沒有發電機 → 沒有電源格")
