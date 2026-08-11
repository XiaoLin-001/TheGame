extends SceneTree
## 存檔的純邏輯測試（30_TECH_DESIGN.md §3、50_QA_PLAN.md §2）。
##
## 只測 static 的部分（defaults／migrate／normalize）——落地那半需要檔案系統
## 與 autoload，不在 `--script` 模式的能力範圍內；它由 L4 冒煙遊玩涵蓋。
##
## 跑法：<godot> --headless --path godot --script res://tests/save_test.gd

const T := preload("res://tests/_assert.gd")
const Save := preload("res://scripts/core/SaveService.gd")
const Difficulty := preload("res://data/Difficulty.gd")


func _initialize() -> void:
	var t := T.new("save_test", 98)

	# ── 空存檔 → 補完整 schema ──
	var fresh: Dictionary = Save.normalize({})
	t.eq(fresh.get("sv"), Save.SAVE_VERSION, "空存檔補上當前 sv")
	for key: String in Save.DEFAULTS.keys():
		t.ok(fresh.has(key), "空存檔補上頂層區段 %s" % key)
	t.eq(fresh["tech"]["data"], 0, "巢狀預設值有補到（tech.data）")
	t.eq(fresh["settings"]["reduce_motion"], false, "巢狀預設值有補到（settings.reduce_motion）")

	# ── 玩家資料永遠優先，預設值只補不覆蓋 ──
	# 這是「只增不破」承諾的核心：新版本加欄位，不能動到玩家既有的值。
	var partial := {"tech": {"data": 7}, "settings": {"master": 0.25}}
	var merged: Dictionary = Save.normalize(partial)
	t.eq(merged["tech"]["data"], 7, "既有值不被預設值覆蓋")
	t.eq(merged["settings"]["master"], 0.25, "既有巢狀值不被預設值覆蓋")
	t.eq(merged["settings"]["bgm"], 0.6, "同一區段內缺的鍵仍補上預設")

	# ★ 認不得的區段要原樣留著（B1.9）。這一條就是「B1.9 砍掉八個空殼鍵是安全的」
	#   的證明：**用舊版玩過、存檔裡已經有 `tycoon` 之類欄位的玩家，讀進來不會掉東西**
	#   ——`normalize()` 只補不刪。降級或跨版本開檔也走同一條保證。
	var legacy: Dictionary = Save.normalize({"tycoon": {"credit": 3456}, "blueprints": [1]})
	t.eq(legacy["tycoon"]["credit"], 3456, "★ 認不得的區段原樣保留（只補不刪）")
	t.eq(legacy["blueprints"], [1], "★ 認不得的陣列原樣保留")

	# ── 殘缺／損壞的輸入不得炸掉 ──
	var junk := {"sv": 1, "campaign": {}, "tech": {"unlocked": ["cap1"]}}
	var fixed: Dictionary = Save.normalize(junk)
	t.eq(fixed["campaign"]["stars"], {}, "空區段補回內部預設")
	t.eq(fixed["tech"]["unlocked"], ["cap1"], "既有陣列原樣保留")
	t.eq(fixed["tech"]["data"], 0, "陣列旁缺的鍵仍補上")

	# ── normalize 不得改動輸入（純函式） ──
	var src := {"tech": {"data": 3}}
	Save.normalize(src)
	t.eq(src.size(), 1, "normalize 不修改傳入的字典")

	# ── 預設值本身是深複製，兩次取得互不干擾 ──
	var a: Dictionary = Save.defaults()
	a["tech"]["data"] = 99
	var b: Dictionary = Save.defaults()
	t.eq(b["tech"]["data"], 0, "defaults() 回傳深複製，不會被上一份污染")

	# ── 磁碟往返：原子寫入 → 讀回 → 一致 ──
	_disk_round_trip(t)

	_migration_sv1_to_sv2(t)
	_hostile_saves(t)

	quit(t.report())


