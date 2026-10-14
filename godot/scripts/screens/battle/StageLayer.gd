extends Node2D
## 舞台的一層**快取圖層**（B3.15）。
##
## `Stage2D._draw()` 原本每幀把**整張圖**從 GDScript 重發一次——路徑、導管、節點、流動珠全部——
## 而其中絕大多數在一個 tick（0.1 秒）之內根本沒變：RG-184 量到戰役第 10 關每幀 12 ms 花在 GDScript 的繪圖指令上。
## 這一層只在**內容簽章**變了才重畫（`refresh()`）；其餘的幀引擎直接重播上次記下的指令，GDScript 一行都不跑。
##
## 做法與 B3.13 的地貌層相同：`show_behind_parent` 的 `Node2D`，座標是**地圖座標**，
## 縮放與平移由這一層自己的 transform 帶（`place()`），所以 `painter` 裡的每一支 `_draw_*` 都不知道視野存在。
## 圖層的**順序就是繪圖順序**——加入的先後必須和原本 `_draw()` 裡呼叫的先後一致。
##
## 兩種用法：**頂層圖層**（`show_behind_parent`，畫在舞台本體後面，由 `Stage2D._add_layer()` 設）與
## **逐件的畫布項**（一座節點、一條導管各一個，掛在群組底下，只重畫簽章變了的那一件）。

## 畫這一層的函式：`func(ci: CanvasItem) -> void`。
var painter: Callable

## 上一次畫的內容簽章。
var key: Array = []

## 重畫了幾次（測試用：證明「簽章沒變就不重畫」）。
var redraws: int = 0

var _valid: bool = false

var _at: Vector2 = Vector2(INF, INF)

var _zoom: float = -1.0


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)


## 簽章變了才重畫。回傳有沒有重畫。
func refresh(new_key: Array) -> bool:
	if _valid and key == new_key:
		return false
	key = new_key
	_valid = true
	repaint()
	return true


## 不管簽章，現在就重畫（每幀都在動的層用它）。
func repaint() -> void:
	redraws += 1
	queue_redraw()


## 下一次 `refresh()` 一定重畫。
func invalidate() -> void:
	_valid = false


## 對到目前的視野（地圖原點在螢幕上的位置與縮放）。沒變就什麼都不做。
func place(origin: Vector2, zoom: float) -> void:
	if origin == _at and zoom == _zoom:
		return
	_at = origin
	_zoom = zoom
	position = origin
	scale = Vector2(zoom, zoom)
