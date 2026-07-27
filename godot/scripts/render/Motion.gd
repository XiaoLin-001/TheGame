class_name Motion
extends RefCounted
## 20_ART_DIRECTION.md §4 的實作：動效時長階與緩動。
##
## 所有動效都必須用這裡的時長階，且都必須可被「減少動態效果」關閉（§4.4）——
## 那既是無障礙需求，也是高手快速重來的需求。

const INSTANT := 0.12  ## 按鈕回饋、hover、選中框
const BASE := 0.24     ## 面板開闔、數值補間、狀態切換
const SLOW := 0.50     ## 畫面轉場、局末結算逐項揭示
const AMBIENT := 2.0   ## 敵潮脈動、背景呼吸（循環）


## 玩家操作的回饋：快起慢收＝有回應感。
static func out_cubic(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


## 敵潮的呼吸：有機的來回。輸入為累積時間，輸出 0..1。
static func breathe(elapsed: float, period: float = AMBIENT) -> float:
	return 0.5 - 0.5 * cos(TAU * elapsed / maxf(period, 0.001))


## 是否應該省略動效。讀設定裡的 reduce_motion；找不到就照常播。
## 放這裡而不是各處自己判斷，是為了讓「所有動效可跳過」成為一行就能遵守的事。
static func reduced(settings: Dictionary) -> bool:
	return bool(settings.get("reduce_motion", false))
