extends SceneTree
## M2 驗收（G2 閘門，`40_PRODUCTION_PLAN.md` B2.8、`50_QA_PLAN.md` 里程碑清單）。
##
## 這支測試**不重測任何單一系統**——那十八支各自的測試已經在做了。它問的是
## 只有把全部系統擺在一起才問得出來的三件事：
##
##   ① **內容矩陣的實測值**（`10_GDD.md` §5）。印成一張表，並斷言不得**倒退**
##      ——內容數量沒有人在看的話，一次重構刪掉一隻角色不會有任何東西抗議。
##   ② **做了但到不了的內容**（G3 清單的「全內容可到達」提前做）。每一種可蓋的
##      節點、每一隻敵人、每一隻角色都要**至少有一個模式到得了它**。
##   ③ **玩過一輪之後的存檔仍然是乾淨的**：全部系統各寫一次，然後 `normalize()`
##      一次不變、頂層沒有任何 schema 不認得的孤兒鍵。
##
## 跑法：<godot> --headless --path godot --script res://tests/m2_test.gd

const T := preload("res://tests/_assert.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Campaign := preload("res://data/Campaign.gd")
const Maps := preload("res://data/Maps.gd")
const Tech := preload("res://data/Tech.gd")
const Levels := preload("res://data/Levels.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const Achievements := preload("res://data/Achievements.gd")
const Roster := preload("res://data/Roster.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")

## §5 內容矩陣的 M1 欄（**下限**，不是目標）。M2／M3 的差距由 §5 那張表
## 與 `40_PRODUCTION_PLAN.md` §5 記錄，這裡守的是「不得倒退」。
const M1_FLOOR := {
	"角色（塔）": 5,
	"生產節點": 5,
	"敵人": 3,
	"戰役關卡": 5,
	"科技節點": 12,
	"無盡佈局": 1,
}


func _initialize() -> void:
	var t := T.new("m2_test")
	_content_matrix(t)
	_everything_is_reachable(t)
	_full_playthrough_save_is_clean(t)
	_red_lines_still_hold(t)
	quit(t.report())


# ── ④ 兩條紅線（`10_GDD.md` §1 R1／R2） ──────────────────────────────

## G2 的「§2 的設計承諾斷言全部生效」在兩條紅線上有一個缺口：
## **R1（失敗只花時間）與 R2（無體力／次數閘門）沒有任何測試在守。**
##
## 它們現在是空的——因為變現系統排 M4，還沒有東西可以違反它們。而那正是
## 該寫斷言的時機：**等到有東西違反再寫，就是等到玩家先看到它。**
func _red_lines_still_hold(t: T) -> void:
	# ★ R2：存檔 schema 上不得出現任何「次數／體力／重試」欄位。
	#   列舉禁字而不是列舉允許的欄位：允許清單每加一個功能就要改一次，
	#   而禁字清單只在有人**真的想加一個體力條**的時候才會擋到人。
	var banned := ["stamina", "energy_cap", "lives", "retries", "attempts", "plays_today", "tickets"]
	var keys: Array[String] = []
	_collect_keys(SaveService.DEFAULTS, "", keys)
	for key: String in keys:
		for word: String in banned:
			t.ok(not key.to_lower().contains(word),
				"★★ 紅線 R2：存檔欄位 `%s` 不是次數／體力閘門" % key)

	# ★ R1：輸掉一局**不得減少任何持久狀態**。
	#   走的是真正的局末結算路徑（0 波、0 產能、0 星），不是一個假設。
	var save := SaveService.defaults()
	((save["campaign"] as Dictionary)["stars"] as Dictionary)[Campaign.id_at(0)] = 3
	SaveService.apply_components(save, 40)
	SaveService.apply_level_up(save, Levels.TOWER)
	SaveService.apply_endless(save, 18, 4.0, 0)
	var before := SaveService.normalize(save).duplicate(true)
	var comps_before := SaveService.components(save)

	SaveService.apply_result(save, Campaign.id_at(0), 0, 100)   # 0 星＝輸了
	SaveService.apply_components(save, 0)                        # 0 波
	SaveService.apply_endless(save, 0, 0.0, 0)
	var after := SaveService.normalize(save)

	t.eq(int(((after["campaign"] as Dictionary)["stars"] as Dictionary)[Campaign.id_at(0)]), 3,
		"★★ 紅線 R1：輸掉一局不扣星")
	t.eq(int(Difficulty.best(after, 0)["wave"]), 18, "★★ 紅線 R1：輸掉一局不扣無盡紀錄")
	t.eq(SaveService.components(save), comps_before, "★★ 紅線 R1：輸掉一局不扣材料")
	t.eq(int((after["levels"] as Dictionary)["tower"]), int((before["levels"] as Dictionary)["tower"]),
		"★★ 紅線 R1：輸掉一局不掉等級")
	t.eq(after["tech"], before["tech"], "★★ 紅線 R1：輸掉一局不扣研究數據")


static func _collect_keys(d: Dictionary, prefix: String, out: Array[String]) -> void:
	for k: String in d.keys():
		out.append(prefix + k)
		if d[k] is Dictionary:
			_collect_keys(d[k], prefix + k + ".", out)


# ── ① 內容矩陣 ───────────────────────────────────────────────────────

func _content_matrix(t: T) -> void:
	var towers := 0
	var prod := 0
	for type: String in NodeDefs.DEFS.keys():
		if bool(NodeDefs.of(type).get("tower", false)):
			towers += 1
		elif type != "core":
			prod += 1

	var actual := {
		"角色（塔）": towers,
		"生產節點": prod,
		"敵人": Enemies.DEFS.size(),
		"戰役關卡": Campaign.count(),
		"科技節點": Tech.count(),
		"無盡佈局": 1,
		"難度層": Difficulty.MAX_TIER,
		"成就": Achievements.count(),
		"tycoon 訂單品項": TycoonSim.ORDER_NAMES.size(),
		"tycoon 廠等": TycoonSim.MAX_LEVEL,
	}
	# §5 的 M2 欄（目標）。**印出來，不斷言**——差距是製作人的排程決定，
	# 不是一個測試該否決的東西。斷言只守「不得倒退」。
	var m2_target := {
		"角色（塔）": 16, "生產節點": 11, "敵人": 12, "戰役關卡": 15,
		"科技節點": 30, "無盡佈局": 3, "難度層": 3, "成就": 20,
		"tycoon 訂單品項": 8, "tycoon 廠等": 10,
	}
	print("  ── 內容矩陣實測（`10_GDD.md` §5）")
	for key: String in actual:
		var got := int(actual[key])
		var want := int(m2_target[key])
		print("     %-16s 實際 %3d ／ M2 目標 %3d　%s" % [
			key, got, want, "✔" if got >= want else "缺 %d" % (want - got)
		])
	for key: String in M1_FLOOR:
		t.ok(int(actual[key]) >= int(M1_FLOOR[key]),
			"★ 內容不得倒退：%s 至少 %d（M1 已交的量）" % [key, int(M1_FLOOR[key])])


# ── ② 做了但到不了的內容 ────────────────────────────────────────────

## G2 的「每個系統可玩」在內容層的樣子：**每一種做出來的東西都要有一條路走到它。**
## 做了卻進不去的內容比沒做更糟——它會出現在圖鑑、成就與名冊裡，然後永遠是灰的。
func _everything_is_reachable(t: T) -> void:
	# 建造欄的聯集：戰役各關 ∪ 統一配置榜 ∪ 名冊全滿。
	var buildable: Dictionary = {}
	for i in Campaign.count():
		for type: String in (Campaign.at(i) as Dictionary)["unlocked"]:
			buildable[type] = true
	for type: String in Daily.UNIFORM_BUILD:
		buildable[type] = true
	var full := SaveService.defaults()
	for id: String in Campaign.ids():
		((full["campaign"] as Dictionary)["stars"] as Dictionary)[id] = 3
	(full["roster"] as Dictionary)["recruited"] = Roster.all()
	for type: String in Roster.buildable(full):
		buildable[type] = true
	for type: String in NodeDefs.BUILDABLE:
		t.ok(buildable.has(type), "★ 「%s」在某個模式的建造欄裡到得了" % NodeDefs.label(type))

	# 每一隻敵人都要真的出場：戰役五關的波次表 ∪ 無盡的出場池。
	var spawned: Dictionary = {}
	for i in Campaign.count():
		for wave: Variant in Maps.waves_of((Campaign.at(i) as Dictionary)["map"]):
			for entry: Variant in (wave as Dictionary).get("spawn", []):
				spawned[String((entry as Dictionary)["type"])] = true
	for w in range(1, 40):
		for e: Variant in Enemies.endless_schedule(12345, w):
			spawned[String((e as Dictionary)["type"])] = true
	for type: String in Enemies.DEFS.keys():
		t.ok(spawned.has(type), "★ 敵人「%s」真的會出場" % String(Enemies.of(type)["name"]))

	# 每一隻角色都有取得途徑（`Roster.unlock_hint()` 說得出來）。
	for type: String in Roster.all():
		t.ok(Roster.unlock_hint(type) != "", "★ 角色「%s」說得出怎麼拿到" % NodeDefs.label(type))

	# 每一條成就都要有人推得動它（metric 真的在 `metrics()` 上）。
	var metrics := Achievements.metrics(full)
	for a: Dictionary in Achievements.LIST:
		t.ok(metrics.has(String(a["metric"])),
			"★ 成就「%s」的計量 `%s` 真的被量" % [String(a["name"]), String(a["metric"])])

	# 生成器：同一個種子必得同一張圖，而且開得出來（§7.10 的不變量由
	# `endless_test` 逐條守；這裡只確認 M2 宣稱的那 1 種佈局真的接得上）。
	var g1 := MapGen.generate(4242)
	t.ok(bool(g1.get("endless", false)), "無盡佈局產得出地圖")
	t.eq(Maps.path_of(g1).size(), Maps.path_of(MapGen.generate(4242)).size(), "同種子同圖")


# ── ③ 玩過一輪之後的存檔 ────────────────────────────────────────────

## L4 冒煙遊玩的存檔版本：**每一個系統各寫一次**，然後問三件事——
##   · `normalize()` 一次不變（冪等，不會每次開遊戲就變形一點）
##   · 頂層沒有 schema 不認得的孤兒鍵（有的話玩家的檔會愈長愈大而沒有人讀它）
##   · 全部推導出來的數字都算得出來（材料餘額、公司等級、券、解鎖層）
func _full_playthrough_save_is_clean(t: T) -> void:
	var save := SaveService.defaults()

	# 戰役：通關第 1 關拿三星。
	SaveService.apply_result(save, Campaign.id_at(0), 3, int((Campaign.at(0) as Dictionary)["reward"]))
	# 科技：買一個節點。
	((save["tech"] as Dictionary)["unlocked"] as Array).append("cap1")
	# 藍圖：存一張。
	var bp := {"nodes": [{"type": "extractor", "at": [0, 0]}], "conduits": []}
	SaveService.add_blueprint(save, bp, 2)
	# 名冊：招一隻（先把戰役塞滿星才有券）。
	for id: String in Campaign.ids():
		((save["campaign"] as Dictionary)["stars"] as Dictionary)[id] = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var got := SaveService.apply_recruit(save, rng)
	t.ok(got != "", "招募寫得進存檔")
	# tycoon：接單 → 上線 → 生產 → 收成。
	var ty: Dictionary = save["tycoon"]
	t.ok(TycoonSim.accept(ty, TycoonSim.available_tiers(1)[0]), "訂單接得下來")
	t.ok(TycoonSim.assign(ty, 0, 0), "訂單上得了產線")
	TycoonSim.accrue(ty, 9999.0)
	t.ok(TycoonSim.collect(ty, 0), "訂單收得成")
	# 等級軸：局末材料 → 升一級。
	SaveService.apply_components(save, 40)
	t.ok(SaveService.apply_level_up(save, Levels.TOWER), "等級軸升得了級")
	# 無盡與每日：兩邊各記一筆。
	SaveService.apply_endless(save, 12, 3.5, 0)
	SaveService.apply_daily(save, "2026-01-01", Daily.FREE, 9, 2.0)

	# ★ 冪等：`normalize()` 一次不得改動任何東西。
	var norm := SaveService.normalize(save)
	var twice := SaveService.normalize(norm)
	t.eq(twice, norm, "★★ 玩過一輪的存檔：normalize 冪等（每次開遊戲不會再變形一點）")

	# ★ 沒有孤兒鍵：頂層每一個鍵都在 schema 上。
	for key: String in norm.keys():
		t.ok(SaveService.DEFAULTS.has(key), "★ 頂層鍵 `%s` 在 schema 上（沒有沒人讀的孤兒欄位）" % key)
	for key: String in SaveService.DEFAULTS.keys():
		t.ok(norm.has(key), "schema 的 `%s` 在存檔裡" % key)

	# ★ 全部推導值都算得出來，而且是這一輪真的推出來的（不是預設值）。
	t.ok(SaveService.components(norm) > 0, "材料餘額 > 0（局末結算那條路走過了）")
	t.ok(Achievements.company_level(norm) >= 1, "公司等級算得出來")
	t.ok(Achievements.done(norm).size() > 0, "★ 這一輪真的達成了成就（推導的，沒有領取鈕）")
	t.eq(Difficulty.unlocked(norm), 1, "★ 戰役全通之後第 1 層開了")
	t.ok(int(Difficulty.best(norm, 0)["wave"]) == 12, "無盡紀錄記在第 0 層")
	t.ok(Roster.owned(norm).size() > 1, "名冊不只有起始那一隻")
	t.ok((norm["blueprints"] as Array).size() == 1, "藍圖存得住")
	t.ok(int((norm["tycoon"] as Dictionary)["credits"]) > 0, "公司真的賺到錢")

	# ★ 讀回來的每一格仍然是玩家那一份（`_repair_containers()` 不得誤傷）。
	t.eq(int(((norm["campaign"] as Dictionary)["stars"] as Dictionary)[Campaign.id_at(0)]), 3,
		"★ 反向對照：型別修復沒有動到玩家的星數")
