extends SceneTree
## 科技樹（`10_GDD.md` §3.6、§7.8；B1.3）。
##
## 這支測試守的是三件事，而**第三件才是重點**：
##   ① 成本表與 GDD §7.8 的那張表逐格相同（數值只有一個來源）。
##   ② B2 硬上限：全解鎖對戰鬥數值的總增幅 ≤ +35%。
##   ③ ★ **科技真的改變模擬結果。** 一個買了沒生效的科技在畫面上完全正常——
##      它只是讓玩家的研究數據消失。所以每一種效果都要在**跑過的 tick 上**
##      量到差異，不是只斷言 `mods()` 的回傳值。
##
## 跑法：<godot> --headless --path godot --script res://tests/tech_test.gd

const T := preload("res://tests/_assert.gd")
const Tech := preload("res://data/Tech.gd")
const Maps := preload("res://data/Maps.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")


func _initialize() -> void:
	var t := T.new("tech_test")
	_costs_match_gdd(t)
	_prereq_chain(t)
	_can_unlock(t)
	_mods_resolve(t)
	_b2_combat_cap(t)
	_cap_tech_moves_flow(t)
	_mine_tech_moves_ore(t)
	_engage_tech_moves_demand(t)
	_damage_tech_moves_kills(t)
	_no_tech_changes_nothing(t)
	_save_round_trip(t)
	quit(t.report())


## ① 成本＝`50 × tier^1.6`，與 §7.8 的表逐格相同。
func _costs_match_gdd(t: T) -> void:
	t.eq(Tech.count(), 12, "M1 首批 12 節點")
	var want := {
		"cap1": 50, "cap2": 152, "cap3": 289,
		"mine1": 50, "mine2": 152,
		"eff1": 50, "eff2": 152, "eff3": 289,
		"cal1": 50, "cal2": 152,
		"bp1": 50, "bp2": 152,
	}
	for id: String in want.keys():
		t.eq(Tech.cost(id), int(want[id]), "成本表 %s（GDD §7.8）" % id)
	# 全解鎖的總價。戰役滿星全通是 855，**買不完 12 個是刻意的**：
	# 科技樹要撐過 M2 的無盡與每日，一輪戰役就清空等於它只有一次意義。
	var total := 0
	for id: String in _all_ids():
		total += Tech.cost(id)
	t.eq(total, 1588, "12 節點全解鎖總價")


## ② 前置＝同一串的前一階；跨串沒有前置。
func _prereq_chain(t: T) -> void:
	t.eq(Tech.prereq("cap1"), "", "第一階無前置")
	t.eq(Tech.prereq("cap2"), "cap1", "導管擴容 II ← I")
	t.eq(Tech.prereq("cap3"), "cap2", "導管擴容 III ← II")
	t.eq(Tech.prereq("eff3"), "eff2", "能量效率 III ← II")
	t.eq(Tech.prereq("mine1"), "", "採集精煉 I 不需要導管擴容（不同串）")


func _can_unlock(t: T) -> void:
	t.eq(Tech.can_unlock("cap1", [], 50.0), Tech.OK, "剛好付得起 → 可解鎖")
	t.eq(Tech.can_unlock("cap1", [], 49.0), Tech.NO_DATA, "差 1 點 → 擋下")
	t.eq(Tech.can_unlock("cap2", [], 9999.0), Tech.NEEDS_PREREQ, "跳階 → 擋下")
	t.eq(Tech.can_unlock("cap1", ["cap1"], 9999.0), Tech.ALREADY, "重複購買 → 擋下")
	t.eq(Tech.can_unlock("nope", [], 9999.0), Tech.UNKNOWN, "不存在的 id → 擋下")


