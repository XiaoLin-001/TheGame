extends SceneTree
## 戰役五關（`10_GDD.md` §7.9、B1.2 DoD）。
##
## ★ 這支測試存在的唯一理由：**「這一關過得了」不能是一句宣稱。**
## 每一關都拿它自己的參考解實跑到底，斷言真的 `won`。B1.2 的硬性驗收
## 「第 1–2 關以新手可通關為條件、且只用關卡參數達成」——「只用關卡參數」
## 由 `_no_hidden_multiplier()` 守住，「通得了」由這裡的實跑守住。
##
## 跑法：<godot> --headless --path godot --script res://tests/campaign_test.gd

const T := preload("res://tests/_assert.gd")
const Campaign := preload("res://data/Campaign.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Roster := preload("res://data/Roster.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Shapes := preload("res://scripts/render/Shapes.gd")
const Score := preload("res://scripts/sim/Score.gd")
const SaveService := preload("res://scripts/core/SaveService.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")

## 一局跑多久才判定「跑不完」。五關最長的是第 5 關（準備期 45s ＋ 5 波），
## 4000 tick ＝ 400 秒，遠寬於任何一關的實際長度。
const MAX_TICKS := 9000
## 地圖框架（`screens/Battle.gd` 的 `FRAME`）。**一屏可見從此由縮放保證**，
## 不再靠「地圖必須小於這個尺寸」——所以這裡不再檢查格數上限，改檢查
## **fit 之後的格子還讀不讀得出來**（B1.2.2）。
const FRAME := Vector2(1152.0, 604.0)


func _initialize() -> void:
	var t := T.new("campaign_test", 431)
	_geometry(t)
	_frame_fit(t)
	_tower_geometry(t)
	_unlock_ladder(t)
	_no_hidden_multiplier(t)
	_locked_is_a_rule(t)
	_reference_solutions_win(t)
	_stars(t)
	_save_progress(t)
	quit(t.report())


# ── 地圖本身 ──────────────────────────────────────────────────────────

func _geometry(t: RefCounted) -> void:
	t.eq(Campaign.count(), 5, "戰役五關（`10_GDD.md` §7.9 內容矩陣 M1 = 5）")
	for i in Campaign.count():
		var lv: Dictionary = Campaign.at(i)
		var m: Dictionary = lv["map"]
		var name: String = m["name"]
		var size: Vector2i = m["size"]
		# ★ 一屏可見現在由框架＋自動 fit 保證（B1.2.2），所以要守的不是格數，
		#   而是**fit 之後一格還有幾個像素**——視覺編碼是在 32px 上驗收的。
		var cell_px := Shapes.fit_cell_px(size, FRAME)
		t.ok(
			cell_px >= Shapes.MIN_READABLE_CELL,
			"%s fit 後一格 %.1f px ≥ 可讀性地板 %.0f（%s）" % [
				name, cell_px, Shapes.MIN_READABLE_CELL, size
			]
		)
		var path := Maps.path_of(m)
		t.ok(path.size() > 0, "%s 有敵人路徑" % name)
		t.eq(path[path.size() - 1], m["core"], "%s 路徑終點就是核心" % name)
		var cells: Dictionary = {}
		for c: Vector2i in path:
			t.ok(
				c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y,
				"%s 路徑格 %s 在圖內" % [name, c]
			)
			cells[c] = true
		t.eq(cells.size(), path.size(), "%s 路徑不自我重疊" % name)
		# 跨越點必須真的在路徑上——不在路徑上的「橋」是一格不會被畫出來的謊。
		for c: Vector2i in m["crossings"]:
			t.ok(cells.has(c), "%s 跨越點 %s 落在路徑上" % [name, c])
		# 礦點不得壓在路徑上（採集器蓋不上去 → 那顆礦是裝飾）。
		for c: Vector2i in m["ore"]:
			t.ok(not cells.has(c), "%s 礦點 %s 不在路徑上" % [name, c])
			t.ok(
				c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y,
				"%s 礦點 %s 在圖內" % [name, c]
			)


## ★ RG-56：塔的擺位在幾何上必須成立（B1.7 補上的直接斷言）。
##
## 這兩條原本只被「參考解實跑必勝」間接守著——**間接守住的東西，壞掉時
## 指的是別的地方**：真正壞的是擺位，但失敗訊息會說「第 N 關輸了」。
##
##   ① **每一關至少要有一座會開火的塔搆得到核心。** 敵人只在核心駐足
##      （`10_GDD.md` walk-by），搆不到就代表任何一次漏怪都是必輸——
##      那不是難度，是關卡設計的漏洞。
##   ② **稜鏡必須和某一段路徑同排或同列。** 它是貫穿武器（沿軸線打穿一整列），
##      擺在沒有任何路徑格與它共線的地方 ＝ 一座 130 礦砂的裝飾品。
##
## 射程判定直接呼叫 `Combat` 的同一支函式，不在測試裡另寫一份幾何——
## 另寫的那一份會在某天和真的規則分岔，然後兩邊都「對」。
func _tower_geometry(t: RefCounted) -> void:
	for i in Campaign.count():
		var lv: Dictionary = Campaign.at(i)
		var m: Dictionary = lv["map"]
		var name: String = m["name"]
		var core: Vector2i = m["core"]
		var path := Maps.path_of(m)
		var covers_core := false
		var prisms := 0
		var prisms_aligned := 0
		for op: Array in lv["demo"]:
			if String(op[0]) != "place":
				continue
			var def := NodeDefs.of(String(op[1]))
			if not def.get("tower", false):
				continue
			var cell: Vector2i = op[2]
			var r := float(def.get("range", 0.0))
			# 不開火的塔（潮鳴 rof=0）搆得到核心也擋不住任何東西。
			if float(def.get("rof", 0.0)) > 0.0:
				if not Combat.in_range_indices(cell, [core], r).is_empty():
					covers_core = true
			if def.get("pierce", false):
				prisms += 1
				for c: Vector2i in path:
					if (c.x == cell.x or c.y == cell.y) and not Combat.in_range_indices(
						cell, [c], r
					).is_empty():
						prisms_aligned += 1
						break
		t.ok(covers_core, "%s 參考解至少一座會開火的塔搆得到核心（RG-56）" % name)
		t.eq(prisms_aligned, prisms, "%s 每一座稜鏡都和某一段路徑共線且在射程內（RG-56）" % name)


## ★ 地圖框架與自動 fit（B1.2.2，使用者要求）。
##
## 玩家看到的地圖區域**恆定**，進場時縮放到剛好填滿它。這裡守三件事：
##   ① fit 之後**至少一軸剛好填滿框架**（另一軸留邊是長寬比不同，不是漏算）
##   ② 兩軸都不溢出（溢出就不是「進場看得到全貌」）
##   ③ 每一關 fit 後的格子都在可讀性地板之上（上面 `_geometry` 已逐關檢查）
func _frame_fit(t: RefCounted) -> void:
	for i in Campaign.count():
		var m: Dictionary = (Campaign.at(i) as Dictionary)["map"]
		var size: Vector2i = m["size"]
		var z := Shapes.fit_zoom(size, FRAME)
		var px := Vector2(size) * Shapes.GRID * z
		t.ok(
			is_equal_approx(px.x, FRAME.x) or is_equal_approx(px.y, FRAME.y),
			"%s fit 後至少一軸填滿框架（%.1f×%.1f / %s）" % [m["name"], px.x, px.y, FRAME]
		)
		t.ok(
			px.x <= FRAME.x + 0.5 and px.y <= FRAME.y + 0.5,
			"%s fit 後兩軸都不溢出框架" % m["name"]
		)
	# 地板本身：40×40 這種圖會掉到 15px，**低於地板**——它不是不能做，
	# 是要先重新跑一次 `TL_NAKED` 讀圖驗收才能做（`50_QA_PLAN.md` RG-58）。
	t.ok(
		Shapes.fit_cell_px(Vector2i(40, 40), FRAME) < Shapes.MIN_READABLE_CELL,
		"40×40 的圖會掉到可讀性地板之下（%.1f px）——這條在提醒未來的人先驗收" % (
			Shapes.fit_cell_px(Vector2i(40, 40), FRAME)
		)
	)


## 解鎖階梯：**只增不減**，而且第 5 關等於全解鎖（§7.9）。
## 少了這條，「第 3 關拿掉稜鏡」這種改動不會有人發現。
func _unlock_ladder(t: RefCounted) -> void:
	var prev: Array = []
	for i in Campaign.count():
		var lv: Dictionary = Campaign.at(i)
		var now: Array = lv["unlocked"]
		for type: String in prev:
			t.ok(now.has(type), "第 %d 關沒有把 %s 收回去" % [i + 1, NodeDefs.label(type)])
		for type: String in now:
			t.ok(NodeDefs.BUILDABLE.has(type), "第 %d 關的 %s 是真的可建造類型" % [i + 1, type])
		prev = now
	# ★ 「全解鎖」＝**全部確定性節點**，不是 `BUILDABLE` 全表（B2.4 起兩者不同）。
	#   招募池那三隻不進戰役：戰役的建造欄是那一關要教的機制（§7.9），而
	#   「抽到才有的塔」教不了任何人任何事，也會讓參考解取決於玩家的手氣。
	var deterministic := 0
	for type: String in NodeDefs.BUILDABLE:
		if not Roster.RECRUIT_POOL.has(type):
			deterministic += 1
	t.eq(
		(Campaign.at(4)["unlocked"] as Array).size(), deterministic,
		"第 5 關全解鎖（＝全部確定性節點；招募池不進戰役）"
	)
	for type: String in Roster.RECRUIT_POOL:
		for i in Campaign.count():
			t.ok(
				not (Campaign.at(i)["unlocked"] as Array).has(type),
				"★ 招募專屬的 %s 不在第 %d 關的建造欄（參考解不吃手氣）" % [type, i + 1]
			)


## ★ R-4／§7.7：新手難度**只能**用關卡參數表達。
## 這裡守的是「沒有人偷偷加了一個係數」——關卡字典裡除了那幾個
## 玩家看得見的鍵之外，不准出現別的。
func _no_hidden_multiplier(t: RefCounted) -> void:
	var allowed := [
		"id", "name", "size", "core", "waypoints",
		"start_ore", "prep_time", "crossings", "ore", "waves",
	]
	for i in Campaign.count():
		var m: Dictionary = (Campaign.at(i) as Dictionary)["map"]
		for k: String in m.keys():
			t.ok(allowed.has(k), "第 %d 關的地圖沒有隱藏參數（發現 `%s`）" % [i + 1, k])


# ── ★ 參考解實跑 ──────────────────────────────────────────────────────

## 一關：套用參考解（含 `wait` 分段）→ 跑到結束 → 回傳結果摘要。
func _play(lv: Dictionary) -> Dictionary:
	var s: RefCounted = SessionState.new()
	s.setup(lv["map"], lv["unlocked"])
	var step := func(st: RefCounted) -> void: BattleController.step(st)
	var failures: Array = BuildController.apply_timeline(s, lv["demo"], step)
	while s.tick_count < MAX_TICKS and s.phase != "won" and s.phase != "lost":
		BattleController.step(s)
	var tp := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	return {
		"failures": failures,
		"phase": s.phase,
		"ticks": s.tick_count,
		"core_hp": s.core_hp(),
		"core_max": NodeDefs.hp("core"),
		"throughput": tp,
		"kills": s.kills,
		"ore": s.ore,
	}


func _reference_solutions_win(t: RefCounted) -> void:
	for i in Campaign.count():
		var lv: Dictionary = Campaign.at(i)
		var name: String = (lv["map"] as Dictionary)["name"]
		var r := _play(lv)
		# 建造腳本靜靜失敗會產生騙人的結論：那不是「這關通得了」，
		# 是「少蓋了三座塔還通得了」，兩者對關卡設計的意義完全相反。
		t.eq(r["failures"], [], "第 %d 關「%s」參考解沒有建造失敗" % [i + 1, name])
		t.eq(r["phase"], "won", "★ 第 %d 關「%s」參考解通關" % [i + 1, name])
		print("  第 %d 關「%s」：%d tick　核心 %.0f/%.0f　擊殺 %d　產能積分 %.2f（★★★ 門檻 %.2f）" % [
			i + 1, name, r["ticks"], r["core_hp"], r["core_max"],
			r["kills"], r["throughput"], lv["star_throughput"],
		])
		# ★ B1.2 DoD：第 1–2 關以「新手可通關」為硬性驗收。
		# 一個剛學會的人不會打出零失血的完美局，但他也不該是**險勝**：
		# 參考解在前兩關必須核心無損，那才是「餘裕」這個詞的可驗證形式。
		if i <= 1:
			t.eq(
				r["core_hp"], r["core_max"],
				"★ 第 %d 關「%s」參考解核心無損（新手餘裕）" % [i + 1, name]
			)


# ── 星等與存檔 ────────────────────────────────────────────────────────

func _stars(t: RefCounted) -> void:
	t.eq(Score.stars(false, 1000.0, 1000.0, 99.0, 1.0), 0, "沒通關就是 0 顆")
	t.eq(Score.stars(true, 1000.0, 1000.0, 0.0, 1.0), 2, "通關＋核心無損＝2 顆")
	t.eq(Score.stars(true, 999.0, 1000.0, 99.0, 1.0), 1, "核心掉一滴血就封頂 1 顆")
	t.eq(Score.stars(true, 1000.0, 1000.0, 1.0, 1.0), 3, "產能積分踩到門檻＝3 顆")
	# 「產能爆表但核心快沒了」拿三星，等於把這一關的第一課教反。
	t.eq(Score.stars(true, 1.0, 1000.0, 99.0, 1.0), 1, "產能再高也補不回破掉的核心")


func _save_progress(t: RefCounted) -> void:
	var d := SaveService.defaults()
	var gain := SaveService.apply_result(d, "tidemouth", 2, 30)
	t.near(gain, 60.0, "首通 2 星＝30 × 2")
	t.near(float((d["tech"] as Dictionary)["data"]), 60.0, "研究數據入帳")
	# sv2 起「通關」就是「星數 >= 1」，沒有另一份 cleared 清單（B1.4）。
	t.eq(int(((d["campaign"] as Dictionary)["stars"] as Dictionary)["tidemouth"]), 2, "通關紀錄＝星數")

	# 回頭補到 3 星：**只補差額**。
	var gain2 := SaveService.apply_result(d, "tidemouth", 3, 30)
	t.near(gain2, 30.0, "補到 3 星只補差額 30")
	t.near(float((d["tech"] as Dictionary)["data"]), 90.0, "研究數據累計 90")

	# 重刷同一星數：不再給。這是「賣速度不賣次數」（B6）在戰役側的樣子——
	# 沒有無限刷分的入口，也就沒有「刷不刷」這個假選擇。
	var gain3 := SaveService.apply_result(d, "tidemouth", 3, 30)
	t.near(gain3, 0.0, "重刷同星數不再給")

	# 重玩失敗：星數與通關紀錄都不得被抹掉（紅線 R1「失敗只花時間」）。
	SaveService.apply_result(d, "tidemouth", 0, 30)
	t.eq(int(((d["campaign"] as Dictionary)["stars"] as Dictionary)["tidemouth"]), 3, "失敗不扣星")
	t.ok(not (d["campaign"] as Dictionary).has("cleared"), "sv2 不再有 cleared 這個重複來源")

	# 存檔往返：normalize 之後戰役進度還在（只增不破）。
	var round_trip := SaveService.normalize(d)
	t.eq(
		((round_trip["campaign"] as Dictionary)["stars"] as Dictionary)["tidemouth"], 3,
		"normalize 往返後星數還在"
	)


# ── 解鎖閘門是規則，不只是畫面 ────────────────────────────────────────

## 鎖如果只做在 UI（不畫那顆鈕），藍圖展開（B2.3）與重播都會繞過它。
## 這裡直接呼叫規則層，確認第 1 關真的蓋不出稜鏡。
func _locked_is_a_rule(t: RefCounted) -> void:
	var lv: Dictionary = Campaign.at(0)
	var s: RefCounted = SessionState.new()
	s.setup(lv["map"], lv["unlocked"])
	s.ore = 9999.0
	var free_cell := Vector2i(8, 5)
	t.eq(
		BuildController.place(s, "prism", free_cell), Build.LOCKED,
		"第 1 關蓋不出稜鏡（規則層擋下，不是畫面擋下）"
	)
	t.eq(BuildController.place(s, "anchor", free_cell), Build.OK, "第 1 關蓋得出錨")
	# 測試圖與沙盤不受限：空的 unlocked ＝ 不限制。
	var open: RefCounted = SessionState.new()
	open.setup(Maps.SANDBOX)
	open.ore = 9999.0
	t.eq(
		BuildController.place(open, "prism", Vector2i(8, 8)), Build.OK,
		"沙盤不受解鎖限制（空陣列＝不限制）"
	)
