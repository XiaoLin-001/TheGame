extends SceneTree
## 潮汐公司（`10_GDD.md` §3.8、§7.14；B2.5）。
##
## 這支測試守的是**憲法級的四件事**，不是數值：
##   ① **離線結算受結構性上限約束**——離線三十天的收益上限＝每個產線位各完成
##      一張訂單（RG-10）。上限不是一個要調的數字，所以它必須是可證明的。
##   ② **時鐘倒退不獎不罰**——把系統時間調回去既不倒扣也不加速（§4.3）。
##   ③ **塔防完全不依賴 tycoon**（憲法 B6、`00_CONCEPT.md` §三）——
##      以一份「從沒開過公司」的存檔跑完戰役五關的參考解。
##   ④ **沒有失敗狀態**——任何操作都不會讓玩家失去已經付出的進度（§3.8 約束 1）。
##
## 跑法：<godot> --headless --path godot --script res://tests/tycoon_test.gd

const T := preload("res://tests/_assert.gd")
const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const Roster := preload("res://data/Roster.gd")
const CampaignData := preload("res://data/Campaign.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")

## 三十天的秒數。RG-10 指名的那個數字。
const THIRTY_DAYS := 30 * 24 * 60 * 60


func _initialize() -> void:
	var t := T.new("tycoon_test", 64)
	_shape_and_curves(t)
	_accept_assign_collect(t)
	_offline_is_capped_by_lines(t)
	_clock_rollback_is_neutral(t)
	_no_failure_state(t)
	_ui_depth_is_two_screens(t)
	_campaign_needs_no_tycoon(t)
	_save_round_trip(t)
	quit(t.report())


func _fresh() -> Dictionary:
	return (SaveService.defaults()["tycoon"] as Dictionary).duplicate(true)


## 在廠等 L **全速生產**時，存到下一次擴廠要幾秒。
##
## 這是收斂的正確量法：把「一級有幾個產線位」與「一張訂單要多久」都算進去。
## 假設玩家永遠接得到當前廠等的最高階（最划算的那一張）。
func _expand_seconds(level: int) -> float:
	var per_sec := (
		float(TycoonSim.slots(level)) * float(TycoonSim.reward_of(level))
		/ TycoonSim.work_of(level)
	)
	return float(TycoonSim.expand_cost(level)) / per_sec


## 廠等 L 的公司，資金給滿，方便驗別的東西。
func _at_level(level: int) -> Dictionary:
	var s := _fresh()
	s["level"] = level
	s["credits"] = 999999
	return s


# ── 曲線與形狀 ────────────────────────────────────────────────────────

func _shape_and_curves(t: T) -> void:
	# 產線位：1,2,2,3,3,4,4,5（§7.14）
	var got: Array[int] = []
	for l in range(1, TycoonSim.MAX_LEVEL + 1):
		got.append(TycoonSim.slots(l))
	t.eq(
		got, [1, 1, 1, 2, 2, 2, 3, 3] as Array[int],
		"產線位 slots(L) = 1 + floor((L−1)/3)　★ 每三級才加一個，理由見 `TycoonSim.slots()`"
	)

	# ★ **收斂**（§4.2 防通膨：指數成本 × 線性偏下收入）。這不是一條數值斷言，
	#   是一條**曲線關係**的斷言——單獨驗某一級的數字，改表的人不會知道自己
	#   破壞了收斂。
	#
	# ⚠ 第一版比的是「擴廠成本的倍率 vs 訂單報酬的倍率」，**那兩個不可比**：
	#   前者是每一級的成本、後者是每一張訂單的報酬，中間差了「一級有幾個產線位」
	#   與「一張訂單要多久」。照那個寫法量出來是 8.2× vs 13.5×（看起來會通膨），
	#   而真正要問的是「**推到後期，每一次擴廠要存多久**」。
	var early := _expand_seconds(1)
	var late := _expand_seconds(TycoonSim.MAX_LEVEL - 1)
	t.ok(
		late > early,
		"★ 存下一次擴廠的時間隨廠等上升（%.0f 秒 → %.0f 秒）＝ 自然收斂，不會通膨"
			% [early, late]
	)

	# 訂單由廠等解鎖，一個機制答兩題（不另做「研發」）。
	t.eq(TycoonSim.available_tiers(1), [1] as Array[int], "廠等 1 只接得到第 1 階")
	t.eq(TycoonSim.available_tiers(8).size(), 8, "廠等 8 接得到全部八階")
	t.eq(TycoonSim.ORDER_NAMES.size(), 9, "八個品項 ＋ 一個佔位的空字串（§5 內容矩陣：M2 ＝ 8）")

	# 招募券是第 4 階起才有——前期靠塔防，後期公司才幫得上忙。
	t.eq(TycoonSim.token_of(3), 0, "第 3 階不給券")
	t.eq(TycoonSim.token_of(4), 1, "第 4 階起每張訂單一張券")


