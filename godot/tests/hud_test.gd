extends SceneTree
## HUD 背後的那些量（`10_GDD.md` §3.1 三態、§3.4／§7.6 提前召喚與結算）。
##
## HUD 本身不能自動測（那要真人看圖），但**它顯示的每一個數字都能**。
## 這支測試守的是「畫面上那個數字是對的」，`TL_NAKED` 截圖守的是「看不看得懂」。
##
## 這支測試鎖住的設計承諾：
##   ★ **提前召喚倍率按下當下鎖給那一波**——事後再算一律 1.0，賭注會憑空消失
##   ★ **`正常` 不掛徽章**；核心與儲槽**永遠不會** `缺料`（它們的需求是機會性的）
##   ★ **`滿溢` 指得出「採得出來但送不掉」**——頂欄的 `▲0.0/秒` 沒有位置資訊
##   ★ **產能積分只算送達核心的礦砂**（與 `▲/秒` 同口徑）
##   ★ **波次表跑完＝通關**，模擬停住不再空轉
##
## 跑法：<godot> --headless --path godot --script res://tests/hud_test.gd

const T := preload("res://tests/_assert.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Score := preload("res://scripts/sim/Score.gd")
const Maps := preload("res://data/Maps.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")


func _initialize() -> void:
	var t := T.new("hud_test")
	_motion_tokens(t)
	_bursts_are_render_only(t)
	_every_tower_records_its_shot(t)
	_summon_bonus_math(t)
	_bonus_is_locked_to_its_wave(t)
	_bonus_multiplies_the_drop(t)
	_settlement_math(t)
	_node_states(t)
	_core_and_silo_never_starve(t)
	_clearing_the_table_wins(t)
	_conduit_net_direction(t)
	quit(t.report())


## ★ 流動珠的方向來源（`20_ART_DIRECTION.md` §1.4a）。`conduit_net` 帶號，
## **沿建造時的 a→b 為正**。導管本身無方向（§7.2），方向是每 tick 解出來的
## 結果——所以同一條線用相反的順序蓋，淨流率必須恰好反號。
##
## 這條斷言在守 B0.5 那個缺陷的同一個家族：珠子往錯的方向跑，玩家會照著
## 一張反過來的流向圖去診斷瓶頸。
func _conduit_net_direction(t: T) -> void:
	var fwd := _session()
	BuildController.place(fwd, "extractor", Vector2i(16, 8))
	BuildController.place(fwd, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(fwd, Vector2i(16, 8), Vector2i(16, 11))  # a=採集器
	BattleController.step(fwd)
	var a := _net(fwd, Vector2i(16, 8), Vector2i(16, 11))
	t.ok(a.x > 0.0, "★ 礦砂由採集器流向發電機：沿 a→b 為正")
	t.near(a.y, 0.0, "這條線上沒有能量在跑（發電機的電沒地方去）")

	var rev := _session()
	BuildController.place(rev, "extractor", Vector2i(16, 8))
	BuildController.place(rev, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(rev, Vector2i(16, 11), Vector2i(16, 8))  # a=發電機
	BattleController.step(rev)
	var b := _net(rev, Vector2i(16, 11), Vector2i(16, 8))
	t.near(b.x, -a.x, "★ 反過來蓋同一條線 → 淨流率恰好反號（導管無方向）")


## B1.1 起是 `Vector3(礦砂, 能量, 合金)`——第三種資源也要有自己的流動珠列，
## 不然熔爐那條線在畫面上是靜止的（R-3 可讀性）。
func _net(s: RefCounted, a: Vector2i, b: Vector2i) -> Vector3:
	for c: Dictionary in s.conduits:
		if (c["a"] == a and c["b"] == b) or (c["a"] == b and c["b"] == a):
			return (s.rates["conduit_net"] as Dictionary).get(int(c["id"]), Vector3.ZERO)
	return Vector3.ZERO


# ── 提前召喚的下注數學（§7.6）──────────────────────────────────────────

func _summon_bonus_math(t: T) -> void:
	t.near(Score.summon_bonus(60.0, 60.0), 1.5, "★ 準備期一秒沒用就開波＝上限 1.5")
	t.near(Score.summon_bonus(30.0, 60.0), 1.25, "剩一半＝ +25%")
	t.near(Score.summon_bonus(0.0, 60.0), 1.0, "倒數歸零（自然開波）＝ 1.0，沒有賭注")
	t.near(Score.summon_bonus(120.0, 60.0), 1.5, "剩餘超過總長也封在 1.5（clamp）")
	t.near(Score.summon_bonus(10.0, 0.0), 1.0, "準備期為 0 的關卡不會除以零")
	t.near(Score.summon_data_bonus(1.5), 5.0, "★ 倍率 1.5 折成研究數據＝ 10×0.5 ＝ 5")
	t.near(Score.summon_data_bonus(1.0), 0.0, "沒提前召喚就沒有加成")


## ★ 倍率**在按下的那一刻算一次**。波次開始後 `phase_time` 歸零、倒數也停了，
##   事後再算會拿到「剩餘 = 準備期全長」或 0，兩種都是錯的。
func _bonus_is_locked_to_its_wave(t: T) -> void:
	var early: RefCounted = _session()
	BattleController.start_wave(early)          # phase_time = 0 → 一秒沒用
	t.near(float(early.wave_bonus), 1.5, "★ 準備期一開始就召喚：倍率鎖 1.5")
	t.near(float(early.bonus_data), 5.0, "★ 累計加成同時入帳（+5 研究數據）")
	for _i in 50:
		BattleController.step(early)
	t.near(float(early.wave_bonus), 1.5, "★ 開打 5 秒後倍率沒有縮水——它鎖給這一波了")

	var natural: RefCounted = _session()
	# 自然開波：讓倒數自己跑完（`_phase()` 會替你按下去）。
	for _i in int(natural.prep_time() / BattleController.TICK) + 2:
		BattleController.step(natural)
	t.eq(String(natural.phase), "wave", "倒數跑完會自動開波")
	t.near(float(natural.wave_bonus), 1.0, "★ 自然開波沒有倍率")
	t.near(float(natural.bonus_data), 0.0, "自然開波不累計加成")


## 獎勵形式：**該波掉落的礦砂**按倍率增加（§3.4）。
func _bonus_multiplies_the_drop(t: T) -> void:
	var plain := _one_kill(false)
	var bet := _one_kill(true)
	t.eq(int(plain.kills), 1, "前置：自然開波這局確實殺了 1 隻")
	t.eq(int(bet.kills), 1, "前置：提前召喚這局也殺了 1 隻")
	t.near(float(plain.salvage_total), 3.0, "漂蟲 12 礦砂 × 25% ＝ 3")
	t.near(float(bet.salvage_total), 4.5, "★ 同一隻漂蟲，提前召喚 1.5 倍 → 4.5")


# ── 局末結算（§7.6）───────────────────────────────────────────────────

func _settlement_math(t: T) -> void:
	# 60 秒（600 tick）送達 600 礦砂 ＝ 10/秒 → 產能積分 1.0
	t.near(Score.throughput(600.0, 600, 0.1), 1.0, "★ 產能積分＝平均每秒送達 ÷ 10")
	t.near(Score.throughput(0.0, 0, 0.1), 0.0, "零 tick 不會除以零")
	t.near(
		Score.research_data(5, 1.0, 5.0), 57.0,
		"★ 研究數據 ＝ 10×5 波 ＋ 2×1.0 積分 ＋ 5 加成 ＝ 57"
	)
	# 產能積分的分子是**送達核心的**，不是採出來的（§7.3 同口徑）。
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(16, 8))   # 6 礦砂/秒，沒接線
	for _i in 100:
		BattleController.step(s)
	t.near(float(s.delivered_total), 0.0, "★ 採了 10 秒但沒接線 → 產能積分的分子是 0")
	# 接得到核心的那一份才算。示範佈局的東岸礦線（採集器 → 過橋 → 核心）就是它。
	var wired := _demo(100)
	t.ok(float(wired.delivered_total) > 0.0, "接到核心的礦線才開始累計產能積分")
	t.near(
		Score.throughput(wired.delivered_total, wired.tick_count, BattleController.TICK),
		float(wired.rates["ore_in"]) / 10.0, "產能積分與頂欄 ▲/秒 同口徑（穩態下相等）", 0.05
	)


# ── 節點三態徽章（§3.1）───────────────────────────────────────────────

func _node_states(t: T) -> void:
	# ① 滿溢：採集器產得出來，但沒有任何一條線把它送得出去。
	var stuck := _session()
	var ex: String = BuildController.place(stuck, "extractor", Vector2i(16, 8))
	t.eq(ex, "", "前置：採集器蓋在礦點上")
	BattleController.step(stuck)
	t.eq(
		_state(stuck, Vector2i(16, 8)), SessionState.OVERFLOW,
		"★ 滿溢：採到礦卻沒有出路——這是「導管被打斷」在地圖上的位置資訊"
	)

	# ② 接得到核心的採集器不掛徽章（示範佈局的東岸礦線）。
	var wired := _demo(100)
	t.eq(
		_state(wired, Vector2i(25, 12)), SessionState.NORMAL,
		"★ 正常＝不畫任何東西：一屏 14 個節點全掛「我很好」會把要找的那個埋掉"
	)

	# ③ 缺料：發電機要 4 礦砂/秒，一滴都沒有。
	var hungry := _session()
	BuildController.place(hungry, "generator", Vector2i(16, 11))
	BattleController.step(hungry)
	t.eq(
		_state(hungry, Vector2i(16, 11)), SessionState.STARVED,
		"★ 缺料：發電機要 4 礦砂/秒而沒人給它"
	)


## ★ 核心與儲槽的需求是**解算器合成出來的機會性需求**（核心收剩下的、
##   儲槽有多少收多少）。照滿足率掛徽章的話這兩個會幾乎全程亮著，
##   例外標記就變成背景雜訊——R-3 要找的那一個反而被埋掉。
func _core_and_silo_never_starve(t: T) -> void:
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(16, 8))
	BuildController.place(s, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 11))
	BuildController.place(s, "silo", Vector2i(17, 11))
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(17, 11))
	for _i in 30:
		BattleController.step(s)
	# 發電機吃光採到的礦砂 → 核心一滴都收不到（§7.3 燃料優先於入帳）。
	t.near(float(s.rates["ore_in"]), 0.0, "前置：礦砂全被發電機吃掉，核心入帳 0")
	t.eq(
		_state(s, Maps.SHOAL["core"]), SessionState.NORMAL,
		"★ 核心收不到礦砂也不算「缺料」——它是銀行，不是消費者"
	)
	t.ok(float(s.rates["silo_charge"]) > 0.0, "前置：儲槽正在充能")
	t.eq(
		_state(s, Vector2i(17, 11)), SessionState.NORMAL,
		"★ 充能中的儲槽不算「缺料」——它是有多少收多少，不是被餓著"
	)
	# 對稱的另一半：電網盈餘、儲槽充飽之後，餘量會塞在中繼手上。
	# 那是路由後果，不是玩家能在那一格處理的事——恆亮的徽章＝沒有徽章。
	var full := _demo(5600)
	t.eq(String(full.phase), "won", "前置：示範佈局撐完全部波次（順便驗通關真的到得了）")
	# ★ 「儲槽充飽」要在**充飽的那一格**上驗，不是在最後一格上驗（B2.1e）。
	#   最後一格是通關的那一瞬間，塔正在放電打最後幾隻，儲槽當然不是滿的。
	#   舊版把它寫成末格斷言而剛好是綠的——那是通關 tick 落點的巧合：
	#   B2.1e 換掉解算器後通關晚了 45 個 tick，同一個局面就變紅了。
	#   （和 RG-120 小地圖那條同一種毛病：斷言看的是快照，不是它想證明的性質。）
	var brim := _demo(400)
	t.near(float(brim.rates["silo_charge"]), 300.0, "前置：儲槽已充飽，盈餘無處可去")
	for state: RefCounted in [brim, full]:
		for n: Dictionary in state.nodes:
			if String(n["type"]) != "relay":
				continue
			t.eq(
				int((state.rates["node_state"] as Dictionary).get(int(n["id"]), -1)),
				SessionState.NORMAL, "★ 中繼永遠不掛徽章：它不宣告需求，也不產出"
			)