func _mods_resolve(t: T) -> void:
	var none := Tech.mods([])
	t.near(float(none["cap_bonus"]), 0.0, "未解鎖：cap 加成 0")
	t.near(float(none["engage_mult"]), 1.0, "未解鎖：交戰耗能乘數 1")
	t.near(float(none["damage_mult"]), 1.0, "未解鎖：傷害乘數 1")

	var full := Tech.mods(_all_ids())
	t.near(float(full["cap_bonus"]), 6.0, "導管擴容三級：基礎 cap +6（10 → 16）")
	t.near(float(full["extractor_ore"]), 2.0, "採集精煉二級：採集器 +2 礦砂/秒")
	t.near(float(full["engage_mult"]), 0.92 * 0.92 * 0.92, "能量效率三級連乘")
	t.near(float(full["damage_mult"]), 1.06 * 1.06, "校準二級連乘")
	t.near(float(full["blueprint_slots"]), 2.0, "藍圖槽 +2")

	# ★ 順序無關：存檔裡 `unlocked` 的排列不得影響任何一個數字。
	var reversed_ids := _all_ids()
	reversed_ids.reverse()
	t.eq(Tech.mods(reversed_ids), full, "★ mods 與解鎖順序無關（確定性前提）")

	# 滿配 cap：科技 +6 與局內加粗 +18 疊加 → 34（§7.2 註）。
	t.near(
		Build.conduit_cap(Build.CAP_MAX_LEVEL, float(full["cap_bonus"])), 34.0,
		"滿配導管 cap 34（科技 16 ＋ 局內三級）"
	)


## ★ B2 硬上限（`10_GDD.md` §1 B2）：全解鎖對**戰鬥數值**的總增幅 ≤ +35%。
## 這一條是 B1.3 DoD 明列的斷言。日後往防務支加節點時，它會先變紅。
func _b2_combat_cap(t: T) -> void:
	var gain := Tech.combat_gain(_all_ids())
	t.ok(gain <= 0.35, "★ B2：全解鎖戰鬥增幅 %.4f ≤ 0.35" % gain)
	# 也不能離上限太遠——離太遠代表這 12 個節點根本沒把 M1 的預算用掉。
	t.ok(gain >= 0.30, "全解鎖戰鬥增幅 %.4f 有用掉 M1 的預算" % gain)
	t.near(gain, 0.1236 + 0.2213, "戰鬥增幅＝傷害增幅 ＋ 交戰耗能降幅", 0.0002)
	t.near(Tech.combat_gain([]), 0.0, "未解鎖：戰鬥增幅 0")


## ★ ③-a 導管擴容：同一條線、同一份供給，**送得過去的量真的變多**。
func _cap_tech_moves_flow(t: T) -> void:
	var base := _flow_through_one_line([])
	var teched := _flow_through_one_line(["cap1", "cap2", "cap3"])
	t.near(base, 10.0, "基礎導管吞吐 10/秒（兩座採集器產 12，被幹線卡掉 2）")
	# 幹線升到 16 之後**瓶頸就不在管子上了**，全部 12 都送得過去。
	# 這正是這個科技買的東西——把 12 也一起壓成 16 的測試會量到供給，不是 cap。
	t.near(teched, 12.0, "★ 導管擴容三級 → 瓶頸移開，12 全數入帳（模擬實測）")
	t.near(Build.conduit_cap(0, 6.0), 16.0, "科技三級的基礎 cap＝16")


## 一條「兩座採集器 → 一條幹線 → 核心」的圖每秒實際送達多少。
## 採集器產 6/秒 < cap 10，**兩座才頂得到上限**——這裡要量的是管子，不是礦。
## 幹線是 (2,6)→(6,6) 那一段，全圖唯一的瓶頸。
func _flow_through_one_line(tech: Array) -> float:
	var s := _sandbox(tech)
	_build(s, [
		["place", "extractor", Vector2i(2, 2)],
		["place", "extractor", Vector2i(4, 4)],
		["place", "relay", Vector2i(2, 6)],
		["place", "relay", Vector2i(6, 6)],
		["conduit", Vector2i(2, 2), Vector2i(2, 6)],    # 垂直
		["conduit", Vector2i(4, 4), Vector2i(2, 6)],    # 45°
		["conduit", Vector2i(2, 6), Vector2i(6, 6)],    # ★ 幹線（唯一瓶頸）
		["conduit", Vector2i(6, 6), Vector2i(10, 10)],  # 45° 進核心
	])
	for _i in 20:
		BattleController.step(s)
	return float(s.rates["ore_in"])


