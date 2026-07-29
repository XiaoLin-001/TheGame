extends RefCounted
## 局末結算與提前召喚的下注數學（`10_GDD.md` §3.4、§7.6）。
##
## **純函式、零副作用、零 RNG。** 不引用 autoload。
##
## 這支檔案存在的理由：這幾個數字同時被三個地方讀——按鈕上的倍率、擊殺時的
## 礦砂加成、局末結算的研究數據。散在三處就會各寫一份、然後彼此對不起來。

## 提前召喚的倍率上限（§7.6：`1 + 剩餘比例 × 0.5`）。
const SUMMON_BONUS_MAX := 1.5
## 每波在研究數據裡值多少（§7.6 `10 × 波次數`）。倍率乘的就是這一項。
const DATA_PER_WAVE := 10.0
## 產能積分的權重與除數（§7.6 `2 × 產能積分`、`產能積分 = 平均每秒總產出 / 10`）。
const DATA_PER_SCORE := 2.0
const THROUGHPUT_DIVISOR := 10.0


## 提前召喚的獎勵倍率。**按下當下算一次，鎖給那一波**（§7.6）——
## 波次開始後準備期倒數就停了，事後再算一律拿到 1.0。
static func summon_bonus(remaining: float, prep_time: float) -> float:
	if prep_time <= 0.0:
		return 1.0
	return minf(SUMMON_BONUS_MAX, 1.0 + clampf(remaining / prep_time, 0.0, 1.0) * 0.5)


## 產能積分＝**送達核心的礦砂**平均每秒 ÷ 10（§7.6）。
## 分母含準備期：準備期也在生產，排除它等於獎勵「一直快進」。
static func throughput(delivered_total: float, ticks: int, tick_len: float) -> float:
	var seconds := float(ticks) * tick_len
	if seconds <= 0.0:
		return 0.0
	return delivered_total / seconds / THROUGHPUT_DIVISOR


## 局末研究數據 = `10 × 波次數 + 2 × 產能積分 + 提前召喚累計加成`（§7.6）。
## `bonus_data` 由 `summon_data_bonus()` 逐波累加而來。
static func research_data(waves: int, throughput_score: float, bonus_data: float) -> float:
	return DATA_PER_WAVE * float(waves) + DATA_PER_SCORE * throughput_score + bonus_data


## 一波的提前召喚加成折成研究數據：`10 × (倍率 − 1)`，每波最多 +5。
static func summon_data_bonus(bonus: float) -> float:
	return DATA_PER_WAVE * maxf(0.0, bonus - 1.0)


## ★ 星等（`10_GDD.md` §7.9）。三顆星＝三個學習階段：撐住 → 守好 → 生產。
##
##   ★   通關
##   ★★  核心無損——敵人只在核心駐足，核心掉血等於「有東西走到底了」
##   ★★★ 產能積分 ≥ 該關宣告門檻（用 §7.6 已定義的分數，不另發明）
##
## **三條是累進的**：沒通關就是 0 顆，核心破了就封頂 1 顆——
## 讓「產能爆表但核心快沒了」拿到三星，等於把這一關的第一課教反。
static func stars(won: bool, core_hp: float, core_max: float, tp: float, threshold: float) -> int:
	if not won:
		return 0
	if core_hp < core_max:
		return 1
	return 3 if tp >= threshold else 2


## 這一關這次拿到的研究數據 ＝ `基礎獎勵 × 星數`，扣掉歷史最高星數已經領過的
## 部分（§7.9）。回頭補星拿得到差額，重刷同一星數拿不到第二次。
static func reward_delta(reward: int, stars_now: int, stars_best: int) -> float:
	return float(reward) * float(maxi(0, stars_now - maxi(0, stars_best)))