# ── 通關（局末結算的觸發條件）─────────────────────────────────────────

## 波次表跑完就結束。沒有這個分支的話 `start_wave` 會一直排出空波次，
## 局面永遠停在「倒數→瞬間結束」的空轉，局末結算永遠等不到。
func _clearing_the_table_wins(t: T) -> void:
	var s := _session()
	var waves: int = Maps.waves_of(Maps.SHOAL).size()
	t.ok(waves > 0, "前置：淺灘有波次表")
	# 直接把波次索引推到底，敵人清空——只驗終止條件，不驗打得贏打不贏。
	s.wave_index = waves
	s.phase = "wave"
	s.enemies.clear()
	s.spawn_queue.clear()
	BattleController.step(s)
	t.eq(String(s.phase), "won", "★ 波次表跑完且場上無敵人 → 通關")
	var frozen: int = s.tick_count
	for _i in 10:
		BattleController.step(s)
	t.eq(int(s.tick_count), frozen, "★ 通關後模擬停住，不再空轉")

	# 但殘敵還在啃核心時**不算通關**——不是它們死，就是核心死。
	var chewed := _session()
	chewed.wave_index = waves
	chewed.phase = "wave"
	chewed.add_enemy("drifter")
	chewed.enemies[0]["progress"] = float(chewed.path.size() - 1)
	BattleController.step(chewed)
	t.eq(String(chewed.phase), "wave", "★ 最後一波的殘敵還駐足在核心 → 還沒結束")


