class_name BattleCamera
extends RefCounted
## 2D 相機：視野框架、fit／縮放／平移與「螢幕 ↔ 格」座標轉換。換成 3D 時這是第一個被取代的元件。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Motion := preload("res://scripts/render/Motion.gd")

## 地圖左上角。36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，
## 浮層與地圖**不重疊**（RG-20 的先行實踐，正式驗收在 B0.6）。
## ★ 地圖框架（B1.2.2，使用者要求）。**玩家看到的地圖區域恆定**，不隨關卡
## 大小變動：進場時自動縮放到剛好填滿它，之後玩家自由縮放。
##
## 這比「地圖必須小到放得進一屏」好在兩件事：關與關之間的視覺尺度一致
## （20×12 的第 1 關不再只佔左上角一小塊），而且**地圖尺寸不再受畫面限制**
## ——它變成純粹的關卡設計參數。代價是**格子的像素大小會隨圖變大而變小**，
## 而線寬／徽章那套視覺編碼有一個可讀性地板（`50_QA_PLAN.md` RG-58）。
##
## x=120 讓出左側建造欄，y=56 讓出頂欄，下緣停在 660（底欄鈕在 668）。
const FRAME := Rect2(Vector2(120.0, 56.0), Vector2(1152.0, 604.0))

## 縮放上限＝**下限**的幾倍。
##
## ★ 下限在 B2.1b 從「就是 fit」改成 `max(fit, 可讀性地板)`：
##   一屏可見的圖（全部戰役關卡）fit 本來就在地板之上 → 行為完全不變；
##   大過一屏的圖（無盡）fit 會讓一格掉到 24px 以下，而那正是 RG-59 說
##   「要重新驗收才能跨過」的線——**縮到看得見全圖但讀不出瓶頸，等於
##   把 R-3 的驗收轉包給玩家**。所以無盡看全圖的地方是小地圖，不是主畫面。
const ZOOM_MAX_MULT := 3.0

const ZOOM_STEP := 1.25

## 視野（B1.2.2）。`_fit` 是「剛好填滿框架」的倍率，也是縮放下限。
var zoom: float = 1.0

var fit: float = 1.0

## 平移（螢幕像素）。fit 時恆為 0（地圖與框架同大，居中就是全貌）。
var pan: Vector2 = Vector2.ZERO

## ★ 平移的**目標**（B2.1d）。`_pan` 每幀朝它收斂，所以小地圖拖曳與一鍵跳
## 都是平滑的。**中鍵直接拖地圖不走這條**——直接拖曳加上緩動會變成「黏手」，
## 手指到哪畫面就該到哪。`reduce_motion` 開啟時一律直接到位（§1.6 的紀律：
## 動效是裝飾，關掉之後資訊一點都不能少）。
var pan_goal: Vector2 = Vector2.ZERO

## 每秒收斂比率。14 在 60fps 下約 4 幀走完八成——快到不覺得延遲，
## 又慢到看得出是「滑過去」而不是「跳過去」（使用者要的是後者的反面）。
const PAN_EASE := 14.0

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## 縮放下限。一屏可見的圖就是 fit；大過一屏的圖是**可讀性地板**（24px／格）。
##
## `_fit` 這個欄位名沿用下來（它是「全景」鈕與縮放夾限共用的那一個值），
## 但語意在 B2.1b 之後是「看得最遠的倍率」，不一定看得到全圖。
func _fit_zoom() -> float:
	return maxf(
		Shapes.fit_zoom(battle.s.map["size"], FRAME.size),
		Shapes.MIN_READABLE_CELL / Shapes.GRID
	)


## 地圖在目前倍率下裝不進框架嗎？＝ 需不需要小地圖與邊緣箭頭。
## **一屏可見的地圖一律 false**，所以戰役關卡不會多出這兩塊遮擋。
func oversized() -> bool:
	var px := Vector2(battle.s.map["size"]) * Shapes.GRID * zoom
	return px.x > FRAME.size.x + 0.5 or px.y > FRAME.size.y + 0.5


## 進場（與「全景」鈕）的視野：fit ＋ 居中。
func reset_view() -> void:
	fit = _fit_zoom()
	zoom = fit
	pan = Vector2.ZERO
	pan_goal = Vector2.ZERO
	battle.guide.mini_ttl = BattleGuide.MINI_HOLD
	# ★ `TL_FOCUS="x,y,zoom"`：拍特效的近照（B1.6）。**不會在真實遊玩中生效**
	#   ——它只在有鉤子時存在，而有鉤子時存檔已經是唯讀的。
	if Hooks.focus.x >= 0:
		zoom = clampf(fit * Hooks.focus_zoom, fit, fit * ZOOM_MAX_MULT)
		var px := Vector2(battle.s.map["size"]) * Shapes.GRID
		pan_to((px * 0.5 - center(Hooks.focus)) * zoom, true)


## 地圖左上角在螢幕上的位置。**框架內居中**，放大後由 `_pan` 帶著走。
func map_origin() -> Vector2:
	var px := Vector2(battle.s.map["size"]) * Shapes.GRID * zoom
	return FRAME.position + (FRAME.size - px) * 0.5 + pan