## ★ sv1 → sv2（B1.4）：`campaign.cleared` 併進 `campaign.stars`。
##
## 這是本專案第一個真的遷移分支，所以它同時也是**遷移機制本身**的覆蓋：
## 一次跳一版、沒有 `sv` 的檔當成 1、遷移過的檔再跑一次不得二次變形。
func _migration_sv1_to_sv2(t: RefCounted) -> void:
	# ① 典型的 sv1 存檔：三關通關，其中兩關有星數。
	var old := {
		"sv": 1,
		"campaign": {"cleared": ["tidemouth", "twinbay", "narrows"], "stars": {
			"tidemouth": 3, "twinbay": 2,
		}},
	}
	var up: Dictionary = Save.normalize(old)
	var stars: Dictionary = (up["campaign"] as Dictionary)["stars"]
	# ★ 對的是 `SAVE_VERSION` 不是寫死的 2（B2.6 加 sv3 時這兩條紅了）：
	#   這兩條要問的是「遷移鏈跑得完」，而不是「最新版恰好是第 2 版」。
	t.eq(up["sv"], Save.SAVE_VERSION, "遷移後 sv 是最新版")
	t.ok(not (up["campaign"] as Dictionary).has("cleared"), "cleared 已移除")
	t.eq(int(stars["tidemouth"]), 3, "既有星數不被遷移壓低")
	t.eq(int(stars["twinbay"]), 2, "既有星數原樣保留")
	# ★ 「在 cleared 裡但 stars 沒記錄」補成 1 星。**遷移不能假設舊資料自洽**——
	#   真實存檔會有中途版本、有當機、有手改過的檔。
	t.eq(int(stars["narrows"]), 1, "只在 cleared 裡的關補成 1 星（不假設舊資料自洽）")

	# ② 沒有 `sv` 的檔＝首版出貨的形狀，不是壞檔。
	var no_sv: Dictionary = Save.normalize({"campaign": {"cleared": ["tidemouth"]}})
	t.eq(no_sv["sv"], Save.SAVE_VERSION, "沒有 sv 的舊檔一樣跑得完遷移鏈")
	t.eq(
		int(((no_sv["campaign"] as Dictionary)["stars"] as Dictionary)["tidemouth"]), 1,
		"沒有 sv 的舊檔也補得到星數"
	)

	# ③ **冪等**：已經是 sv2 的檔再 normalize 一次不得再變形。
	#    遷移最常見的事故就是「開遊戲兩次跑了兩次遷移」。
	var again: Dictionary = Save.normalize(up)
	t.eq(again["campaign"], up["campaign"], "已遷移的檔再跑一次不變（冪等）")

	# ④ 新存檔不受影響。
	var fresh2: Dictionary = Save.normalize({})
	t.eq((fresh2["campaign"] as Dictionary)["stars"], {}, "全新存檔：沒有任何星數")
	t.ok(not (fresh2["campaign"] as Dictionary).has("cleared"), "全新存檔不會長出 cleared")