# ── helper ───────────────────────────────────────────────────────────

func _session() -> RefCounted:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SHOAL)
	return s


## 示範佈局（`data/Maps.gd` 的 `SHOAL_DEMO`）跑 N 個 tick。
## 用它是因為它是全案唯一一份「真的接得到核心」的完整佈局——
## 在測試裡手刻一條過橋礦線只會刻出第二份會過期的地圖知識。
func _demo(ticks: int) -> RefCounted:
	var s := _session()
	s.alloy = Maps.DEMO_ALLOY   # 示範佈局的加粗要合金（`Maps.DEMO_ALLOY`）
	BuildController.apply_ops(s, Maps.SHOAL_DEMO)
	for _i in ticks:
		BattleController.step(s)
	return s


func _state(s: RefCounted, cell: Vector2i) -> int:
	var n: Dictionary = s.node_at(cell)
	if n.is_empty():
		return -1
	return int((s.rates["node_state"] as Dictionary).get(int(n["id"]), -1))


## 一台錨打死一隻血剩 1 的漂蟲。`early` 決定要不要用掉提前召喚的賭注。
func _one_kill(early: bool) -> RefCounted:
	var s := _session()
	BuildController.place(s, "extractor", Vector2i(16, 8))
	BuildController.place(s, "generator", Vector2i(16, 11))
	BuildController.lay_conduit(s, Vector2i(16, 8), Vector2i(16, 11))
	# ★ B1.6.1：樞紐從 (16,9) 移到 (14,9)。(16,9) 坐在「採集器→發電機」那條
	#   導管的正中間，接出去的線會整段疊在它上面（新規則擋掉的正是這個）。
	BuildController.place(s, "relay", Vector2i(14, 9))
	BuildController.lay_conduit(s, Vector2i(16, 11), Vector2i(14, 9))
	BuildController.place(s, "anchor", Vector2i(14, 7))
	BuildController.lay_conduit(s, Vector2i(14, 9), Vector2i(14, 7))
	if not early:
		s.phase_time = s.prep_time()
	BattleController.start_wave(s)
	s.spawn_queue.clear()
	s.add_enemy("drifter")
	s.enemies[0]["progress"] = 16.0
	s.enemies[0]["hp"] = 1.0
	for _i in 20:
		BattleController.step(s)
	return s


