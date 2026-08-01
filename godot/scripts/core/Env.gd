class_name Env
extends RefCounted
## 環境變數鉤子的讀取層（純靜態，零 autoload 依賴）。
##
## 為什麼要有這個檔案：`tests/*.gd` 以 `--script` 執行時 **不載入 autoload**
## （30_TECH_DESIGN.md §4.2）。任何需要在測試裡使用的環境判斷都必須走這裡，
## 而不是問 Hooks 這個 autoload。同時，各 autoload 一律透過 Env 各自讀取，
## 彼此不互相引用 —— 否則 `_ready()` 的執行順序會變成隱性依賴。
##
## 鉤子清單與語意見 30_TECH_DESIGN.md §4.1。

## 本專案承認的鉤子。新增鉤子必須同步加進這裡，
## 否則 any_hook() 認不得它，存檔保護（規則 1）會失效。
const HOOKS := [
	"TL_SHOT",        # =<png絕對路徑>　渲染數秒後截圖並自動退出
	"TL_SHOT_DELAY",  # =<秒>　截圖前等待，讓動效跑完（預設 3）
	"TL_PANEL",       # =<畫面名>　直開某畫面，跳過導航
	"TL_MUTE",        # =1　全域靜音
	"TL_SEED",        # =<int>　覆寫隨機種子
	"TL_SIM",         # =<ticks>　headless 模擬，輸出 JSON 後退出
	"TL_NAKED",       # =1　隱藏所有數值標籤（R-3 可讀性驗收專用）
	"TL_DEMO_TICKS",  # =<ticks>　示範佈局先推幾個 tick 再截圖（預設 860）
	"TL_CLICKTEST",   # =1　用合成滑鼠事件點地圖，驗證輸入層（B0.7.2 的教訓）
	"TL_LEVEL",       # =1..5　TL_PANEL=campaign 時直接進那一關
	"TL_FOCUS",       # ="x,y,zoom"　鏡頭對到某一格並放大（拍特效近照）
	"TL_STRESS",      # =1　壓力情境，模擬凍結只量渲染（B1.7、RG-8）
]

## ⚠ 上面漏掉一個就等於**那個鉤子單獨使用時會寫進玩家的真實存檔**（規則 1）。
## `TL_LEVEL` 與 `TL_FOCUS` 是 B1.2／B1.6 加的，一直到 B1.7 才補進這張表——
## 它們實務上都跟 `TL_PANEL` 一起用所以沒出事，但「實務上不會單獨用」不是保護。


static func has(name: String) -> bool:
	return OS.has_environment(name) and OS.get_environment(name).strip_edges() != ""


static func str_of(name: String, def: String = "") -> String:
	if not has(name):
		return def
	return OS.get_environment(name).strip_edges()


static func int_of(name: String, def: int) -> int:
	var s := str_of(name, "")
	return int(s) if s.is_valid_int() else def


static func float_of(name: String, def: float) -> float:
	var s := str_of(name, "")
	return float(s) if s.is_valid_float() else def


## 旗標型鉤子：存在且不是 "0"／"false" 即視為開啟。
static func flag(name: String) -> bool:
	var s := str_of(name, "").to_lower()
	return s != "" and s != "0" and s != "false"


## 是否有任何測試鉤子啟用。
## 鐵律 1（30_TECH_DESIGN.md §4.1）：為真時存檔一律不落地。
static func any_hook() -> bool:
	for h: String in HOOKS:
		if has(h):
			return true
	return false


## 是否應該全域靜音。
## 鐵律 2：TL_SHOT 或 TL_MUTE 存在時自動靜音 —— 絕不在使用者可能正在工作時發出聲音。
## 放在這裡而不是 Hooks，是為了讓 AudioBus 不必依賴 Hooks 的 _ready 先跑完。
static func want_mute() -> bool:
	return flag("TL_MUTE") or has("TL_SHOT")


## 啟用中的鉤子。`with_values` 只給 stdout 用。
##
## **畫面上一律用不帶值的那個**：TL_SHOT 的值是絕對路徑，直接畫上去會橫跨
## 整個畫面、在小解析度下裁切（P1）。螢幕要回答的是「哪些鉤子開著」。
static func active(with_values: bool = false) -> String:
	var on: PackedStringArray = []
	for h: String in HOOKS:
		if has(h):
			on.append("%s=%s" % [h, str_of(h)] if with_values else h)
	return " ".join(on)
