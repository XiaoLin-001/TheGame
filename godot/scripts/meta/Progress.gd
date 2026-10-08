extends RefCounted
## 局外進度的狀態轉移：把一件事的結果寫進存檔字典。B3.14 自 `core/SaveService.gd` 抽出。
##
## `SaveService` 管**存檔的形狀與落地**（預設值、遷移、讀寫檔）；這裡管**進度怎麼變**
## （戰役星數、無盡／每日紀錄、藍圖、招募、升級材料與等級軸）。兩件事分開，
## 是因為前者幾乎不變、後者每一批都在加新動詞——放在一起，存檔服務就會
## 一路長成「全遊戲的規則大雜燴」。
##
## **純函式、零副作用、不引用 autoload、不做 IO**：全部只改傳進來的字典，
## 要不要寫檔是呼叫端的事（`SaveService.save_from()`）。所以 headless 測試與
## 3D 畫面都用同一份，不碰玩家的真存檔。

const Achievements := preload("res://data/Achievements.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Levels := preload("res://data/Levels.gd")
const Roster := preload("res://data/Roster.gd")
const Score := preload("res://scripts/sim/Score.gd")


## ★ 把一局戰役的結果寫進存檔（B1.2、`10_GDD.md` §7.9）。**只增不減**：
## 星數取歷史最高、研究數據只補發差額、已通關的關卡不會因為重玩失敗而消失
## （紅線 R1「失敗只花時間」在存檔層的樣子）。
##
## 回傳實得的研究數據，讓局末結算面板有東西可講——
## 靜靜地寫進存檔而不告訴玩家，等於沒有獎勵。
static func apply_result(d: Dictionary, level_id: String, stars: int, reward: int) -> float:
	var campaign: Dictionary = d.get("campaign", {})
	var best: Dictionary = campaign.get("stars", {})
	if stars <= 0:
		return 0.0
	var gain := Score.reward_delta(reward, stars, int(best.get(level_id, 0)))
	best[level_id] = maxi(stars, int(best.get(level_id, 0)))
	var tech: Dictionary = d.get("tech", {})
	tech["data"] = float(tech.get("data", 0)) + gain
	return gain


## ★ 無盡的個人最佳（B2.1a、`10_GDD.md` §7.10）。**兩欄各自取最大值**。
##
## 刻意不是「波次高的那一局整組蓋過去」：波次與產能積分量的是兩件事
## （撐得久 vs 產線好），把它們綁成一組會讓一局「波次 +1、積分砍半」
## 洗掉玩家真正的最佳產線紀錄。回傳哪幾欄破了紀錄，讓局末面板講得出來。
##
## ★ sv3 起**逐難度層各一筆**（B2.6）：`tier` 決定寫進哪一格。
## 難度層是規則差異不是分數係數——把高層的成績乘一個倍率丟進同一張榜，
## 等於宣告「第 3 層的 8 波比第 0 層的 20 波好」，而那是一個沒有人能驗證的匯率。
static func apply_endless(d: Dictionary, wave: int, output: float, tier: int = 0) -> Dictionary:
	var e: Dictionary = d.get("endless", {})
	var all: Dictionary = e.get("best", {})
	var key := str(maxi(0, tier))
	var row: Dictionary = all.get(key, {})
	var new_wave := wave > int(row.get("wave", 0))
	var new_output := output > float(row.get("output", 0.0))
	if new_wave:
		row["wave"] = wave
	if new_output:
		row["output"] = output
	if not row.is_empty():
		all[key] = row
		e["best"] = all
	d["endless"] = e
	return {"wave": new_wave, "output": new_output}


## ★ 每日挑戰的成績（B2.2、`10_GDD.md` §3.10）。**兩欄各自取最大值**，
## 理由與 `apply_endless()` 完全相同（撐得久 vs 產線好是兩件事）。
##
## 跨日在這裡處理，不在畫面層：畫面層有兩個入口（兩張榜）而換日只該發生一次，
## 放在那裡就會出現「先點哪一榜決定昨天的紀錄有沒有被存進歷史」。
##
## ⚠ `today` 的兩榜**一起歸零**。只歸零玩的那一榜的話，昨天的另一榜會混進今天
## ——而它是在另一張圖上打出來的。
static func apply_daily(
	d: Dictionary, date: String, board: String, wave: int, output: float
) -> Dictionary:
	var day: Dictionary = d.get("daily", {})
	var today: Dictionary = day.get("today", {})
	if Daily.rolled_over(String(day.get("date", "")), date):
		var hist: Array = day.get("history", [])
		for b: String in Daily.BOARDS:
			var old: Dictionary = today.get(b, {})
			if int(old.get("wave", 0)) > 0:
				hist.push_front(Daily.entry(
					String(day["date"]), b, int(old["wave"]), float(old["output"])
				))
		while hist.size() > Daily.HISTORY_MAX:
			hist.pop_back()
		day["history"] = hist
		today = {}
	for b: String in Daily.BOARDS:
		if not today.has(b):
			today[b] = {"wave": 0, "output": 0.0}
	day["date"] = date
	var slot: Dictionary = today[board]
	var new_wave := wave > int(slot.get("wave", 0))
	var new_output := output > float(slot.get("output", 0.0))
	if new_wave:
		slot["wave"] = wave
	if new_output:
		slot["output"] = output
	day["today"] = today
	d["daily"] = day
	return {"wave": new_wave, "output": new_output}


## ★ 存一張藍圖（B2.3、`10_GDD.md` §3.7）。回傳空字串＝成功，否則是給玩家看的話。
##
## 槽數在這裡把關而不是在畫面層：畫面之後可能有第二個入口（例如局末結算
## 直接存這一局的佈局），而「槽滿了」這條規則只該有一份。
static func add_blueprint(d: Dictionary, bp: Dictionary, slot_count: int) -> String:
	if Blueprint.is_empty(bp):
		return "✕ 框選範圍內沒有可存的節點"
	var list: Array = d.get("blueprints", [])
	if list.size() >= slot_count:
		return "✕ 藍圖槽已滿（%d／%d）——先刪一張，或解鎖後勤科技" % [list.size(), slot_count]
	var copy: Dictionary = bp.duplicate(true)
	if String(copy.get("name", "")) == "":
		# 自動命名用**尺寸與節點數**，不是流水號：三個月後回來看「藍圖 3」
		# 想不起來是什麼，「4×3・7 節點」至少認得出是哪一種產線。
		var sp := Blueprint.span(copy)
		copy["name"] = "%d×%d・%d 節點" % [sp.x, sp.y, (copy["nodes"] as Array).size()]
	list.append(copy)
	d["blueprints"] = list
	return ""


## ★ 招募一隻（B2.4、`10_GDD.md` §3.9）。回傳招到的角色，空字串＝沒招成。
##
## 規則判定回頭問 `Roster`（畫面上的鈕是狀態不是規則，`Tech._unlock()` 同一條）：
## 券不夠、或已經畢業，就一張券都不扣。**畢業之後不再消耗券**是 §3.9 明文——
## 抽到重複的、或抽了個空還扣錢，都是這一條要擋的。
static func apply_recruit(d: Dictionary, rng: RandomNumberGenerator) -> String:
	if Roster.graduated(d) or Roster.tokens(d) <= 0:
		return ""
	var got := Roster.pull(d, rng)
	if got == "":
		return ""
	var r: Dictionary = d.get("roster", {})
	var list: Array = r.get("recruited", [])
	list.append(got)
	r["recruited"] = list
	d["roster"] = r
	return got


## ★ 升級材料的餘額（B2.7、`10_GDD.md` §7.15）。**推導，不存。**
##
## 三條路各自只增不減（成就是推導的、tycoon 與局末是累計欄位），花掉多少
## 則由**現在的等級**反推。所以「等級」與「材料」不可能互相矛盾——
## 這是 sv2 砍掉 `campaign.cleared`、B2.4 不存 `owned`、B2.5 不存產線佔用的同一條。
##
## 放在這裡（`Progress`）而不是 `Levels`：這一支要同時問 `Achievements` 與 `Levels`，
## 而 `Achievements` 已經 preload 了 `Levels`——寫進 `Levels` 就是一個環。
static func components(d: Dictionary) -> int:
	return maxi(0, earned_components(d) - spent_components(d))


## 一路上總共賺到多少材料（三條路，§4.1）。
static func earned_components(d: Dictionary) -> int:
	var lv: Dictionary = d.get("levels", {})
	return (
		int(lv.get("from_battle", 0))
		+ int((d.get("tycoon", {}) as Dictionary).get("components", 0))
		+ Achievements.components(d)
	)


## 已經花掉多少 ＝ 兩軸各自從 0 升到現在那一級的價錢總和。
static func spent_components(d: Dictionary) -> int:
	var sum := 0
	for axis: String in Levels.AXES:
		for i in Levels.level_of(d, axis):
			sum += Levels.cost(i)
	return sum


## ★ 局末結算的升級材料（§7.15 的第一條路）。**只數波數**。
##
## 加星數加成的話，「重刷第 1 關（3 波 3 星）」會比「打完第 5 關（5 波）」划算
## ——一條讓最短的局付最多錢的曲線是退化的。回傳這一局實得，讓結算面板講得出來。
static func apply_components(d: Dictionary, waves: int) -> int:
	var got := maxi(0, waves)
	if got <= 0:
		return 0
	var lv: Dictionary = d.get("levels", {})
	lv["from_battle"] = int(lv.get("from_battle", 0)) + got
	d["levels"] = lv
	return got


## ★ 升一級等級軸（§7.15）。回傳成功與否。
##
## 規則判定回頭問 `Levels.can_upgrade()`（`Tech._unlock()` 的同一條分工）：
## 鈕的 `disabled` 是畫面狀態不是規則。**不扣任何欄位**——花費由等級本身反推。
static func apply_level_up(d: Dictionary, axis: String) -> bool:
	if Levels.can_upgrade(d, axis, components(d)) != Levels.OK:
		return false
	var lv: Dictionary = d.get("levels", {})
	lv[axis] = Levels.level_of(d, axis) + 1
	d["levels"] = lv
	return true
