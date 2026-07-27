class_name Palette
extends RefCounted
## 20_ART_DIRECTION.md §1.1 的實作。
##
## **全專案唯一的色值來源。** 任何 `Color(...)` 或 `Color("#...")` 字面量
## 出現在其他檔案，視為缺陷（每批 UI 一致性檢查會 Grep 這件事）。
##
## 兩條配色紀律（§1.1）：
##   1. 只有敵人與危險狀態能用品紅／橙 —— 保證眼睛能在混亂畫面裡瞬間找到威脅。
##   2. 琥珀專屬於能量 —— 看到琥珀＝跟耗能有關。這是本作最重要的資訊通道。

# ── 底層 ──
const BG_DEEP := Color("#0a1420")       ## 主背景（深潮）
const BG_PANEL := Color("#10202e")      ## 面板底
const BG_RAISED := Color("#162c3d")     ## 浮起元件（按鈕、卡片）
const BORDER_SUBTLE := Color("#1d3547") ## 面板分隔線、網格
const BORDER_STRONG := Color("#2e5570") ## 選中／聚焦邊框

# ── 秩序側（玩家）──
const ORDER_CYAN := Color("#7fd4e8")    ## 主色：節點、導管、UI 主體
const ORDER_BRIGHT := Color("#a8f0ff")  ## 導管滿載、選中高亮
const ORDER_DIM := Color("#3c6e80")     ## 未啟用／飢餓狀態

# ── 能量與材料 ──
const ENERGY_AMBER := Color("#ffc857")  ## 能量：能量列、發電機、耗能相關數字
const ALLOY_STEEL := Color("#b8c9d4")   ## 合金、高階建築

# ── 混沌側（敵潮）──
const TIDE_MAGENTA := Color("#ff4d6d")  ## 敵人本體
const TIDE_DEEP := Color("#7b2d5e")     ## 敵潮陰影、路徑帶、來襲方向指示

# ── 狀態 ──
const WARN_ORANGE := Color("#ff8a3d")   ## 能量不足、建築受損、倒數 <10s
const OK_GREEN := Color("#5fd39a")      ## 交貨完成、解鎖、關卡通過

# ── 文字 ──
const TEXT_PRIMARY := Color("#e8f1f5")
const TEXT_SECONDARY := Color("#8ba3b0")
const TEXT_DISABLED := Color("#4a5f6b")


## 導管顏色：正常（青）→ 滿載（亮青）→ 飢餓（暗青）。
## 這是「線的顏色＝飽和度」這條資訊視覺化規則的唯一實作（§1.4、R-3）。
static func conduit(flow: float, cap: float, starving: bool) -> Color:
	if starving:
		return ORDER_DIM
	if cap <= 0.0:
		return ORDER_DIM
	return ORDER_BRIGHT if flow >= cap - 0.001 else ORDER_CYAN


## 依透明度取色。避免各處自己寫 `var c := X; c.a = 0.2`。
static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