# ── 動效 token（B1.6、`20_ART_DIRECTION.md` §4）─────────────────────────

## ★ 「**所有動效都可跳過**」（§4.4）是硬性要求，而它在 B1.6 之前
## 沒有任何掛勾點：`settings.reduce_motion` 存在存檔裡、沒有任何人讀。
## 這一段守的就是那個開關真的關得掉東西。
func _motion_tokens(t: T) -> void:
	Motion.reduce = false
	# 時長階換算成 tick（`dur.base` 0.24s ÷ 0.1s = 2）。
	t.eq(Motion.ticks(Motion.BASE), 2, "dur.base ＝ 2 個 tick")
	t.ok(Motion.ticks(Motion.INSTANT) >= 1, "最短的時長階也至少活 1 個 tick（否則一出生就死）")
	# 脈動：值域對稱、由 tick 驅動（同一個 tick 必得同一個值 → 截圖可重現）。
	t.near(Motion.pulse(0, Motion.AMBIENT, 0.12), 1.0, "相位 0 的脈動＝1.0")
	t.eq(
		Motion.pulse(37, Motion.AMBIENT, 0.12), Motion.pulse(37, Motion.AMBIENT, 0.12),
		"同一個 tick 必得同一個值（不用系統時間）"
	)
	# 緩動端點。
	t.near(Motion.ease_out_cubic(0.0), 0.0, "ease-out-cubic 起點")
	t.near(Motion.ease_out_cubic(1.0), 1.0, "ease-out-cubic 終點")
	t.ok(Motion.ease_out_cubic(0.5) > 0.5, "ease-out-cubic 是快起慢收")
	# §4.2 的 `ease-in-out-sine` 循環實作在 `pulse()` 裡（B1.9 刪掉獨立入口），
	# 所以改驗那條曲線本身：半週期處回到中點，而且對稱。
	# 週期 2.0 秒 ＝ 20 tick：第 5 tick 是四分之一週期（波峰）、第 10 tick 是
	# 半週期（回到中點）。兩點一起驗才是在驗那條曲線，不是驗一個數字。
	t.near(Motion.pulse(5, 2.0, 0.5), 1.5, "pulse 四分之一週期＝波峰")
	t.near(Motion.pulse(10, 2.0, 0.5), 1.0, "pulse 半週期回到中點（ease-in-out-sine 對稱）")
	# 效果進度：life 個 tick 走完 0→1，中間用 frac 補到 60Hz。
	t.near(Motion.progress(2, 2, 0.0), 0.0, "剛生成＝0")
	t.near(Motion.progress(2, 1, 0.0), 0.5, "過一個 tick＝一半")
	t.near(Motion.progress(2, 1, 0.5), 0.75, "tick 內用 frac 補間")
	# 碎片方向：零 RNG，同一個來源永遠炸成同一個樣子（`30_TECH_DESIGN.md` §2.4）。
	t.eq(
		Motion.fragment_dir(7, 2, 4), Motion.fragment_dir(7, 2, 4),
		"★ 碎片方向是確定的（重播與每日挑戰要看到同一場爆炸）"
	)
	t.ok(
		Motion.fragment_dir(7, 2, 4) != Motion.fragment_dir(8, 2, 4),
		"不同來源炸出不同方向（否則每次爆炸都是同一朵標本花）"
	)

	# ★ reduce_motion：脈動靜止、效果不生成。
	Motion.reduce = true
	t.eq(Motion.ticks(Motion.BASE), 0, "★ reduce_motion → 效果壽命 0（碎片根本不生成）")
	t.near(Motion.pulse(37, Motion.AMBIENT, 0.5), 1.0, "★ reduce_motion → 脈動回靜止值")
	t.near(Motion.pulse01(37, Motion.AMBIENT, 0.2), 1.0, "★ reduce_motion → 透明度脈動也靜止")
	Motion.reduce = false


