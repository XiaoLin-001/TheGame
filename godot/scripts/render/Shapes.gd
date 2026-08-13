class_name Shapes
extends RefCounted
## 20_ART_DIRECTION.md §1.4／§1.5 裡「有公式」的部分。
##
## 本批只放已經有明確規格、且下一批就要用的東西：網格與導管線寬。
## 節點／敵潮／跨越點的實際繪圖函式排在 B0.3（那時才有東西要畫），
## 現在先建檔案不先建函式 —— 沒有呼叫者的繪圖 helper 只是猜測。

## 地圖網格。所有玩家建築嚴格對齊（§1.5）。
const GRID := 32.0


## 導管線寬 = 2 + 6 × (flow / scale)，範圍 2–8px。
##
## **這是遊戲最重要的資訊視覺化：線的粗細就是流量。**
##
## ★ `scale` 是**全遊戲的最大 cap**（滿級導管），不是這條線自己的 cap。
## B1.1 之前的分母是自己的 cap，也就是「飽和度」——那讓**加粗一條線會讓它變細**
## （分母變大），而按鈕就叫「加粗」。使用者實看後的原話：「有時候升級的管道
## 卻比沒升級的還小」「應該要是越大的流量管道越粗」。
##
## 分母改成固定的最大 cap 之後：粗細在全圖上可以互相比較（同樣的粗代表同樣的
## 流量，不管那條線升到幾級），而**飽和度整個交給顏色**（`Palette.conduit()`）。
## 兩個視覺通道從此各講一件事，不再重複。
static func conduit_width(flow: float, scale: float) -> float:
	if scale <= 0.0:
		return 2.0
	return 2.0 + 6.0 * clampf(flow / scale, 0.0, 1.0)


## ★ 升過幾級的塔**看起來多大**（`10_GDD.md` §4.3，B3.9，使用者指定「每一級都要
## 有外觀上的改變」）。每級 ×1.05 累乘，滿級（5）×1.276。
##
## 為什麼是縮放而不是「每一級各畫一版」：十三種節點各有自己的幾何，每種再畫五版
## ＝ 65 個要維護的形狀，而漏掉一個的症狀是**隱形**（`_no_glyph` 就是為此而生）。
## 縮放掛在 `draw_set_transform` 上，一行就套住每一種形狀，日後新增第十四種
## 不必記得補。
##
## 1.05 是照**格子**訂的：最大的塔身半徑 13px（長哨），×1.276 ＝ 16.6px，
## 仍在半格（16px）附近——再大就會越界踩到隔壁那一格。
static func level_scale(level: int) -> float:
	return pow(1.05, float(maxi(level, 0)))


## ★ 可讀性地板（B1.2.2）。**視覺編碼是在 32px 的格子上校準與驗收的**
## （線寬 2–8px、三態徽章、射程圈，B0.6 的 `TL_NAKED` 讀圖紀錄）。
##
## 地圖框架固定之後，格子的像素大小 ＝ `GRID × fit_zoom`，也就是**圖越大格越小**。
## 24px 是 32 的四分之三：低於它，8px 的滿載線寬只剩 6px、徽章開始糊成一團，
## 「一眼看出瓶頸」（R-3）就不再是驗過的事。
##
## 這不是硬性禁令，是一條**要重新驗收才能跨過的線**：真的需要 40×40 的圖，
## 就先拿那張圖跑一次 `TL_NAKED` 讀圖，把結論寫進 `50_QA_PLAN.md`。
const MIN_READABLE_CELL := 24.0


## 一張地圖剛好填滿框架的縮放倍率。取兩軸較小值——較大值會讓另一軸溢出，
## 而「進場就看得到全貌」是框架存在的理由。
##
## 純函式放在這裡而不是畫面層：`campaign_test` 要拿它算每一關的格子大小，
## 而測試不開視窗。
static func fit_zoom(map_cells: Vector2i, frame: Vector2) -> float:
	var px := Vector2(map_cells) * GRID
	if px.x <= 0.0 or px.y <= 0.0:
		return 1.0
	return minf(frame.x / px.x, frame.y / px.y)


## 這張圖在框架裡的一格會有幾個像素。
static func fit_cell_px(map_cells: Vector2i, frame: Vector2) -> float:
	return GRID * fit_zoom(map_cells, frame)


## 座標 ↔ 網格互換。
static func to_grid(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / GRID), floori(world.y / GRID))


static func to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID, cell.y * GRID)


## ★ 路徑帶的邊緣抖動（`20_ART_DIRECTION.md` §1.6、§7.1 A-2）。
##
## §0 是全文件的統御命題：**秩序＝直線／對齊網格／銳角；混沌＝曲線／不對齊／抖動**。
## §1.6 因此要求路徑帶「不對齊網格的抖動邊緣」——而 B2.4.2 之前它是一個
## **完美的軸對齊矩形**：畫面上最大的一塊混沌側元素，是整張圖裡最幾何的東西。
##
## ── 三個實作決定 ──────────────────────────────────────────────────────
## **① 抖動掛在「格點」上，不是「格子」上。** 相鄰的兩格共用同一個角落，
##    偏移量必須是那個**格點座標**的函式，兩邊才算得出同一個值——掛在格子上
##    會讓每一格各偏各的，帶子裂成一排錯開的方塊。
## **② 零 RNG。** 純粹是座標的函式，所以 `TL_SHOT` 同參數在任何機器上拍出
##    同一張圖（`30_TECH_DESIGN.md` §2.4 那條紀律延伸到渲染）。
## **③ 只有外緣抖，內部格點回傳零**（呼叫端判斷），否則帶子內部會出現裂縫。
##
## 振幅約 ±4px（兩個不同頻率的正弦疊加，避免看出週期）。**這是刻意克制的一版**
## ——32px 的格子上 4px 剛好讓邊緣「不是機器畫的」，又不至於吵。
static func band_jitter(gx: int, gy: int) -> Vector2:
	var x := float(gx)
	var y := float(gy)
	return Vector2(
		sin(x * 1.73 + y * 0.61) * 2.4 + sin(y * 2.19) * 1.6,
		cos(y * 1.51 + x * 0.83) * 2.4 + sin(x * 2.41) * 1.6
	)


## 網格線。1px、border.subtle、透明度 20%（§1.5）。
static func draw_grid(ci: CanvasItem, rect: Rect2) -> void:
	var c := Palette.alpha(Palette.BORDER_SUBTLE, 0.2)
	var x := floorf(rect.position.x / GRID) * GRID
	while x <= rect.end.x:
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), c, 1.0)
		x += GRID
	var y := floorf(rect.position.y / GRID) * GRID
	while y <= rect.end.y:
		ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), c, 1.0)
		y += GRID
