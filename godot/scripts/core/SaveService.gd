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
const DEFAULTS := {
	"sv": SAVE_VERSION,
	"company_level": 1,
	"tech": {"unlocked": [], "data": 0},
	"roster": {"owned": [], "tokens": 0},
	# ★ sv2 起**沒有 `cleared`**：它和 `stars` 講的是同一件事（`stars[id] >= 1`），
	# 而同一個事實存兩份遲早會漂移——漂掉的那一天，玩家會看到「這一關通關了
	# 但下一關還鎖著」，而兩個欄位各自都「對」。
	"campaign": {"stars": {}},
	"endless": {"best_wave": 0, "best_score": 0},
	# 每日兩榜：{"<日期>": {"unified": {...}, "free": {...}}}（§3）
	"daily": {},
	"tycoon": {"level": 1, "credit": 0, "components": 0, "lines": [], "last_seen_unix": 0},
	"levels": {"towers": {}, "nodes": {}},
	"entitlements": {"purchases": [], "no_ads": false, "pass_season": 0, "pass_owned": false},
	"blueprints": [],
	# `resolution` 是 `screens/Settings.gd` 的 `RESOLUTIONS` 索引，不是像素——
	# 存像素的話，日後刪掉一個選項就會出現一個選不到、也顯示不出來的設定值。
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
