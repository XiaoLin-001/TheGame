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
