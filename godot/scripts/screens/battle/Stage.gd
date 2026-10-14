extends Control
## 局內舞台的**契約**（畫面層與舞台實作之間的接縫）。
##
## 局內畫面（`screens/Battle.gd`）、覆蓋層（`Overlay2D`）與 HUD 只認這個檔案列出的東西。
## 現在唯一的實作是 `Stage2D`（俯視的格子地圖，用 `_draw()` 畫）；要換成別種畫法（例如 3D），
## **照這份契約另寫一個實作就好**，局內畫面與 HUD 不必動：
##
##   · 它是一個滿版的 `Control`（`mouse_filter = IGNORE`）——HUD 仍然是同一批 2D `Control` 疊在上面。
##   · **只讀 `s`（`SessionState`），不改局面，不擁有遊戲規則。**
##   · **座標約定**：「格」是 `Vector2i`（模擬層的唯一座標）；「地圖座標」是格 × `Shapes.GRID` 的
##     像素（`center()` 回的就是它）；「螢幕座標」是 `Control` 的全域像素。`cell_at()`／`to_screen()`
##     是這三者之間唯一的換算——換一種畫法時，拾取與投影都只收在這兩個函式裡。
##
## ⚠ 這份契約只涵蓋**畫面層真的用到的**東西（由 `Battle.gd`、`Overlay2D` 的呼叫點反推）。
##   新增一個跨模組的呼叫，就是在這裡新增一條契約——請先在這裡寫成空實作，再去實作它。

## 地圖框架：地圖在螢幕上佔據的矩形。HUD 的版面（頂欄、建造欄、底欄）是照它排的，
## 所以它是**版面常數**，不是 2D 的實作細節。
##
## 36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，浮層與地圖**不重疊**
## （RG-20 的先行實踐）。★ B1.2.2（使用者要求）：**玩家看到的地圖區域恆定**，不隨關卡
## 大小變動：進場時自動縮放到剛好填滿它，之後玩家自由縮放。
## 這比「地圖必須小到放得進一屏」好在兩件事：關與關之間的視覺尺度一致，而且**地圖尺寸不再受
## 畫面限制**——它變成純粹的關卡設計參數。代價是格子的像素大小會隨圖變大而變小，
## 而線寬／徽章那套視覺編碼有一個可讀性地板（`50_QA_PLAN.md` RG-58）。
## x=120 讓出左側建造欄，y=56 讓出頂欄，下緣停在 660（底欄鈕在 668）。
const FRAME := Rect2(Vector2(120.0, 56.0), Vector2(1152.0, 604.0))

## 滾輪／按鈕每一格的縮放比。
const ZOOM_STEP := 1.25

## 視野變了（重設、平移、縮放）。覆蓋層聽它來決定小地圖要不要現身。
signal view_moved

## 擁有這個舞台的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null

## 視野倍率與它的下限（「全景」＝回到 `fit`）。HUD 的「全景 100%」讀的就是 `zoom / fit`。
## 數值的單位不重要，比值才是。
var zoom: float = 1.0
var fit: float = 1.0
## 平移（螢幕像素）與它的目標。fit 時恆為 0。
var pan: Vector2 = Vector2.ZERO
var pan_goal: Vector2 = Vector2.ZERO

## 本幀交戰中的塔 `{id: bool}`、正在被啃的格 `{cell: true}`。**舞台自己算**——
## 它要畫的是「誰正在吃電」「哪裡正在被啃」，模擬層只留了一個座數。HUD 與小地圖會讀它們。
var engaged: Dictionary = {}
var threat: Dictionary = {}


## 回到進場的視野（fit ＋ 居中）。也是「全景」鈕。
func reset_view() -> void:
	pass


## 以螢幕上的 `anchor` 為不動點縮放。
func zoom_by(_mult: float, _anchor: Vector2) -> void:
	pass


## 平移到 `p`。`immediate` 為真時當場到位（測試與直接拖曳用），否則平滑追過去。
func pan_to(_p: Vector2, _immediate: bool = false) -> void:
	pass


## 平移一個**相對量**（螢幕像素）。滑鼠中鍵拖曳走這條。
func pan_by(_rel: Vector2) -> void:
	pass


## 把某一格移到畫面中央（小地圖與箭頭的「一鍵跳」）。
func center_view_on(_c: Vector2i, _immediate: bool = false) -> void:
	pass


## 目前看得到的地圖座標矩形。小地圖的視野框與「這個問題在不在畫面內」都從這裡算。
func view_world_rect() -> Rect2:
	return Rect2()


## 地圖在目前倍率下裝不進框架嗎？＝ 需不需要小地圖與邊緣箭頭。
func oversized() -> bool:
	return false


## 螢幕座標 → 格。**拾取的唯一入口**：命中判定與繪圖共用同一個反變換。
func cell_at(_pos: Vector2) -> Vector2i:
	return Vector2i(-1, -1)


## 螢幕座標 → **格為單位的浮點座標**（整數＝格中心）。點導管要靠它。
func point_at(_pos: Vector2) -> Vector2:
	return Vector2.ZERO


## 格 → 地圖座標（格中心的像素）。
func center(_c: Vector2i) -> Vector2:
	return Vector2.ZERO


## 地圖座標 → 螢幕座標。**投影的唯一入口**。
func to_screen(_p: Vector2) -> Vector2:
	return Vector2.ZERO


## 這一格在不在地圖範圍內。
func in_map(_c: Vector2i) -> bool:
	return false


## 每幀的視野緩動（只動畫面，不碰模擬）。
func tick_view(_delta: float) -> void:
	pass
