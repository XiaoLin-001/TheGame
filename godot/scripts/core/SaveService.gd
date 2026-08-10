extends Node
## 存檔（autoload）。規格：30_TECH_DESIGN.md §3。
##
## 三條承諾：
##   1. **只增不破**——新欄位給預設值，結構改動寫遷移分支。上線後破壞存檔＝事故。
##   2. **有測試鉤子時不落地**（§4.1 鐵律 1）——測試絕不寫壞使用者的真實存檔。
##   3. **原子寫入**——寫 .tmp → 讀回驗證 → 改名，避免半寫的檔案毀掉進度。
##
## 純邏輯（defaults／migrate／normalize）一律寫成 **static**，因為 `tests/*.gd`
## 以 `--script` 執行時不載入 autoload，只能 preload 這個檔案呼叫靜態函式（§4.2）。

const Score := preload("res://scripts/sim/Score.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Roster := preload("res://data/Roster.gd")
const Levels := preload("res://data/Levels.gd")
const Achievements := preload("res://data/Achievements.gd")

## sv2（B1.4）：`campaign.cleared` 移除，改由 `campaign.stars` 推導。
## sv3（B2.6）：`endless.best_wave`／`best_output` 收進 `endless.best`（逐難度層一筆）。
const SAVE_VERSION := 3

const PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"

## ★ 可選的視窗尺寸。**放在 schema 旁邊**：存檔存的是這個陣列的**索引**，
## 兩者不在同一個檔案的那一天，刪掉一個選項就會留下一個選不到也顯示不出來的值。
## 全部 16:9——版面基準是 1280×720，`stretch/aspect=expand` 在別的長寬比下
## 會讓框架與地圖的比例對不上。
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

## 完整 schema 骨架。**讀取一律走 normalize()**，任何缺失欄位都由此補上安全預設。
## ★ **只列真的有讀取端的欄位**（B1.9）。
##
## 這裡曾經有八個沒有任何人讀的頂層鍵（`company_level` `roster` `endless`
## `daily` `tycoon` `levels` `entitlements` `blueprints`），讓 schema 看起來
## 比實作大四倍。**提前宣告買不到任何相容性**：`_fill_defaults()` 本來就在
## 讀檔時補缺鍵，所以功能落地那一批直接加上那一個鍵，舊存檔照樣讀得進來。
##
## 反過來，提前宣告有真的代價：每一個空殼鍵都會被寫進玩家的存檔檔案，
## 而看到 `"tycoon": {...}` 的人會以為那個系統已經在跑了。
const DEFAULTS := {
	"sv": SAVE_VERSION,
	"tech": {"unlocked": [], "data": 0},
	# ★ sv2 起**沒有 `cleared`**：它和 `stars` 講的是同一件事（`stars[id] >= 1`），
	# 而同一個事實存兩份遲早會漂移——漂掉的那一天，玩家會看到「這一關通關了
	# 但下一關還鎖著」，而兩個欄位各自都「對」。
	"campaign": {"stars": {}},
	# ★ B2.1a 落地、B2.6 改結構（sv3）。`best` 的鍵是**難度層的字串**（"0".."3"），
	# 值是 `{wave, output}`。改結構而不是在旁邊加一格「高難度的紀錄」：
	# 同一個「12 波」在標準層與深潮層不是同一件事，共用一格會讓其中一個
	# 永遠洗不掉另一個（而玩家兩邊都覺得自己那筆才對）。
	#
	# 鍵是字串不是整數：這一格要進 JSON，而 JSON 的物件鍵本來就只有字串
	# ——存成整數的話，寫進去是 3、讀回來是 "3"，查表當場落空。
	"endless": {"best": {}},
	# ★ B2.2 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（理由同上：加鍵不是結構改動）。
	# `date` ＝ `today` 那兩榜屬於哪一天；跨日時 `apply_daily()` 會把它推進 `history`。
	"daily": {
		"date": "",
		"today": {"uniform": {"wave": 0, "output": 0.0}, "free": {"wave": 0, "output": 0.0}},
		"history": [],
	},
	# `resolution` 是 `RESOLUTIONS` 的索引，不是像素——存像素的話，
	# 日後刪掉一個選項就會出現一個選不到、也顯示不出來的設定值。
	# ★ B2.3 落地的鍵。藍圖的座標是 `[dx, dy]` 整數陣列（`sim/Blueprint.gd`
	# 的說明）——**全部是 JSON 原生型別**，所以這一格存進去讀出來就是原樣，
	# 不需要任何序列化程式碼。
	"blueprints": [],
	# ★ B2.4 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# 只有 `recruited` 一格。「擁有哪些角色」與「還有幾張券」**都是推導出來的**
	# （`data/Roster.gd` 的說明）——存進來的每一份平行事實都會漂，而漂掉的那天
	# 玩家會看到「第 3 關通了但潮鳴還鎖著」，兩邊各自都「對」。
	"roster": {"recruited": []},
	# ★ B2.5 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# `orders` 的每一筆是 `{tier, done, line}`，`line` ＝ 第幾格產線位（−1 ＝ 沒上線）。
	# **「哪一格產線位被佔著」是推導的**（`TycoonSim.order_on_line()`）——存一份
	# slots 陣列等於讓同一個事實有兩個版本，而收成一張訂單會讓後面每個索引位移。
	#
	# `last_seen` ＝ Unix 秒，離線結算的基準（`TycoonSim.settle()`）。
	# 0 ＝ 從沒開過公司，**不結算**（否則會把 1970 年到現在整段算進去）。
	"tycoon": {
		"level": 1, "credits": 0, "components": 0, "tokens": 0,
		"last_seen": 0, "orders": [],
	},
	# ★ B2.7 落地的鍵。同樣**沒有 bump `SAVE_VERSION`**（加鍵不是結構改動）。
	#
	# 只有三格，而且**沒有一格是「我還剩多少材料」**：餘額是推導的
	# （`components()`）。存餘額的話，等級與材料會變成兩個各自可以「對」的事實，
	# 而漂掉的那天玩家看到的是「我 10 級但材料只花了三級的錢」。
	# `from_battle` ＝ 局末結算的**累計**（只增），`tower`／`line` 反推花掉多少。
	"levels": {"tower": 0, "line": 0, "from_battle": 0},
	"settings": {
		"master": 0.8, "bgm": 0.6, "sfx": 0.8,
		"reduce_motion": false, "fullscreen": false, "resolution": 0,
	},
}

## 有任何 TL_* 鉤子時為 false。直接由 Env 靜態判定，不依賴其他 autoload 的 _ready 順序。
var persist: bool = not Env.any_hook()

## ★ 這個實例讀寫哪一個檔（B2.8）。預設就是上面那兩個常數，**玩家的路徑一個字都沒變**。
##
## 為什麼要能換：磁碟往返（原子寫入 → 讀回 → 改名）是「只增不破」唯一的自動化覆蓋，
## 而它原本**在任何已經有存檔的機器上整段跳過**——也就是我的機器與使用者的機器。
## 那條測試從 B0.1 起就一直印著「待補」，等於這條路徑從來沒有被真的跑過（RG-160）。
var path: String = PATH
var tmp_path: String = TMP_PATH


# ─────────────────────────────────────────────────────────────
# 純邏輯（static；測試直接呼叫，不需要 autoload）
# ─────────────────────────────────────────────────────────────

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## 把任意（可能殘缺、可能舊版）的資料整理成當前 schema 的完整資料。
## 順序很重要：先遷移舊結構，再補預設值——反過來會讓遷移看到假的預設欄位。
##
## ★ B2.8 在**遷移之前**多一步 `_repair_containers()`（RG-159）。順序仍然是
## 「修型別 → 遷移 → 補預設」：`_fill_defaults()` 只補**缺的鍵**，它不會修一個
## 型別錯掉的鍵，而遷移分支與所有讀取端都假設 `campaign` 是字典、`endless` 是字典。
## 一個 `"campaign": 5` 的檔於是會在整個局外層噴一整串型別錯誤（實測 14 條）。
static func normalize(raw: Dictionary) -> Dictionary:
	var d := raw.duplicate(true)
	_repair_containers(d, DEFAULTS)
	d = migrate(d)
	_fill_defaults(d, DEFAULTS)
	d["sv"] = SAVE_VERSION
	return d


## ★ 型別修復（B2.8、RG-159）。**只修容器與非容器不合的那些鍵，不補任何缺鍵。**
##
## 為什麼只看「是不是容器」而不是嚴格比對型別：**JSON 沒有整數**。
## `"data": 12` 存進去讀出來是 `12.0`，嚴格比對會把玩家的研究數據當成壞資料清掉。
## 純量之間的差異由讀取端既有的 `int()`／`float()` 轉換吸收，那條路本來就通；
## 真正會炸的是「該是字典的地方放著一個數字」——那種值沒有任何轉換救得回來。
##
## 補缺鍵留給 `_fill_defaults()`（它在遷移之後跑）：在這裡補的話，遷移分支會看到
## 一堆它那個版本還不存在的欄位，那正是 `normalize()` 的順序註解在講的事。
static func _repair_containers(target: Dictionary, defs: Dictionary) -> void:
	for k: String in defs.keys():
		if not target.has(k):
			continue
		var dv: Variant = defs[k]
		var tv: Variant = target[k]
		if dv is Dictionary:
			if tv is Dictionary:
				_repair_containers(tv, dv)
			else:
				target[k] = (dv as Dictionary).duplicate(true)
		elif dv is Array:
			if not (tv is Array):
				target[k] = (dv as Array).duplicate(true)
		elif tv is Dictionary or tv is Array:
			target[k] = dv


## ★ 鏈式套用版本遷移（B1.4 起真的有分支了）。
##
## **一次跳一版，不寫「從任何版本直達最新」的捷徑**：捷徑要在每加一版時
## 重寫一次全部組合，而漏掉的那一格是玩家的存檔。
##
## 沒有 `sv` 的檔一律當成 1——那是首版出貨時的形狀，不是「壞檔」。
static func migrate(d: Dictionary) -> Dictionary:
	var sv := int(d.get("sv", 1))
	while sv < SAVE_VERSION:
		match sv:
			1: _migrate_sv1_to_sv2(d)
			2: _migrate_sv2_to_sv3(d)
		sv += 1
	d["sv"] = SAVE_VERSION
	return d


## sv1 → sv2：`campaign.cleared` 併進 `campaign.stars`。
##
## 舊檔裡可能有「在 cleared 裡、但 stars 沒有記錄」的關（理論上不該發生，
## 但存檔遷移**不能假設舊資料是自洽的**）——那種一律補成 1 星，
## 因為 cleared 唯一的意思就是「至少通關過一次」。
static func _migrate_sv1_to_sv2(d: Dictionary) -> void:
	var campaign: Dictionary = d.get("campaign", {})
	if not campaign.has("cleared"):
		return
	var stars: Dictionary = campaign.get("stars", {})
	for id: Variant in campaign["cleared"]:
		stars[String(id)] = maxi(1, int(stars.get(String(id), 0)))
	campaign["stars"] = stars
	campaign.erase("cleared")


## sv2 → sv3：無盡的個人最佳收進 `endless.best`，鍵是難度層（B2.6、§7.16）。
##
## 舊檔的那一筆**一律記在第 0 層**——它是在還沒有難度層的世界裡打出來的，
## 而第 0 層就是那個世界的規則。丟掉它會讓玩家開遊戲第一件事是看到紀錄歸零。
##
## 兩欄都是 0 就不建那一格：一個 `{"0": {"wave": 0, "output": 0.0}}` 會讓
## 「從沒玩過無盡」看起來像「打過但 0 波」。
static func _migrate_sv2_to_sv3(d: Dictionary) -> void:
	var e: Dictionary = d.get("endless", {})
	if not e.has("best_wave") and not e.has("best_output"):
		return
	var wave := int(e.get("best_wave", 0))
	var output := float(e.get("best_output", 0.0))
	e.erase("best_wave")
	e.erase("best_output")
	if wave > 0 or output > 0.0:
		var best: Dictionary = e.get("best", {})
		best["0"] = {"wave": wave, "output": output}
		e["best"] = best
	d["endless"] = e


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
## 放在 `SaveService` 而不是 `Levels`：這一支要同時問 `Achievements` 與 `Levels`，
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


## 遞迴補預設值：defaults 有而 target 沒有的鍵才補；兩邊都是 Dictionary 就往下走。
## **不覆蓋已存在的值**——玩家的資料永遠優先。
static func _fill_defaults(target: Dictionary, defs: Dictionary) -> void:
	for k: String in defs.keys():
		var dv: Variant = defs[k]
		if not target.has(k):
			target[k] = dv.duplicate(true) if dv is Dictionary or dv is Array else dv
		elif dv is Dictionary and target[k] is Dictionary:
			_fill_defaults(target[k], dv)


# ─────────────────────────────────────────────────────────────
# 落地（instance；需要檔案系統）
# ─────────────────────────────────────────────────────────────

## 讀檔並**原地**填入 target，維持所有既有引用有效（§2.3）。
##
## ★ **有測試鉤子時連「讀」都不讀真存檔**（B1.2.2）。原本只擋寫入，於是
## 任何 `TL_*` 跑出來的畫面都會跟著這台機器上玩家的進度變——`TL_SHOT`
## 「同參數在任何機器上拍出同一張圖」那句保證，在關卡選擇畫面上是假的
## （已通關幾關就長不一樣），而 `TL_CLICKTEST` 對「第 2 關是鎖著的」
## 這種斷言會在玩過的機器上無故變紅。鉤子在兩個方向上都該是空操作。
func load_into(target: Dictionary) -> void:
	var loaded := normalize({} if not persist else _read_raw())
	target.clear()
	target.merge(loaded, true)


func save_from(source: Dictionary) -> bool:
	if not persist:
		print("[TL] save skipped（有測試鉤子）")
		return true
	return _write_atomic(normalize(source))


func _read_raw() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("存檔開啟失敗 err=%d，改用預設值" % FileAccess.get_open_error())
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("存檔內容不是合法 JSON 物件，改用預設值")
	return {}


## 寫 .tmp → 讀回驗證 → 換掉主檔。中途失敗時主檔完好如初。
func _write_atomic(d: Dictionary) -> bool:
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("暫存檔寫入失敗 err=%d" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

	# 驗證：讀不回來就不要動主檔。
	var check := FileAccess.open(tmp_path, FileAccess.READ)
	if check == null or not (JSON.parse_string(check.get_as_text()) is Dictionary):
		if check != null:
			check.close()
		push_error("暫存檔驗證失敗，保留原存檔不動")
		return false
	check.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("user:// 開啟失敗")
		return false
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	var err := dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("存檔改名失敗 err=%d" % err)
		return false
	return true
