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

const SAVE_VERSION := 1

const PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"

## 完整 schema 骨架。**讀取一律走 normalize()**，任何缺失欄位都由此補上安全預設。
const DEFAULTS := {
	"sv": SAVE_VERSION,
	"company_level": 1,
	"tech": {"unlocked": [], "data": 0},
	"roster": {"owned": [], "tokens": 0},
	"campaign": {"cleared": [], "stars": {}},
	"endless": {"best_wave": 0, "best_score": 0},
	# 每日兩榜：{"<日期>": {"unified": {...}, "free": {...}}}（§3）
	"daily": {},
	"tycoon": {"level": 1, "credit": 0, "components": 0, "lines": [], "last_seen_unix": 0},
	"levels": {"towers": {}, "nodes": {}},
	"entitlements": {"purchases": [], "no_ads": false, "pass_season": 0, "pass_owned": false},
	"blueprints": [],
	"settings": {"master": 0.8, "bgm": 0.6, "sfx": 0.8, "reduce_motion": false},
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


## 鏈式套用版本遷移。目前 sv=1 為首版，尚無遷移分支。
## 新增時的形狀：
##   while sv < SAVE_VERSION: match sv: 1: _migrate_sv1_to_sv2(d); sv += 1
static func migrate(d: Dictionary) -> Dictionary:
	# 尚無 sv2，故無迴圈；沒有 sv 的舊檔也一樣，交給 _fill_defaults 補完。
	# 加入第一個遷移時把上面註解的形狀展開。
	return d


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
func load_into(target: Dictionary) -> void:
	var loaded := normalize(_read_raw())
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