## 實際寫檔／讀檔。這段是「只增不破」承諾與原子寫入唯一的自動化覆蓋。
##
## ★ B2.8 起**一定會跑**（RG-160）。原本的規則是「偵測到既有存檔就整段跳過，
## 免得碰壞使用者的進度」——立意是對的，結果是這條路徑**在任何玩過遊戲的機器上
## 都沒有被執行過**，也就是我的機器與使用者的機器。它從 B0.1 起一直印著「待補」，
## 而一條永遠待補的測試與沒有這條測試沒有差別。
##
## 現在改成寫**測試自己的檔名**（`SaveService.path` 是實例欄位，預設仍是玩家那一個）：
## 真實存檔一個位元組都不會被碰到，而原子寫入、改名、讀回三段真的跑得到。
func _disk_round_trip(t: RefCounted) -> void:
	var svc: Node = Save.new()
	svc.path = "user://save_roundtrip_test.json"
	svc.tmp_path = "user://save_roundtrip_test.json.tmp"
	# `persist` 由 Env 判定；這支測試沒有鉤子，但**明寫**比較不會在日後被改壞。
	svc.persist = true

	var written := {"campaign": {"stars": {"shoal": 3}}, "tech": {"data": 12}}
	t.ok(svc.save_from(written), "save_from 回報成功")
	t.ok(FileAccess.file_exists(svc.path), "主存檔已建立")
	t.ok(not FileAccess.file_exists(svc.tmp_path), "暫存檔已被改名，未留下殘骸")

	var back := {}
	svc.load_into(back)
	t.eq(back["tech"]["data"], 12, "讀回巢狀值一致")
	t.eq(back["campaign"]["stars"]["shoal"], 3, "讀回巢狀字典一致")
	t.eq(back["tech"]["unlocked"], [], "寫入時未提供的鍵讀回時已補預設")
	t.eq(back["sv"], Save.SAVE_VERSION, "讀回的 sv 為當前版本")

	# ★ 寫進去的真的是 JSON，而且讀得回同一份（不是只有 `load_into` 認得的格式）。
	var raw := FileAccess.open(svc.path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(raw.get_as_text())
	raw.close()
	t.ok(parsed is Dictionary, "檔案內容是合法 JSON 物件")

	# ★ 半寫壞的檔：讀不出 JSON 就退回預設值，**不得當掉、也不得沿用上一份**。
	var broken := FileAccess.open(svc.path, FileAccess.WRITE)
	broken.store_string('{"campaign": {"stars": {"shoal": 3')
	broken.close()
	var salvaged := {}
	svc.load_into(salvaged)
	t.eq(salvaged["sv"], Save.SAVE_VERSION, "★ 讀到半寫壞的檔仍然拿得到一份完整的資料")
	t.eq((salvaged["campaign"] as Dictionary)["stars"], {}, "★ 壞檔退回預設值，不是半份進度")

	# 真實存檔沒被碰到（這條就是上面那段註解的保證）。
	t.ok(svc.path != Save.PATH, "★ 全程寫的是測試自己的檔名，玩家的存檔沒有被開啟過")

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(svc.path.get_file())
		dir.remove(svc.tmp_path.get_file())
	t.ok(not FileAccess.file_exists(svc.path), "測試結束後未留下檔案")
	svc.free()


## ★ 惡意／壞掉的存檔（B2.8 L5 找碴、RG-159）。
##
## 這一段找到的是一個真的缺陷：`_fill_defaults()` 只補**缺的鍵**，不修**型別錯的鍵**，
## 於是一個 `"campaign": 5` 的檔會讓整個局外層噴 14 條型別錯誤（成就、名冊、
## 材料餘額、難度層解鎖全部中招）。修法是在遷移之前多一步 `_repair_containers()`。
func _hostile_saves(t: RefCounted) -> void:
	var cases := {
		"型別全錯": {"sv": 2, "campaign": 5, "tech": "hello", "endless": [1, 2], "levels": 7},
		"陣列當字典": {"sv": 2, "campaign": {"stars": [1, 2, 3]}},
		"字典當純量": {"sv": 2, "settings": {"master": {"a": 1}}},
		"sv 是字串": {"sv": "abc", "tech": {"data": 5}},
		# ★ B3.2 補的那一格：**遷移分支讀的舊鍵型別壞掉**。
		#   `_repair_containers()` 只走 `DEFAULTS` 的鍵，而 `best_wave` 在 sv3
		#   已經被砍掉——它蓋不到。`int({})` 於是丟「Nonexistent 'int' constructor」，
		#   而執行期錯誤**中止 `_migrate_sv2_to_sv3()`**（RG-164 的同一條）：
		#   `erase()` 沒跑到，`migrate()` 卻照樣把 `sv` 蓋成 3
		#   ——存檔永久停在「標記成已遷移、實際上沒遷移完」，下次開機不會再試。
		"遷移讀的舊鍵型別壞掉": {"sv": 2, "endless": {"best_wave": {}, "best_output": []}},
	}
	for name: String in cases:
		var d: Dictionary = Save.normalize(cases[name] as Dictionary)
		t.ok(d["campaign"] is Dictionary, "%s：campaign 修回字典" % name)
		t.ok((d["campaign"] as Dictionary)["stars"] is Dictionary, "%s：stars 修回字典" % name)
		t.ok(d["endless"] is Dictionary, "%s：endless 修回字典" % name)
		t.ok(d["levels"] is Dictionary, "%s：levels 修回字典" % name)
		t.ok(d["tech"] is Dictionary, "%s：tech 修回字典" % name)
		t.ok(d["blueprints"] is Array, "%s：blueprints 修回陣列" % name)
		t.eq(d["sv"], Save.SAVE_VERSION, "%s：仍然跑得完遷移鏈" % name)
		# 局外層的每一支查詢都問得出一個數字（這才是「不會炸」的可觀察形式）。
		t.ok(Save.components(d) >= 0, "%s：材料餘額算得出來" % name)
		t.ok(Difficulty.unlocked(d) >= 0, "%s：難度層解鎖算得出來" % name)

	# ★ 遷移**真的跑完了**，不是「中途炸掉但 sv 被蓋成 3」。
	#   `sv == 3` 證不了這件事（`migrate()` 在 while 之後無條件蓋 sv），
	#   要問的是遷移那一步該做的事有沒有留下痕跡——舊鍵有沒有被 `erase()` 掉。
	var aborted := Save.normalize({"sv": 2, "endless": {"best_wave": {}, "best_output": []}})
	var e_after: Dictionary = aborted["endless"]
	t.ok(not e_after.has("best_wave"), "★ 遷移跑完：型別壞掉的 best_wave 仍然被清掉")
	t.ok(not e_after.has("best_output"), "★ 遷移跑完：型別壞掉的 best_output 仍然被清掉")
	t.ok(e_after["best"] is Dictionary, "★ 遷移跑完：best 是字典")
	t.ok((e_after["best"] as Dictionary).is_empty(), "★ 壞資料不編造紀錄（0 波不建那一格）")
	# 而**正常的 sv2 檔照樣搬得過來**（上面那條不得是「把遷移整段跳過」換來的）。
	var good := Save.normalize({"sv": 2, "endless": {"best_wave": 7, "best_output": 3.5}})
	var row: Dictionary = ((good["endless"] as Dictionary)["best"] as Dictionary)["0"]
	t.eq(int(row["wave"]), 7, "★ 反向對照：正常 sv2 的紀錄搬進第 0 層")
	t.eq(float(row["output"]), 3.5, "★ 反向對照：產能積分一起搬")

	# ★ 反向對照：**純量之間的型別差異不得被當成壞資料清掉**。
	#   JSON 沒有整數——`"data": 12` 讀回來是 12.0，嚴格比對型別會把它歸零。
	var jsonish := Save.normalize({"sv": 3, "tech": {"data": 12.0, "unlocked": ["cap1"]}})
	t.eq(int((jsonish["tech"] as Dictionary)["data"]), 12, "★ 反向對照：float 的研究數據沒有被清掉")
	t.eq((jsonish["tech"] as Dictionary)["unlocked"], ["cap1"], "★ 反向對照：既有陣列原樣保留")
