extends RefCounted
## 死因歸因的累計（B1.7）。B3.14 自 `screens/Battle.gd` 抽出。
##
## M1 的驗收句子是「**陌生人可以說得出自己為什麼輸**」。局末面板原本只給
## 「撐過幾波、產能積分多少」——那些是**成績**，不是**原因**。玩家輸掉的時候
## 要的是下一句「所以我下次該改什麼」。
##
## 全部從狀態的逐 tick 差值累計，模擬層一個欄位都不動（`scripts/sim/` 零副作用）。
## 一局一份：`reset()` 在開局與重來時呼叫。

var wave_ticks: int = 0
var starved: int = 0
## 核心開始掉血的那一波 ＝ 第一次有敵人走到底。−1 ＝ 還沒有。
var leak_wave: int = -1
var core_hp: float = 0.0


func reset(s: RefCounted) -> void:
	wave_ticks = 0
	starved = 0
	leak_wave = -1
	core_hp = s.core_hp()


## 每當模擬往前走了一個 tick 就呼叫一次。
func tick(s: RefCounted) -> void:
	if s.phase != "wave":
		return
	wave_ticks += 1
	if float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01:
		starved += 1
	# 核心開始掉血的那一波 ＝ 第一次有敵人走到底。
	if leak_wave < 0 and s.core_hp() < core_hp - 0.01:
		leak_wave = s.wave_index
	core_hp = s.core_hp()


## 一句話的死因。**只給一句**：三條並列的診斷等於沒有診斷。
func line(won: bool) -> String:
	var ticks: int = maxi(1, wave_ticks)
	var starve := float(starved) / float(ticks)
	if not won:
		if leak_wave >= 0:
			return "為什麼輸　第 %d 波開始有敵人走到核心。%s" % [
				leak_wave,
				"缺電讓塔的射速掉了（%d%% 的戰鬥時間供不應求）——先補發電機或儲槽。" % roundi(starve * 100.0)
				if starve >= 0.25 else "那條路線上的火力不夠——把塔往敵人的必經之路挪，或多蓋一座。",
			]
		return "為什麼輸　核心被相鄰的敵人啃掉了。節點退開敵人路徑 2 格就打不到。"
	if starve >= 0.25:
		return "下一次　有 %d%% 的戰鬥時間供不應求，塔是降速在打的——補電力就能拉高產能積分。" % roundi(starve * 100.0)
	return ""
