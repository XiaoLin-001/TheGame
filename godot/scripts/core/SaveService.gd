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


## sv2（B1.4）：`campaign.cleared` 移除，改由 `campaign.stars` 推導。
## sv3（B2.6）：`endless.best_wave`／`best_output` 收進 `endless.best`（逐難度層一筆）。
const SAVE_VERSION := 3

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
	# ★ B2.1a 落地、B2.6 改結構（sv3）。`best` 的鍵是**難度層的字串**（"0".."3"），
	# 值是 `{wave, output}`。改結構而不是在旁邊加一格「高難度的紀錄」：
	# 同一個「12 波」在標準層與深潮層不是同一件事，共用一格會讓其中一個
	# 永遠洗不掉另一個（而玩家兩邊都覺得自己那筆才對）。
	#
	# 鍵是字串不是整數：這一格要進 JSON，而 JSON 的物件鍵本來就只有字串
	# ——存成整數的話，寫進去是 3、讀回來是 "3"，查表當場落空。
	"endless": {"best": {}},
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
	# ★ B2.5 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# `orders` 的每一筆是 `{tier, done, line}`，`line` ＝ 第幾格產線位（−1 ＝ 沒上線）。
	# **「哪一格產線位被佔著」是推導的**（`TycoonSim.order_on_line()`）——存一份
	# slots 陣列等於讓同一個事實有兩個版本，而收成一張訂單會讓後面每個索引位移。
	#
	# `last_seen` ＝ Unix 秒，離線結算的基準（`TycoonSim.settle()`）。
	# 0 ＝ 從沒開過公司，**不結算**（否則會把 1970 年到現在整段算進去）。
	"tycoon": {
		"level": 1, "credits": 0, "components": 0, "tokens": 0,
		"last_seen": 0, "orders": [],
	},
	# ★ B2.7 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# 只有三格，而且**沒有一格是「我還剩多少材料」**：餘額是推導的
	# （`components()`）。存餘額的話，等級與材料會變成兩個各自可以「對」的事實，
	# 而漂掉的那天玩家看到的是「我 10 級但材料只花了三級的錢」。
	# `from_battle` ＝ 局末結算的**累計**（只增），`tower`／`line` 反推花掉多少。
	"levels": {"tower": 0, "line": 0, "from_battle": 0},
	"settings": {
		"master": 0.8, "bgm": 0.6, "sfx": 0.8,
		"reduce_motion": false, "fullscreen": false, "resolution": 0,
	},
}

## 有任何 TL_* 鉤子時為 false。直接由 Env 靜態判定，不依賴其他 autoload 的 _ready 順序。
var persist: bool = not Env.any_hook()

## ★ 這個實例讀寫哪一個檔（B2.8）。預設就是上面那兩個常數，**玩家的路徑一個字都沒變**。
##
## 為什麼要能換：磁碟往返（原子寫入 → 讀回 → 改名）是「只增不破」唯一的自動化覆蓋，
## 而它原本**在任何已經有存檔的機器上整段跳過**——也就是我的機器與使用者的機器。
## 那條測試從 B0.1 起就一直印著「待補」，等於這條路徑從來沒有被真的跑過（RG-160）。
var path: String = PATH
var tmp_path: String = TMP_PATH


# ─────────────────────────────────────────────────────────────
# 純邏輯（static；測試直接呼叫，不需要 autoload）
# ─────────────────────────────────────────────────────────────

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## 把任意（可能殘缺、可能舊版）的資料整理成當前 schema 的完整資料。
## 順序很重要：先遷移舊結構，再補預設值——反過來會讓遷移看到假的預設欄位。
##
## ★ B2.8 在**遷移之前**多一步 `_repair_containers()`（RG-159）。順序仍然是
## 「修型別 → 遷移 → 補預設」：`_fill_defaults()` 只補**缺的鍵**，它不會修一個
## 型別錯掉的鍵，而遷移分支與所有讀取端都假設 `campaign` 是字典、`endless` 是字典。
## 一個 `"campaign": 5` 的檔於是會在整個局外層噴一整串型別錯誤（實測 14 條）。
static func normalize(raw: Dictionary) -> Dictionary:
	var d := raw.duplicate(true)
	_repair_containers(d, DEFAULTS)
	d = migrate(d)
	_fill_defaults(d, DEFAULTS)
	d["sv"] = SAVE_VERSION
	return d


