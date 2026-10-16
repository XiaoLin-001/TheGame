extends RefCounted
## 局內畫面的**延後載入**（開機速度）。
##
## ── 為什麼 ─────────────────────────────────────────────────────────────
## GDScript 的 `preload()` 是**載入這支腳本時就一併編譯**。標題畫面 `Main.gd` 與戰役選擇、難度層選擇都 `preload` 了
## `Battle.gd`，而 `Battle.gd` 往下拉著整個局內的程式碼——舞台（2D、3D）、十一個 HUD 面板、造型配方、測試鉤子……
## 約 2/3 的腳本行數。結果是**玩家還沒看到標題，就先等這些全部編譯完**（量過：開機到第一個畫面，其中約一半是這個）。
## 標題畫面根本用不到它們：玩家按下「戰役」之前，還有好幾秒。
##
## ── 做法 ───────────────────────────────────────────────────────────────
##   · 這三個畫面**不再 `preload` Battle**，改問這支（它自己幾乎沒有相依）：`script()` 回 `Battle.gd`（已載入就是快取，沒載入就當場載）。
##   · 標題畫面一出來就 `prefetch()`：在**背景執行緒**把局內那一大包編譯好（幾支大的各自一個請求，可以並行）。
##     玩家按「戰役」的時候它通常已經好了；沒好就等剩下的那一點（`load()` 會等進行中的請求）。
## 自動化（`TL_PANEL=…` 直接進畫面）不走標題，所以沒有預取、當場載——行為與之前一樣，只是不再有人白等。

const PATH := "res://scripts/screens/Battle.gd"

## 預取清單：局內最大的幾支各自一個請求，編譯可以並行（`Battle.gd` 自己會把其餘的依序拉進來，已經在進行中的它會等）。
## 測試鉤子（`SelfTest.gd`）不在清單上：只有自動化才會用到，玩家永遠不需要。
const PREFETCH := [
	PATH,
	"res://scripts/screens/battle/Stage2D.gd",
	"res://scripts/screens/battle/Stage3D.gd",
	"res://scripts/screens/battle/hud/ResultPanel.gd",
	"res://scripts/screens/battle/hud/InspectPanel.gd",
	"res://scripts/screens/battle/hud/MenuLayer.gd",
]

static var _requested: bool = false


## 局內畫面的腳本（`Battle.gd`）。第一次呼叫可能要等（沒預取完），之後是快取。
static func script() -> GDScript:
	return load(PATH) as GDScript


## 背景預取。可以重複呼叫，只有第一次有作用。
static func prefetch() -> void:
	if _requested:
		return
	_requested = true
	for p: String in PREFETCH:
		ResourceLoader.load_threaded_request(p, "", true)