# ── 接單 → 指派 → 收成 ────────────────────────────────────────────────

func _accept_assign_collect(t: T) -> void:
	var s := _at_level(1)
	t.eq(TycoonSim.order_cap(1), 3, "廠等 1：1 個產線位、接得下 3 張 → 指派是真的取捨")
	t.ok(TycoonSim.accept(s, 1), "接第一張")
	t.ok(TycoonSim.accept(s, 1) and TycoonSim.accept(s, 1), "接到滿")
	t.ok(not TycoonSim.accept(s, 1), "★ 滿了就接不下——上限是結構性的")
	t.ok(not TycoonSim.accept(_at_level(1), 2), "★ 廠等 1 接不到第 2 階（訂單由廠等解鎖）")

	t.eq(TycoonSim.order_on_line(s, 0), -1, "剛接的訂單都沒上線")
	t.ok(TycoonSim.assign(s, 0, 0), "把第 0 張放上第 0 格產線位")
	t.eq(TycoonSim.order_on_line(s, 0), 0, "★ 佔用狀態是推導的，不是另存的一份")
	t.ok(not TycoonSim.assign(s, 0, 1), "廠等 1 沒有第 1 格產線位")

	# 只有上線的那一張會動。
	TycoonSim.accrue(s, 30.0)
	t.near(float((s["orders"][0] as Dictionary)["done"]), 30.0, "上線的那張推進了 30")
	t.near(float((s["orders"][1] as Dictionary)["done"]), 0.0, "沒上線的那張一動也沒動")

	t.ok(not TycoonSim.collect(s, 0), "沒做完不給收")
	TycoonSim.accrue(s, 999.0)
	t.near(
		float((s["orders"][0] as Dictionary)["done"]), TycoonSim.work_of(1),
		"★ 做完就停在上限——多跑的那 900 秒沒有溢出去"
	)
	var before_credits := int(s["credits"])
	t.ok(TycoonSim.collect(s, 0), "做完就收得了")
	t.eq(
		int(s["credits"]) - before_credits, TycoonSim.reward_of(1),
		"收成入帳 reward(1)"
	)
	t.eq(s["orders"].size(), 2, "收成後那張離開清單，產線位空出來")


# ── ① 離線受結構性上限約束（RG-10）───────────────────────────────────

func _offline_is_capped_by_lines(t: T) -> void:
	# 廠等 8：5 個產線位、接得下 7 張。全部接滿、能上線的都上線。
	var s := _at_level(8)
	for _i in TycoonSim.order_cap(8):
		TycoonSim.accept(s, 1)
	for line in TycoonSim.slots(8):
		TycoonSim.assign(s, line, line)

	s["last_seen"] = 1
	var elapsed := TycoonSim.settle(s, 1 + THIRTY_DAYS)
	t.near(elapsed, float(THIRTY_DAYS), "結算推進了三十天")

	var done_count := 0
	for o: Variant in s["orders"]:
		if TycoonSim.is_done(o as Dictionary):
			done_count += 1
	# ★ 這一條就是 RG-10。三十天 ＝ 2,592,000 秒，而第 1 階只要 60 秒——
	#   沒有上限的話這裡會是「四萬三千張訂單」。
	t.eq(
		done_count, TycoonSim.slots(8),
		"★ 離線三十天的收益上限＝每個產線位各完成一張（RG-10）"
	)
	t.eq(
		s["orders"].size(), TycoonSim.order_cap(8),
		"沒上線的那兩張完全沒動——它們不會自己排隊補上"
	)

	# 反向對照：**上限真的在夾**。把產線位當成無限的話會完成七張。
	var loose := _at_level(8)
	for _i in TycoonSim.order_cap(8):
		TycoonSim.accept(loose, 1)
	for i in TycoonSim.order_cap(8):
		(loose["orders"][i] as Dictionary)["line"] = 0   # 全部硬塞到同一格
	TycoonSim.accrue(loose, float(THIRTY_DAYS))
	var loose_done := 0
	for o: Variant in loose["orders"]:
		if TycoonSim.is_done(o as Dictionary):
			loose_done += 1
	t.ok(
		loose_done > TycoonSim.slots(8),
		"★ 紅燈對照：繞過產線位限制就會完成 %d 張（> %d）——證明上面那條不是空的"
			% [loose_done, TycoonSim.slots(8)]
	)


