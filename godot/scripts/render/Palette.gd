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
const ALLOY_STEEL := Color("#b8c9d4")   ## 高階**建築**的金屬感（熔爐、稜鏡、碎浪）
## 合金這個**資源本身**：流動珠與帳上數字。
##
## ★ 為什麼不是 `ALLOY_STEEL`：鋼銀 #b8c9d4 的明度和導管的青 #7fd4e8 幾乎一樣，
## 而流動珠是畫在導管上的——鋼銀珠子會直接融進線裡，變成 B0.6 使用者回報過的
## 那個「看不到貨物在流動」。三種資源的珠子必須靠**色相**分得開：
## 礦砂＝近白（無色相）、能量＝琥珀（暖）、合金＝紫（冷而非青）。
## 這與「採集器是青色、但礦砂珠是白色」是同一條既有慣例：**建築的顏色和
## 它產出的資源的顏色本來就不是同一件事。**
const ALLOY_VIOLET := Color("#c8a0ff")

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


## 導管顏色：青 →（連續）→ 亮青，飢餓為暗青。
## 這是「線的顏色＝飽和度」這條資訊視覺化規則的唯一實作（§1.4、R-3）。
##
## ★ B1.1 起是**連續**的，不是「滿了才亮」的兩段跳。線寬改成表達絕對流量之後
## （`Shapes.conduit_width()`），飽和度只剩顏色這一個通道，兩段跳會讓「九成滿」
## 和「一成滿」長得一模一樣——瓶頸在真的塞爆之前完全看不出來。
##
## 用平方而不是線性：低飽和度時幾乎維持青色，接近滿載才快速提亮，
## 保住「第一台發電機讓那條線當場亮起來」那個 B0.3 的教學瞬間。
static func conduit(flow: float, cap: float, starving: bool) -> Color:
	if starving or cap <= 0.0:
		return ORDER_DIM
	var sat := clampf(flow / cap, 0.0, 1.0)
	return ORDER_CYAN.lerp(ORDER_BRIGHT, sat * sat)


## 依透明度取色。避免各處自己寫 `var c := X; c.a = 0.2`。
static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
