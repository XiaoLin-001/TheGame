extends SceneTree
## 存檔的純邏輯測試（30_TECH_DESIGN.md §3、50_QA_PLAN.md §2）。
##
## 只測 static 的部分（defaults／migrate／normalize）——落地那半需要檔案系統
## 與 autoload，不在 `--script` 模式的能力範圍內；它由 L4 冒煙遊玩涵蓋。
##
## 跑法：<godot> --headless --path godot --script res://tests/save_test.gd

const T := preload("res://tests/_assert.gd")
const Save := preload("res://scripts/core/SaveService.gd")


func _initialize() -> void:
	var t := T.new("save_test")

	# ── 空存檔 → 補完整 schema ──
	var fresh: Dictionary = Save.normalize({})
	t.eq(fresh.get("sv"), Save.SAVE_VERSION, "空存檔補上當前 sv")
	for key: String in Save.DEFAULTS.keys():
		t.ok(fresh.has(key), "空存檔補上頂層區段 %s" % key)
	t.eq(fresh["tycoon"]["level"], 1, "巢狀預設值有補到（tycoon.level）")
	t.eq(fresh["settings"]["reduce_motion"], false, "巢狀預設值有補到（settings.reduce_motion）")

	# ── 玩家資料永遠優先，預設值只補不覆蓋 ──
	# 這是「只增不破」承諾的核心：新版本加欄位，不能動到玩家既有的值。
	var partial := {"company_level": 7, "settings": {"master": 0.25}}
	var merged: Dictionary = Save.normalize(partial)
	t.eq(merged["company_level"], 7, "既有頂層值不被預設值覆蓋")
	t.eq(merged["settings"]["master"], 0.25, "既有巢狀值不被預設值覆蓋")
	t.eq(merged["settings"]["bgm"], 0.6, "同一區段內缺的鍵仍補上預設")

	# ── 殘缺／損壞的輸入不得炸掉 ──
	var junk := {"sv": 1, "tech": {}, "roster": {"owned": ["anchor"]}}
	var fixed: Dictionary = Save.normalize(junk)
	t.eq(fixed["tech"]["data"], 0, "空區段補回內部預設")
	t.eq(fixed["roster"]["owned"], ["anchor"], "既有陣列原樣保留")
	t.eq(fixed["roster"]["tokens"], 0, "陣列旁缺的鍵仍補上")

	# ── normalize 不得改動輸入（純函式） ──
	var src := {"company_level": 3}
	Save.normalize(src)
	t.eq(src.size(), 1, "normalize 不修改傳入的字典")

	# ── 預設值本身是深複製，兩次取得互不干擾 ──
	var a: Dictionary = Save.defaults()
	a["tycoon"]["level"] = 99
	var b: Dictionary = Save.defaults()
	t.eq(b["tycoon"]["level"], 1, "defaults() 回傳深複製，不會被上一份污染")

	# ── 磁碟往返：原子寫入 → 讀回 → 一致 ──
	_disk_round_trip(t)

	t.pending("sv1→sv2 遷移分支（目前只有首版，尚無可測的遷移）", "首次結構改動時")

	quit(t.report())


## 實際寫檔／讀檔。這段是「只增不破」承諾與原子寫入唯一的自動化覆蓋。
##
## 安全規則：**存檔已存在就整段跳過**——測試絕不碰使用者的真實進度。
## 這與鐵律 1（有鉤子時 persist=false）互補：鐵律擋的是有鉤子的情況，
## 這條擋的是「沒有鉤子、直接跑測試」的情況。
func _disk_round_trip(t: RefCounted) -> void:
	var svc: Node = Save.new()

	if FileAccess.file_exists(Save.PATH):
		t.pending("磁碟往返（偵測到既有存檔，為保護使用者進度而跳過）", "—")
		svc.free()
		return
	if not svc.persist:
		t.pending("磁碟往返（persist=false，有測試鉤子啟用）", "—")
		svc.free()
		return

	var written := {"company_level": 12, "tycoon": {"credit": 3456}}
	t.ok(svc.save_from(written), "save_from 回報成功")
	t.ok(FileAccess.file_exists(Save.PATH), "主存檔已建立")
	t.ok(not FileAccess.file_exists(Save.TMP_PATH), "暫存檔已被改名，未留下殘骸")

	var back := {}
	svc.load_into(back)
	t.eq(back["company_level"], 12, "讀回頂層值一致")
	t.eq(back["tycoon"]["credit"], 3456, "讀回巢狀值一致")
	t.eq(back["tycoon"]["level"], 1, "寫入時未提供的鍵讀回時已補預設")
	t.eq(back["sv"], Save.SAVE_VERSION, "讀回的 sv 為當前版本")

	# 清乾淨：測試不留下假存檔，否則使用者首次啟動會拿到 company_level=12。
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("save.json")
	t.ok(not FileAccess.file_exists(Save.PATH), "測試結束後未留下存檔")
	svc.free()