## ★ 型別修復（B2.8、RG-159）。**只修容器與非容器不合的那些鍵，不補任何缺鍵。**
##
## 為什麼只看「是不是容器」而不是嚴格比對型別：**JSON 沒有整數**。
## `"data": 12` 存進去讀出來是 `12.0`，嚴格比對會把玩家的研究數據當成壞資料清掉。
## 純量之間的差異由讀取端既有的 `int()`／`float()` 轉換吸收，那條路本來就通；
## 真正會炸的是「該是字典的地方放著一個數字」——那種值沒有任何轉換救得回來。
##
## 補缺鍵留給 `_fill_defaults()`（它在遷移之後跑）：在這裡補的話，遷移分支會看到
## 一堆它那個版本還不存在的欄位，那正是 `normalize()` 的順序註解在講的事。
##
## ⚠ **它蓋不到「已經被砍掉的鍵」**——它只走 `DEFAULTS` 的鍵，而遷移分支讀的
## 恰恰是那些不在 `DEFAULTS` 裡的舊鍵。那條縫由 `_scalar()` 補（見下）。
static func _repair_containers(target: Dictionary, defs: Dictionary) -> void:
	for k: String in defs.keys():
		if not target.has(k):
			continue
		var dv: Variant = defs[k]
		var tv: Variant = target[k]
		if dv is Dictionary:
			if tv is Dictionary:
				_repair_containers(tv, dv)
			else:
				target[k] = (dv as Dictionary).duplicate(true)
		elif dv is Array:
			if not (tv is Array):
				target[k] = (dv as Array).duplicate(true)
		elif tv is Dictionary or tv is Array:
			target[k] = dv


## ★ 讀一個**舊版才有的**數值鍵（B3.2 補；RG-159 沒蓋到的那道縫）。
##
## 遷移分支讀的是已經從 `DEFAULTS` 砍掉的鍵，所以 `_repair_containers()`
## 走不到它們——一個手改成 `"best_wave": {}` 的檔會讓 `int()` 當場丟
## 「Nonexistent 'int' constructor」。而 GDScript 的執行期錯誤**中止那一支函式**
## （RG-164 的同一條）：`erase()` 沒跑到、`sv` 卻還是被 `migrate()` 蓋成新版
## ——存檔於是永久停在「標記成已遷移、實際上沒遷移完」。
##
## 只有遷移分支需要它。當期的鍵一律由 `_repair_containers()` 保證型別。
static func _scalar(v: Variant) -> float:
	var t := typeof(v)
	return float(v) if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL else 0.0


## ★ 鏈式套用版本遷移（B1.4 起真的有分支了）。
##
## **一次跳一版，不寫「從任何版本直達最新」的捷徑**：捷徑要在每加一版時
## 重寫一次全部組合，而漏掉的那一格是玩家的存檔。
##
## 沒有 `sv` 的檔一律當成 1——那是首版出貨時的形狀，不是「壞檔」。
static func migrate(d: Dictionary) -> Dictionary:
	var sv := int(d.get("sv", 1))
	# ★ 比自己新的檔**原樣放過，版號不動**（B3.10）。原本迴圈不跑、下面那行卻
	#   無條件把 `sv` 蓋成 `SAVE_VERSION`：玩家升級之後又開了一次留在硬碟上的
	#   舊 exe，sv4 的資料會被蓋上 sv3 存回去，於是新版下次啟動時對一份**已經
	#   遷移過**的資料再跑一次 `_migrate_sv3_to_sv4()`。降級一律是不讀不寫，
	#   而不是「假裝它是舊檔」——後者會把玩家的進度改壞。
	if sv > SAVE_VERSION:
		return d
	while sv < SAVE_VERSION:
		match sv:
			1: _migrate_sv1_to_sv2(d)
			2: _migrate_sv2_to_sv3(d)
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


## sv2 → sv3：無盡的個人最佳收進 `endless.best`，鍵是難度層（B2.6、§7.16）。
##
## 舊檔的那一筆**一律記在第 0 層**——它是在還沒有難度層的世界裡打出來的，
## 而第 0 層就是那個世界的規則。丟掉它會讓玩家開遊戲第一件事是看到紀錄歸零。
##
## 兩欄都是 0 就不建那一格：一個 `{"0": {"wave": 0, "output": 0.0}}` 會讓
## 「從沒玩過無盡」看起來像「打過但 0 波」。
static func _migrate_sv2_to_sv3(d: Dictionary) -> void:
	var e: Dictionary = d.get("endless", {})
	if not e.has("best_wave") and not e.has("best_output"):
		return
	var wave := int(_scalar(e.get("best_wave")))
	var output := _scalar(e.get("best_output"))
	e.erase("best_wave")
	e.erase("best_output")
	if wave > 0 or output > 0.0:
		var best: Dictionary = e.get("best", {})
		best["0"] = {"wave": wave, "output": output}
		e["best"] = best
	d["endless"] = e


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
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
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
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("暫存檔寫入失敗 err=%d" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

	# 驗證：讀不回來就不要動主檔。
	var check := FileAccess.open(tmp_path, FileAccess.READ)
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
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	var err := dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("存檔改名失敗 err=%d" % err)
		return false
	return true