# ── ② 時鐘倒退不獎不罰 ────────────────────────────────────────────────

func _clock_rollback_is_neutral(t: T) -> void:
	# ⚠ **用真實的 Unix 時間戳**。第一版用 10_000 這種玩具數字，倒退一天之後
	#   `last_seen` 變成負的，撞上「0 ＝ 從沒開過公司」那個哨兵值 → 下一次結算
	#   被當成第一次而回傳 0。真實時鐘不可能落到 1970 之前，但**測試用不真實的
	#   數字就會驗到不真實的行為**。
	const NOW := 1_700_000_000
	var s := _at_level(2)
	TycoonSim.accept(s, 1)
	TycoonSim.assign(s, 0, 0)
	s["last_seen"] = NOW
	TycoonSim.settle(s, NOW + 30)
	var after_forward := float((s["orders"][0] as Dictionary)["done"])
	t.near(after_forward, 30.0, "前置：正常前進 30 秒")

	# 把系統時間調回一天前。
	var back := TycoonSim.settle(s, NOW + 30 - 86_400)
	t.near(back, 0.0, "★ 時鐘倒退 → 推進 0 秒（不罰：進度不倒扣）")
	t.near(
		float((s["orders"][0] as Dictionary)["done"]), after_forward,
		"★ 倒退之後進度原封不動"
	)
	# 再調回來：**不補償**。`last_seen` 已經被推到那個較早的點，
	# 所以「調回來」等於把那一天重新跑一次——作弊沒好處，誠實也沒損失。
	TycoonSim.settle(s, NOW + 30)
	t.near(
		float((s["orders"][0] as Dictionary)["done"]), TycoonSim.work_of(1),
		"★ 調回來只是正常地把那段時間跑掉，沒有額外補償"
	)

	# 第一次進來（`last_seen` ＝ 0）不能把 1970 年到現在整段算進去。
	var virgin := _at_level(1)
	TycoonSim.accept(virgin, 1)
	TycoonSim.assign(virgin, 0, 0)
	TycoonSim.settle(virgin, 1_800_000_000)
	t.near(
		float((virgin["orders"][0] as Dictionary)["done"]), 0.0,
		"★ 從沒開過公司 → 第一次進來不結算（否則等於白送 50 年）"
	)


# ── ④ 沒有失敗狀態 ───────────────────────────────────────────────────

func _no_failure_state(t: T) -> void:
	var s := _at_level(4)
	TycoonSim.accept(s, 1)
	TycoonSim.accept(s, 1)
	TycoonSim.assign(s, 0, 0)
	TycoonSim.accrue(s, 45.0)
	# 把另一張擠上同一格產線位。
	TycoonSim.assign(s, 1, 0)
	t.eq(TycoonSim.order_on_line(s, 0), 1, "後放的那張佔住了產線位")
	t.eq(int((s["orders"][0] as Dictionary)["line"]), -1, "先放的那張被擠下線")
	t.near(
		float((s["orders"][0] as Dictionary)["done"]), 45.0,
		"★ 被擠下線的訂單**進度不歸零**——會讓玩家不敢動的設計就是一種失敗狀態"
	)

	# 擴廠買不起就什麼都不動（不會扣一半的錢，也不會有懲罰）。
	var poor := _fresh()
	poor["credits"] = TycoonSim.expand_cost(1) - 1
	t.ok(not TycoonSim.expand(poor), "資金不夠 → 擴不了")
	t.eq(int(poor["credits"]), TycoonSim.expand_cost(1) - 1, "而且一毛錢都沒扣")
	t.eq(int(poor["level"]), 1, "廠等也沒動")

	var maxed := _at_level(TycoonSim.MAX_LEVEL)
	t.ok(not TycoonSim.expand(maxed), "滿級就擴不了（M2 上限 8）")
	t.eq(int(maxed["credits"]), 999999, "滿級時按擴廠也不會扣錢")


# ── UI 深度上限兩個畫面（每批 QA 必查的硬指標）───────────────────────

