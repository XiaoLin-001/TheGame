extends Node
## 存檔（autoload）。規格：30_TECH_DESIGN.md §3。
##
## 三條承諾：
##   1. **只增不破**——新欄位給預設值，結構改動寫遷移分支。上線後破壞存檔＝事故。
##   2. **有測試鉤子時不落地**（§4.1 鐵律 1）——測試絕不寫壞使用者的真實存檔。
##   3. **原子寫入**——寫 .tmp → 讀回驗證 → 改名，避免半寫的檔案毀掉進度。
##
## 純邏輯（defaults／migrate／normalize）一律寫成 **static**，因為 `tests/*.gd`
## 以 `--script` 執行時不載入 autoload，只能 preload 這個檔案呼叫靜態函式（§4.2）。

const Score := preload("res://scripts/sim/Score.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Roster := preload("res://data/Roster.gd")

## sv2（B1.4）：`campaign.cleared` 移除，改由 `campaign.stars` 推導。
const SAVE_VERSION := 2

const PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"

## ★ 可選的視窗尺寸。**放在 schema 旁邊**：存檔存的是這個陣列的**索引**，
## 兩者不在同一個檔案的那一天，刪掉一個選項就會留下一個選不到也顯示不出來的值。
## 全部 16:9——版面基準是 1280×720，`stretch/aspect=expand` 在別的長寬比下
## 會讓框架與地圖的比例對不上。
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

## 完整 schema 骨架。**讀取一律走 normalize()**，任何缺失欄位都由此補上安全預設。
## ★ **只列真的有讀取端的欄位**（B1.9）。
##
## 這裡曾經有八個沒有任何人讀的頂層鍵（`company_level` `roster` `endless`
## `daily` `tycoon` `levels` `entitlements` `blueprints`），讓 schema 看起來
## 比實作大四倍。**提前宣告買不到任何相容性**：`_fill_defaults()` 本來就在
## 讀檔時補缺鍵，所以功能落地那一批直接加上那一個鍵，舊存檔照樣讀得進來。
##
## 反過來，提前宣告有真的代價：每一個空殼鍵都會被寫進玩家的存檔檔案，
## 而看到 `"tycoon": {...}` 的人會以為那個系統已經在跑了。
const DEFAULTS := {
	"sv": SAVE_VERSION,
	"tech": {"unlocked": [], "data": 0},
	# ★ sv2 起**沒有 `cleared`**：它和 `stars` 講的是同一件事（`stars[id] >= 1`），
	# 而同一個事實存兩份遲早會漂移——漂掉的那一天，玩家會看到「這一關通關了
	# 但下一關還鎖著」，而兩個欄位各自都「對」。
	"campaign": {"stars": {}},
	# ★ B2.1a 落地的鍵。**沒有 bump `SAVE_VERSION`**——上面那段註解說的就是
	# 這個情況：`_fill_defaults()` 在讀檔時補缺鍵，所以舊存檔讀進來自動長出
	# 這一格 0/0。遷移分支是給「結構改動」用的，加一個新鍵不是結構改動。
	"endless": {"best_wave": 0, "best_output": 0.0},
	# ★ B2.2 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（理由同上：加鍵不是結構改動）。
	# `date` ＝ `today` 那兩榜屬於哪一天；跨日時 `apply_daily()` 會把它推進 `history`。
	"daily": {
		"date": "",
		"today": {"uniform": {"wave": 0, "output": 0.0}, "free": {"wave": 0, "output": 0.0}},
		"history": [],
	},
	# `resolution` 是 `RESOLUTIONS` 的索引，不是像素——存像素的話，
	# 日後刪掉一個選項就會出現一個選不到、也顯示不出來的設定值。
	# ★ B2.3 落地的鍵。藍圖的座標是 `[dx, dy]` 整數陣列（`sim/Blueprint.gd`
	# 的說明）——**全部是 JSON 原生型別**，所以這一格存進去讀出來就是原樣，
	# 不需要任何序列化程式碼。
	"blueprints": [],
	# ★ B2.4 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# 只有 `recruited` 一格。「擁有哪些角色」與「還有幾張券」**都是推導出來的**
	# （`data/Roster.gd` 的說明）——存進來的每一份平行事實都會漂，而漂掉的那天
	# 玩家會看到「第 3 關通了但潮鳴還鎖著」，兩邊各自都「對」。
	"roster": {"recruited": []},
	"settings": {
		"master": 0.8, "bgm": 0.6, "sfx": 0.8,
		"reduce_motion": false, "fullscreen": false, "resolution": 0,
	},
}

## 有任何 TL_* 鉤子時為 false。直接由 Env 靜態判定，不依賴其他 autoload 的 _ready 順序。
var persist: bool = not Env.any_hook()


# ─────────────────────────────────────────────────────────────
# 純邏輯（static；測試直接呼叫，不需要 autoload）
# ─────────────────────────────────────────────────────────────

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## 把任意（可能殘缺、可能舊版）的資料整理成當前 schema 的完整資料。
## 順序很重要：先遷移舊結構，再補預設值——反過來會讓遷移看到假的預設欄位。
static func normalize(raw: Dictionary) -> Dictionary:
	var d := migrate(raw.duplicate(true))
	_fill_defaults(d, DEFAULTS)
	d["sv"] = SAVE_VERSION
	return d


## ★ 鏈式套用版本遷移（B1.4 起真的有分支了）。
##
## **一次跳一版，不寫「從任何版本直達最新」的捷徑**：捷徑要在每加一版時
## 重寫一次全部組合，而漏掉的那一格是玩家的存檔。
##
## 沒有 `sv` 的檔一律當成 1——那是首版出貨時的形狀，不是「壞檔」。
static func migrate(d: Dictionary) -> Dictionary:
	var sv := int(d.get("sv", 1))
	while sv < SAVE_VERSION:
		match sv:
			1: _migrate_sv1_to_sv2(d)
		sv += 1
	d["sv"] = SAVE_VERSION
	return d


## sv1 → sv2：`campaign.cleared` 併進 `campaign.stars`。
##
## 舊檔裡可能有「在 cleared 裡、但 stars 沒有記錄」的關（理論上不該發生，
## 但存檔遷移**不能假設舊資料是自洽的**）——那種一律補成 1 星，
## 因為 cleared 唯一的意思就是「至少通關過一次」。
static func _migrate_sv1_to_sv2(d: Dictionary) -> void:
	var campaign: Dictionary = d.get("campaign", {})
	if not campaign.has("cleared"):
		return
	var stars: Dictionary = campaign.get("stars", {})
	for id: Variant in campaign["cleared"]:
		stars[String(id)] = maxi(1, int(stars.get(String(id), 0)))
	campaign["stars"] = stars
	campaign.erase("cleared")


## ★ 把一局戰役的結果寫進存檔（B1.2、`10_GDD.md` §7.9）。**只增不減**：
## 星數取歷史最高、研究數據只補發差額、已通關的關卡不會因為重玩失敗而消失
## （紅線 R1「失敗只花時間」在存檔層的樣子）。
##
## 回傳實得的研究數據，讓局末結算面板有東西可講——
## 靜靜地寫進存檔而不告訴玩家，等於沒有獎勵。
static func apply_result(d: Dictionary, level_id: String, stars: int, reward: int) -> float:
	var campaign: Dictionary = d.get("campaign", {})
	var best: Dictionary = campaign.get("stars", {})
	if stars <= 0:
		return 0.0
	var gain := Score.reward_delta(reward, stars, int(best.get(level_id, 0)))
	best[level_id] = maxi(stars, int(best.get(level_id, 0)))
	var tech: Dictionary = d.get("tech", {})
	tech["data"] = float(tech.get("data", 0)) + gain
	return gain


## ★ 無盡的個人最佳（B2.1a、`10_GDD.md` §7.10）。**兩欄各自取最大值**。
##
## 刻意不是「波次高的那一局整組蓋過去」：波次與產能積分量的是兩件事
## （撐得久 vs 產線好），把它們綁成一組會讓一局「波次 +1、積分砍半」
## 洗掉玩家真正的最佳產線紀錄。回傳哪幾欄破了紀錄，讓局末面板講得出來。
static func apply_endless(d: Dictionary, wave: int, output: float) -> Dictionary:
	var e: Dictionary = d.get("endless", {})
	var new_wave := wave > int(e.get("best_wave", 0))
	var new_output := output > float(e.get("best_output", 0.0))
	if new_wave:
		e["best_wave"] = wave
	if new_output:
		e["best_output"] = output
	d["endless"] = e
	return {"wave": new_wave, "output": new_output}


## ★ 每日挑戰的成績（B2.2、`10_GDD.md` §3.10）。**兩欄各自取最大值**，
## 理由與 `apply_endless()` 完全相同（撐得久 vs 產線好是兩件事）。
##
## 跨日在這裡處理，不在畫面層：畫面層有兩個入口（兩張榜）而換日只該發生一次，
## 放在那裡就會出現「先點哪一榜決定昨天的紀錄有沒有被存進歷史」。
##
## ⚠ `today` 的兩榜**一起歸零**。只歸零玩的那一榜的話，昨天的另一榜會混進今天
## ——而它是在另一張圖上打出來的。
static func apply_daily(
	d: Dictionary, date: String, board: String, wave: int, output: float
) -> Dictionary:
	var day: Dictionary = d.get("daily", {})
	var today: Dictionary = day.get("today", {})
	if Daily.rolled_over(String(day.get("date", "")), date):
		var hist: Array = day.get("history", [])
		for b: String in Daily.BOARDS:
			var old: Dictionary = today.get(b, {})
			if int(old.get("wave", 0)) > 0:
				hist.push_front(Daily.entry(
					String(day["date"]), b, int(old["wave"]), float(old["output"])
				))
		while hist.size() > Daily.HISTORY_MAX:
			hist.pop_back()
		day["history"] = hist
		today = {}
	for b: String in Daily.BOARDS:
		if not today.has(b):
			today[b] = {"wave": 0, "output": 0.0}
	day["date"] = date
	var slot: Dictionary = today[board]
	var new_wave := wave > int(slot.get("wave", 0))
	var new_output := output > float(slot.get("output", 0.0))
	if new_wave:
		slot["wave"] = wave
	if new_output:
		slot["output"] = output
	day["today"] = today
	d["daily"] = day
	return {"wave": new_wave, "output": new_output}


## ★ 存一張藍圖（B2.3、`10_GDD.md` §3.7）。回傳空字串＝成功，否則是給玩家看的話。
##
## 槽數在這裡把關而不是在畫面層：畫面之後可能有第二個入口（例如局末結算
## 直接存這一局的佈局），而「槽滿了」這條規則只該有一份。
static func add_blueprint(d: Dictionary, bp: Dictionary, slot_count: int) -> String:
	if Blueprint.is_empty(bp):
		return "✕ 框選範圍內沒有可存的節點"
	var list: Array = d.get("blueprints", [])
	if list.size() >= slot_count:
		return "✕ 藍圖槽已滿（%d／%d）——先刪一張，或解鎖後勤科技" % [list.size(), slot_count]
	var copy: Dictionary = bp.duplicate(true)
	if String(copy.get("name", "")) == "":
		# 自動命名用**尺寸與節點數**，不是流水號：三個月後回來看「藍圖 3」
		# 想不起來是什麼，「4×3・7 節點」至少認得出是哪一種產線。
		var sp := Blueprint.span(copy)
		copy["name"] = "%d×%d・%d 節點" % [sp.x, sp.y, (copy["nodes"] as Array).size()]
	list.append(copy)
	d["blueprints"] = list
	return ""


## ★ 招募一隻（B2.4、`10_GDD.md` §3.9）。回傳招到的角色，空字串＝沒招成。
##
## 規則判定回頭問 `Roster`（畫面上的鈕是狀態不是規則，`Tech._unlock()` 同一條）：
## 券不夠、或已經畢業，就一張券都不扣。**畢業之後不再消耗券**是 §3.9 明文——
## 抽到重複的、或抽了個空還扣錢，都是這一條要擋的。
static func apply_recruit(d: Dictionary, rng: RandomNumberGenerator) -> String:
	if Roster.graduated(d) or Roster.tokens(d) <= 0:
		return ""
	var got := Roster.pull(d, rng)
	if got == "":
		return ""
	var r: Dictionary = d.get("roster", {})
	var list: Array = r.get("recruited", [])
	list.append(got)
	r["recruited"] = list
	d["roster"] = r
	return got


## 遞迴補預設值：defaults 有而 target 沒有的鍵才補；兩邊都是 Dictionary 就往下走。
## **不覆蓋已存在的值**——玩家的資料永遠優先。
static func _fill_defaults(target: Dictionary, defs: Dictionary) -> void:
	for k: String in defs.keys():
		var dv: Variant = defs[k]
		if not target.has(k):
			target[k] = dv.duplicate(true) if dv is Dictionary or dv is Array else dv
		elif dv is Dictionary and target[k] is Dictionary:
			_fill_defaults(target[k], dv)


# ─────────────────────────────────────────────────────────────
# 落地（instance；需要檔案系統）
# ─────────────────────────────────────────────────────────────

## 讀檔並**原地**填入 target，維持所有既有引用有效（§2.3）。
##
## ★ **有測試鉤子時連「讀」都不讀真存檔**（B1.2.2）。原本只擋寫入，於是
## 任何 `TL_*` 跑出來的畫面都會跟著這台機器上玩家的進度變——`TL_SHOT`
## 「同參數在任何機器上拍出同一張圖」那句保證，在關卡選擇畫面上是假的
## （已通關幾關就長不一樣），而 `TL_CLICKTEST` 對「第 2 關是鎖著的」
## 這種斷言會在玩過的機器上無故變紅。鉤子在兩個方向上都該是空操作。
func load_into(target: Dictionary) -> void:
	var loaded := normalize({} if not persist else _read_raw())
	target.clear()
	target.merge(loaded, true)


func save_from(source: Dictionary) -> bool:
	if not persist:
		print("[TL] save skipped（有測試鉤子）")
		return true
	return _write_atomic(normalize(source))


func _read_raw() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("存檔開啟失敗 err=%d，改用預設值" % FileAccess.get_open_error())
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("存檔內容不是合法 JSON 物件，改用預設值")
	return {}


## 寫 .tmp → 讀回驗證 → 換掉主檔。中途失敗時主檔完好如初。
func _write_atomic(d: Dictionary) -> bool:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("暫存檔寫入失敗 err=%d" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

	# 驗證：讀不回來就不要動主檔。
	var check := FileAccess.open(TMP_PATH, FileAccess.READ)
	if check == null or not (JSON.parse_string(check.get_as_text()) is Dictionary):
		if check != null:
			check.close()
		push_error("暫存檔驗證失敗，保留原存檔不動")
		return false
	check.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("user:// 開啟失敗")
		return false
	if dir.file_exists("save.json"):
		dir.remove("save.json")
	var err := dir.rename("save.json.tmp", "save.json")
	if err != OK:
		push_error("存檔改名失敗 err=%d" % err)
		return false
	return true