## 放大之後地圖比框架大，平移要有邊界——不然可以把地圖整片拖出畫面，
## 然後玩家會以為遊戲壞了。夾住之後框架永遠被地圖蓋滿。
func clamp_pan() -> void:
	var px := Vector2(battle.s.map["size"]) * Shapes.GRID * zoom
	var slack := (px - FRAME.size) * 0.5
	pan.x = clampf(pan.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	pan.y = clampf(pan.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))
	pan_goal.x = clampf(pan_goal.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	pan_goal.y = clampf(pan_goal.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))


## 設定平移目標。`immediate` 為真時當場到位——中鍵拖曳、縮放錨定、
## 以及所有測試斷言都走這條（斷言要驗的是「目標對不對」，不是「補間跑完沒」）。
func pan_to(p: Vector2, immediate: bool = false) -> void:
	# 視野一動，小地圖就現身（並重新計時）。
	battle.guide.mini_ttl = BattleGuide.MINI_HOLD
	pan_goal = p
	if immediate or Motion.reduce:
		pan = p
	clamp_pan()
	battle.queue_redraw()


## 讓補間立刻走完。測試專用——把「動畫還沒到」和「算錯位置」分開。
func settle_view() -> void:
	pan = pan_goal
	clamp_pan()
	battle.queue_redraw()


## 縮放。`anchor` 是螢幕上要固定不動的那一點（滑鼠位置或框架中心）——
## 少了它，滾輪縮放會把玩家正在看的東西推出畫面。
func zoom_by(mult: float, anchor: Vector2) -> void:
	var before := zoom
	zoom = clampf(zoom * mult, fit, fit * ZOOM_MAX_MULT)
	if is_equal_approx(before, zoom):
		return
	# ★ 讓 `anchor` 底下的那一格在縮放前後**待在原地**。
	#
	#   B1.2.2 的版本寫成 `_pan += (anchor - _map_origin()) * (1 - k)`，錯了兩層：
	#     ① `_map_origin()` 讀的是**已經更新過**的 `_zoom`，量到的是新原點不是舊的；
	#     ② 更根本地，`_map_origin()` 本來就把地圖置中，那一半的位移是縮放自己
	#        帶來的、不該再由 pan 補一次。
	#   兩個加起來的結果是：**按一次「＋」畫面就甩到左上角，而且 pan 當場撞上夾限、
	#   再也拖不動。** `_view_selftest` 當時只斷言「倍率有變大」與「pan 夾得住」，
	#   兩條都還是綠的——這個缺陷是 B1.3.1 加中鍵平移自檢時，
	#   `mid_pan=false` 把它逼出來的。
	#
	#   所以直接照定義寫：新原點 = anchor − k × (anchor − 舊原點)，pan 就是它和
	#   置中位置的差。看得懂比省一行重要。
	var m := Vector2(battle.s.map["size"]) * Shapes.GRID
	var origin_before := FRAME.position + (FRAME.size - m * before) * 0.5 + pan
	var k := zoom / before
	pan_to(
		anchor - (anchor - origin_before) * k
		- (FRAME.position + (FRAME.size - m * zoom) * 0.5),
		true
	)
	battle.bars.refresh_zoom()
	battle.queue_redraw()


## 螢幕像素 → 格號。**縮放與平移的反變換就在這一行**，命中判定與繪圖
## 因此永遠對得起來（各寫一份的那一天，滑鼠就會差半格）。
func cell_at(pos: Vector2) -> Vector2i:
	return Shapes.to_grid((pos - map_origin()) / zoom)


## 螢幕像素 → **格為單位的浮點座標**（整數＝格中心）。
func point_at(pos: Vector2) -> Vector2:
	return (pos - map_origin()) / (Shapes.GRID * zoom) - Vector2(0.5, 0.5)


func in_map(c: Vector2i) -> bool:
	var size: Vector2i = battle.s.map["size"]
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


## 目前看得到的世界座標矩形。小地圖的視野框與「這個問題在不在畫面內」
## 都從這裡算——**只有一份**，兩者不可能各算各的而對不起來。
func view_world_rect() -> Rect2:
	var o := map_origin()
	return Rect2((FRAME.position - o) / zoom, FRAME.size / zoom)


## 把某一格移到畫面中央（小地圖與箭頭的「一鍵跳」）。
## 與 `TL_FOCUS` 走同一條算式——兩份會漂掉。
func center_view_on(c: Vector2i, immediate: bool = false) -> void:
	var px := Vector2(battle.s.map["size"]) * Shapes.GRID
	pan_to((px * 0.5 - center(c)) * zoom, immediate)


## ★ 地圖座標（格 × 32px），**不是螢幕座標**——縮放與平移由 `_draw()` 開頭
## 那一個 `draw_set_transform` 統一處理（B1.2.2）。
func world(c: Vector2i) -> Vector2:
	return Shapes.to_world(c)


func center(c: Vector2i) -> Vector2:
	return world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 地圖座標 → 螢幕座標。只有需要拿螢幕位置的地方才用（例：把浮層對到節點上）。
func to_screen(p: Vector2) -> Vector2:
	return map_origin() + p * zoom