func _ui_depth_is_two_screens(t: T) -> void:
	# ★ 這一條驗的是**檔案數**，不是畫面數——聽起來蠢，但它是唯一擋得住
	#   「漸進膨脹」（風險 R-2）的自動化手段。人會忘記查，grep 不會。
	#   多出第三個 `Tycoon*.gd` 畫面的那一天，這條會紅，而那正是要談的時候。
	var found: Array[String] = []
	for f: String in DirAccess.get_files_at("res://scripts/screens"):
		# ⚠ `get_files_at()` 在原始碼樹上也會回 `.uid`（Godot 4.4+ 的匯入產物）。
		#   第一版沒濾，於是「兩個畫面」量出來是四個。
		if f.begins_with("Tycoon") and f.ends_with(".gd"):
			found.append(f)
	found.sort()
	t.eq(
		found, ["TycoonLines.gd", "TycoonOrders.gd"] as Array[String],
		"★ tycoon 的畫面恰好兩個（`00_CONCEPT.md` §三 約束 2 的硬指標）"
	)


# ── ③ 憲法 B6：塔防完全不依賴 tycoon ────────────────────────────────

func _campaign_needs_no_tycoon(t: T) -> void:
	# 「從沒開過公司」＝ tycoon 全預設。這份存檔要能推完戰役五關。
	var save := SaveService.defaults()
	t.eq(
		save["tycoon"], _fresh(),
		"前置：這份存檔的公司是全預設的（從沒開過）"
	)
	t.eq(
		int((save["tycoon"] as Dictionary)["last_seen"]), 0,
		"前置：連時間戳都還沒寫過"
	)

	# 五關的參考解逐關實跑。**這不是抽樣**——B6 是憲法，不是善意。
	# （完整的通關驗證在 `campaign_test`；這裡驗的是「tycoon 一個字都沒給」
	#   這個前提下同一份參考解仍然成立，而且**走的是同一支 `apply_timeline`**
	#   ——自己複製一份操作解譯器的話，兩邊遲早會不一樣。）
	var step := func(st: RefCounted) -> void: BattleController.step(st)
	for i in CampaignData.LEVELS.size():
		var level: Dictionary = CampaignData.at(i)
		var s: RefCounted = SessionState.new()
		s.setup(level["map"], level["unlocked"])
		var failures: Array = BuildController.apply_timeline(s, level["demo"], step)
		t.eq(
			failures.size(), 0,
			"第 %d 關的參考解一步都沒失敗（tycoon 全預設）" % (i + 1)
		)
		t.ok(
			s.core_hp() > 0.0,
			"★ 第 %d 關的參考解在「從沒開過公司」的存檔下照樣活著（憲法 B6）" % (i + 1)
		)

	# 而且名冊也走得通：純戰役滿星仍然畢業得了（tycoon 只是加法）。
	var maxed := SaveService.defaults()
	var stars: Dictionary = (maxed["campaign"] as Dictionary)["stars"]
	for id: String in CampaignData.ids():
		stars[id] = 3
	t.ok(
		Roster.earned(maxed) >= Roster.RECRUIT_POOL.size(),
		"★ 純戰役滿星就湊得到全部券——tycoon 那條路是加法不是替代（B6）"
	)


# ── 存檔往返 ─────────────────────────────────────────────────────────

func _save_round_trip(t: T) -> void:
	var d := SaveService.defaults()
	var s: Dictionary = d["tycoon"]
	s["level"] = 5
	s["credits"] = 1234
	s["components"] = 42
	s["tokens"] = 3
	s["last_seen"] = 1_700_000_000
	TycoonSim.accept(s, 2)
	TycoonSim.assign(s, 0, 1)
	TycoonSim.accrue(s, 17.5)

	var json := JSON.stringify(d)
	var back: Dictionary = SaveService.normalize(JSON.parse_string(json))
	var bt: Dictionary = back["tycoon"]
	t.eq(int(bt["level"]), 5, "廠等往返")
	t.eq(int(bt["credits"]), 1234, "資金往返")
	t.eq(int(bt["components"]), 42, "升級材料往返")
	t.eq(int(bt["tokens"]), 3, "招募券往返")
	t.eq(int(bt["last_seen"]), 1_700_000_000, "時間戳往返")
	t.eq((bt["orders"] as Array).size(), 1, "訂單往返")
	t.near(float((bt["orders"][0] as Dictionary)["done"]), 17.5, "★ 進度是小數，走 JSON 不會被截成整數")
	t.eq(int((bt["orders"][0] as Dictionary)["line"]), 1, "產線位往返")

	# ★ 舊存檔（完全沒有 `tycoon` 這一鍵）讀進來要長出預設值，而且不掉別的東西。
	var old := {"sv": 2, "tech": {"unlocked": ["cap1"], "data": 99}}
	var fixed := SaveService.normalize(old)
	t.eq(fixed["tycoon"], _fresh(), "★ 舊存檔補得出 tycoon 預設（只增不破）")
	t.eq(int((fixed["tech"] as Dictionary)["data"]), 99, "而且原有的東西一個都沒掉")