## ★ 碎片爆是**純渲染**：它不得改變任何一個會被雜湊的量（B1.6）。
## 沒有這一條，哪天有人把碎片改成「會打到人的東西」，確定性會靜靜地壞掉。
func _bursts_are_render_only(t: T) -> void:
	var a := _played(false)
	var b := _played(true)
	t.eq(a["hash"], b["hash"], "★ 開不開碎片爆，局狀態雜湊完全相同")
	t.ok(int(a["bursts_seen"]) > 0, "關掉 reduce 時真的有碎片生成過（否則上一條是空的）")
	t.eq(int(b["bursts_seen"]), 0, "★ reduce_motion 時一顆碎片都沒生成")


## ★ **每一種塔開火都要留下 `shots` 記錄**（B2.1d 回歸）。
##
## B1.6.3 把 `s.shots.append(rec)` 誤縮排進 `if splash_at.x >= 0:` 裡面，
## 於是**只有濺射（碎浪）畫得出開火**，其餘四座塔整整一批都是啞的。
## 而全部測試都是綠的——`shots` 是純渲染、不進 `state_hash()`，
## 沒有任何斷言看過它。這一條就是那個缺口。
func _every_tower_records_its_shot(t: T) -> void:
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SHOAL)
	s.alloy = Maps.DEMO_ALLOY
	BuildController.apply_ops(s, Maps.SHOAL_DEMO)
	var by_type: Dictionary = {}
	# 3000 tick：淺灘準備期 60s（600 tick）＋敵人走完約 52 格，1200 tick 時
	# 南段的錨才剛要進入交戰——太短會讓這條斷言變成在驗「敵人走到哪」。
	for _i in 3000:
		BattleController.step(s)
		for sh: Dictionary in s.shots:
			by_type[String(sh.get("by", ""))] = true
	# 稜鏡（貫穿／能量）與回收者（回收珠）——**兩座都不是濺射**，
	# 所以誤縮排的那一版在這兩條上都會紅。
	#
	# ⚠ 名單裡沒有潮鳴與錨，兩者原因不同，都不是缺陷：
	#   潮鳴的 `rof` 是 0（「不造成傷害的建築也值得佔用電力」是它的設計）；
	#   錨在示範佈局裡**交戰 0 個 tick**——稜鏡在北段就把敵人清光了，
	#   南段的錨一次都沒開火。拿它當斷言等於在驗「敵人有沒有活著走到南段」。
	for ty: String in ["prism", "reclaimer"]:
		t.ok(by_type.has(ty), "★ %s 開火時留下了 shots 記錄（不是只有濺射才留）" % ty)


## 跑一段淺灘的示範佈局，回傳局狀態雜湊與期間出現過的碎片總數。
func _played(reduce: bool) -> Dictionary:
	Motion.reduce = reduce
	var s: RefCounted = SessionState.new()
	s.setup(Maps.SHOAL)
	s.alloy = Maps.DEMO_ALLOY
	BuildController.apply_ops(s, Maps.SHOAL_DEMO)
	var seen := 0
	for _i in 1200:
		BattleController.step(s)
		seen += s.bursts.size()
	Motion.reduce = false
	return {"hash": s.state_hash(), "bursts_seen": seen}