## ★ ③-b 採集精煉：入帳速率真的變快。用**兩條各自獨立的線**避開 cap 上限，
## 否則加成會被管子吃掉，而測試會誤判成「科技沒生效」。
func _mine_tech_moves_ore(t: T) -> void:
	t.near(_two_line_ore([]), 12.0, "兩座採集器 12 礦砂/秒")
	t.near(_two_line_ore(["mine1", "mine2"]), 16.0, "★ 採集精煉二級 → 16 礦砂/秒")


## 兩條**互相獨立**的線，各自 6/秒（＜cap 10）。加成因此量得到，不會被管子吃掉。
func _two_line_ore(tech: Array) -> float:
	var s := _sandbox(tech)
	_build(s, [
		["place", "extractor", Vector2i(2, 2)],
		["place", "extractor", Vector2i(4, 4)],
		["place", "relay", Vector2i(2, 6)],
		["place", "relay", Vector2i(6, 6)],
		["place", "relay", Vector2i(4, 10)],
		["conduit", Vector2i(2, 2), Vector2i(2, 6)],
		["conduit", Vector2i(2, 6), Vector2i(6, 6)],
		["conduit", Vector2i(6, 6), Vector2i(10, 10)],
		["conduit", Vector2i(4, 4), Vector2i(4, 10)],    # 第二條：垂直下來
		["conduit", Vector2i(4, 10), Vector2i(10, 10)],  # 再水平進核心
	])
	for _i in 20:
		BattleController.step(s)
	return float(s.rates["ore_in"])


func _sandbox(tech: Array) -> RefCounted:
	var s := SessionState.new()
	s.setup(Maps.SANDBOX, [], {"tech": tech})
	s.ore = 99999.0
	return s


## ★ **建造失敗一律當場炸掉，不要靜靜跳過。**
## 幾何寫錯時 `lay_conduit` 只回一個原因碼，測試會照跑，然後量到 0——
## 而 0 看起來就像「科技沒生效」。B1.2 花了好幾輪在這個坑上。
func _build(s: RefCounted, ops: Array) -> void:
	var fails := BuildController.apply_ops(s, ops)
	assert(fails.is_empty(), "測試佈局蓋不起來：%s" % str(fails))


## ★ ③-c 能量效率：**交戰中**的塔耗電變少。
## 待機時本來就是 0，所以這一條必須有敵人在射程內才驗得到（v0.3 定案第 ⑬ 條）。
func _engage_tech_moves_demand(t: T) -> void:
	var base := _engaged_demand([])
	var teched := _engaged_demand(["eff1", "eff2", "eff3"])
	t.ok(base > 0.0, "交戰中的錨確實在吃電（前提成立，否則下一條沒有意義）")
	t.near(teched / base, 0.92 * 0.92 * 0.92, "★ 能量效率三級 → 交戰需求 ×0.7787", 0.001)


## 一座通了電的錨，路徑上釘一隻打不死的敵人，回傳「本 tick 能量需求」。
func _engaged_demand(tech: Array) -> float:
	var s := _armed_anchor(tech)
	BattleController.step(s)
	return float(s.rates["power_demand"])


## 共用的戰鬥夾具：錨 (14,6)、發電機 (14,10)、採集器在礦點 (16,8)。
##
## 幾何上的三個約束同時成立才有意義：錨離路徑 ≥2 格（walk-by 打不到）、
## 敵人 (14,4) 在射程 4 之內、三條線都不共線（B1.6.1 的重疊規則）。
func _armed_anchor(tech: Array) -> RefCounted:
	var s := SessionState.new()
	s.setup(Maps.SHOAL, [], {"tech": tech})
	s.ore = 99999.0
	_build(s, [
		["place", "anchor", Vector2i(14, 6)],
		["place", "generator", Vector2i(14, 10)],
		["place", "extractor", Vector2i(16, 8)],
		["conduit", Vector2i(16, 8), Vector2i(14, 10)],   # 45°
		["conduit", Vector2i(14, 10), Vector2i(14, 6)],   # 垂直
	])
	s.add_enemy("drifter")
	var e: Dictionary = s.enemies[0]
	e["progress"] = 14.0        # path[14] = (14,4)
	e["hp"] = 1e9               # 別讓它被打死——需求會歸零，量到的就是 0
	s.phase = "wave"
	return s


## ★ ③-d 校準：同樣的一段時間，敵人掉的血真的變多。
func _damage_tech_moves_kills(t: T) -> void:
	var base := _damage_dealt([])
	var teched := _damage_dealt(["cal1", "cal2"])
	t.ok(base > 0.0, "沒科技時錨打得出傷害（前提成立）")
	t.near(teched / base, 1.06 * 1.06, "★ 校準二級 → 傷害 ×1.1236", 0.001)


## 同一組夾具打 60 tick，回傳打掉的血量。
func _damage_dealt(tech: Array) -> float:
	var s := _armed_anchor(tech)
	var e: Dictionary = s.enemies[0]
	var before := float(e["hp"])
	for _i in 60:
		BattleController.step(s)
		e["progress"] = 14.0     # 釘住位置：要量的是傷害，不是它有沒有走出射程
	return before - float(e["hp"])


## ★ **沒買科技的一局，數字必須和 B1.3 之前完全一樣。**
## 這條看起來多餘，但它是整批最重要的回歸：`mods` 的預設值只要有一個寫錯，
## 已經校準過的五關參考解與平衡基準線會整組漂掉，而且不會有人立刻發現。
func _no_tech_changes_nothing(t: T) -> void:
	var m := Tech.mods([])
	t.eq(m, Tech.NO_MODS, "空解鎖清單 → 中性 mods")
	var s := SessionState.new()
	s.setup(Maps.SHOAL)                      # 連 tech 參數都不傳（舊呼叫端的樣子）
	t.eq(s.mods, Tech.NO_MODS, "★ 不傳 tech 的 setup() → 中性 mods（舊呼叫端行為不變）")
	t.near(Build.conduit_cap(0), 10.0, "無科技：基礎 cap 仍是 10")
	t.near(Build.conduit_cap(3), 28.0, "無科技：滿級 cap 仍是 28")


## 存檔：只增不破。`tech` 已在 sv1 的 schema 裡，這裡守的是**殘缺存檔補得回來**。
func _save_round_trip(t: T) -> void:
	var d := SaveService.normalize({"tech": {"unlocked": ["cap1", "eff1"]}})
	t.eq((d["tech"] as Dictionary)["unlocked"], ["cap1", "eff1"], "已解鎖清單讀得回來")
	t.eq(float((d["tech"] as Dictionary)["data"]), 0.0, "缺 data 欄補 0，不是崩潰")
	var empty := SaveService.normalize({})
	t.eq((empty["tech"] as Dictionary)["unlocked"], [], "全新存檔：沒有任何科技")
	# 局末獎勵仍然只進 data，不會憑空塞科技進去。
	var d2 := SaveService.defaults()
	SaveService.apply_result(d2, "l1", 3, 30)
	t.eq(float((d2["tech"] as Dictionary)["data"]), 90.0, "三星第 1 關 → 90 研究數據")
	t.eq((d2["tech"] as Dictionary)["unlocked"], [], "獎勵不會自動解鎖任何科技")


## 全部節點的 id。**住在測試裡，不住在資料表裡**（B1.9）：`Tech.all_ids()`
## 從來沒有任何遊戲程式碼呼叫過，它是一支測試 helper 借住在數值權威裡面。
static func _all_ids() -> Array[String]:
	var out: Array[String] = []
	for n: Dictionary in Tech.NODES:
		out.append(String(n["id"]))
	return out
