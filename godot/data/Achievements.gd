extends RefCounted
## 成就與公司等級（`10_GDD.md` §3.9、§7.15；B2.7）。**數值的唯一來源、純函式、零副作用。**
##
## ── 這一批的核心決定：成就是**推導**的，不是領取的 ──────────────────────
## 每一條成就都是「存檔上某個量 ≥ 門檻」，所以：
##   · 沒有 `claimed` 清單 → 不可能重複發放
##   · 沒有事件監聽 → 不可能漏發（B2.4 之前存的存檔照樣算得出來）
##   · 沒有第二份事實 → 不會漂
## 這是 §7.13 的券與 §7.14 的產線位佔用同一條紀律的第三次套用。
##
## ⚠ **不 preload `data/Roster.gd`**：`Roster.earned()` 要問這裡拿券
## （成就是聲望券的第四條路），反過來 preload 就是一個環。所以「名冊」那一條
## 成就看的是 `roster.recruited` 的長度，而**那個門檻等於招募池大小**這件事
## 由 `progress_test` 斷言看著（表上的數字與 `Roster.RECRUIT_POOL` 對不上就變紅）。

const CampaignData := preload("res://data/Campaign.gd")
const Tech := preload("res://data/Tech.gd")
const Levels := preload("res://data/Levels.gd")
const Difficulty := preload("res://data/Difficulty.gd")

## ★ **券只發給「沒有別的來源在數同一件事」的成就**（B2.7，`roster_test` 抓到）。
##
## `Roster.earned()` 已經把**戰役星數**與**無盡波數**換成券了。在「五關全通」
## 「滿星」「無盡五十波」上再各發一張，等於同一份進度領兩次——`roster_test`
## 當場變紅：「戰役滿星 ＝ 3 券」（§7.13 那條刻意的對齊：3 券 ＝ 剛好抽乾招募池，
## 也就是 B6 的證明）變成 5 券。
##
## 「名冊全滿」也不發券：那是**招募池已經空了**才拿得到的東西，一張用不掉的券。
## 所以只剩三條——整棵樹、兩軸滿級——它們量的都是別處沒在數的進度。
## `progress_test._achievement_table_is_consistent()` 用一條通則看著它，
## 不是只釘住這四個 id。

## 20 條（M2 的內容矩陣，§5）。
##   `metric` ＝ `metrics()` 字典裡的鍵；`need` ＝ 門檻（≥ 即達成）
##   `component` ＝ 升級材料；`token` ＝ 聲望券（大部分是 0）
##
## ★ **順序＝畫面上的順序**，由淺到深分五組（戰役／無盡／科技／公司／收藏）。
const LIST := [
	{"id": "clear1", "name": "初次通關", "metric": "cleared", "need": 1,
		"desc": "通過任何一關戰役。", "component": 20, "token": 0},
	# ★ B3.3 起這兩條的門檻與文案都由 `Campaign.count()` 推導（見 `DEFS` 下方）。
	#   寫死 5／15 的那一版在戰役加到八關的當下就變成「全通了但成就沒亮」。
	{"id": "clear_all", "name": "全關通過", "metric": "cleared", "need": -1,
		"desc": "", "component": 60, "token": 0},
	{"id": "stars_max", "name": "滿星", "metric": "stars", "need": -1,
		"desc": "", "component": 100, "token": 0},

	{"id": "wave10", "name": "無盡十波", "metric": "best_wave", "need": 10,
		"desc": "無盡撐過 10 波。", "component": 20, "token": 0},
	{"id": "wave25", "name": "無盡廿五波", "metric": "best_wave", "need": 25,
		"desc": "無盡撐過 25 波。", "component": 60, "token": 0},
	{"id": "wave50", "name": "無盡五十波", "metric": "best_wave", "need": 50,
		"desc": "無盡撐過 50 波。", "component": 150, "token": 0},
	{"id": "out20", "name": "產線成形", "metric": "best_output", "need": 20,
		"desc": "無盡的最佳產能積分達 20。", "component": 30, "token": 0},
	{"id": "out50", "name": "產線精練", "metric": "best_output", "need": 50,
		"desc": "無盡的最佳產能積分達 50。", "component": 80, "token": 0},

	{"id": "tech1", "name": "第一項科技", "metric": "tech", "need": 1,
		"desc": "解鎖任何一個科技節點。", "component": 15, "token": 0},
	{"id": "tech6", "name": "半棵樹", "metric": "tech", "need": 6,
		"desc": "解鎖 6 個科技節點。", "component": 50, "token": 0},
	{"id": "tech_all", "name": "整棵樹", "metric": "tech", "need": 12,
		"desc": "科技樹全解鎖。", "component": 120, "token": 1},

	{"id": "plant3", "name": "廠等三", "metric": "tycoon_level", "need": 3,
		"desc": "潮汐公司擴廠到 3 級。", "component": 30, "token": 0},
	{"id": "plant6", "name": "廠等六", "metric": "tycoon_level", "need": 6,
		"desc": "潮汐公司擴廠到 6 級。", "component": 80, "token": 0},
	{"id": "bulk", "name": "大宗交貨", "metric": "tycoon_tokens", "need": 3,
		"desc": "潮汐公司累計交出 3 張附券的訂單。", "component": 40, "token": 0},

	{"id": "recruit1", "name": "第一次招募", "metric": "recruited", "need": 1,
		"desc": "招募一隻稀有角色。", "component": 20, "token": 0},
	# ⚠ `need` 必須等於 `Roster.RECRUIT_POOL.size()`（`progress_test` 斷言）。
	{"id": "recruit_all", "name": "名冊全滿", "metric": "recruited", "need": 3,
		"desc": "招募池全部到手。", "component": 100, "token": 0},
	{"id": "bp1", "name": "第一張藍圖", "metric": "blueprints", "need": 1,
		"desc": "存下一張藍圖。", "component": 15, "token": 0},
	{"id": "daily1", "name": "出海一日", "metric": "daily", "need": 1,
		"desc": "打過一次每日挑戰。", "component": 20, "token": 0},

	{"id": "tower_max", "name": "塔軸滿級", "metric": "tower", "need": Levels.MAX_LEVEL,
		"desc": "塔的等級軸推到滿級。", "component": 150, "token": 1},
	{"id": "line_max", "name": "生產軸滿級", "metric": "line", "need": Levels.MAX_LEVEL,
		"desc": "生產節點的等級軸推到滿級。", "component": 150, "token": 1},
]


static func count() -> int:
	return LIST.size()


## ★ 解析過的成就列（B3.3）。**`need` 寫 −1 的那幾條由關卡數推導。**
##
## 為什麼要這一層：`clear_all`／`stars_max` 的門檻是「戰役全部通過」與
## 「戰役滿星」，而那兩個數字**跟著關卡數走**。寫死 5 與 15 的那一版，
## 在第二幕把戰役加到八關的當下就變成「八關全通了而成就沒亮」——
## 而且它會安靜地不亮，因為 5 ≤ 8 恆真、15 ≤ 24 恆真的是另一條。
##
## 文案一併推導：一條寫著「戰役五關全部通關」的成就在八關的遊戲裡是錯的字。
## `LIST` 仍然是那張表（加一條成就還是加一列），這裡只補那兩格。
static func rows() -> Array:
	var out: Array = []
	for a: Dictionary in LIST:
		out.append(resolve(a))
	return out


static func resolve(a: Dictionary) -> Dictionary:
	if int(a["need"]) >= 0:
		return a
	var r := a.duplicate(true)
	var n := CampaignData.count()
	match String(a["id"]):
		"clear_all":
			r["need"] = n
			r["desc"] = "戰役 %d 關全部通關。" % n
		"stars_max":
			r["need"] = n * 3
			r["desc"] = "戰役 %d 顆星全拿。" % (n * 3)
	return r


## ★ 存檔 → 一張「可比大小的量」的表。**全案唯一一個讀存檔算成就的地方。**
##
## 每一條成就都只是這張表上的一個比較，所以加一條成就＝加一列資料，
## 不是加一段程式碼；而加一段程式碼正是「有一條成就永遠達不成」的來歷。
static func metrics(save: Dictionary) -> Dictionary:
	var stars: Dictionary = (save.get("campaign", {}) as Dictionary).get("stars", {})
	var star_sum := 0
	var cleared := 0
	for id: String in CampaignData.ids():
		var n := int(stars.get(id, 0))
		star_sum += n
		if n >= 1:
			cleared += 1

	var endless: Dictionary = save.get("endless", {})
	var tycoon: Dictionary = save.get("tycoon", {})

	# 每日：歷史筆數 ＋ 今天已經有成績的榜數。**兩榜各算一次**——
	# 打了統一配置榜就算「打過每日」，不必兩榜都打。
	var daily: Dictionary = save.get("daily", {})
	var daily_runs := int((daily.get("history", []) as Array).size())
	for board: Variant in (daily.get("today", {}) as Dictionary).values():
		if int((board as Dictionary).get("wave", 0)) > 0:
			daily_runs += 1

	return {
		"cleared": cleared,
		"stars": star_sum,
		# ★ sv3 的形狀（B3.3 修）：`endless.best` 逐難度層一筆，取最好的那一筆。
		#   B2.6 改結構之後這兩行還在讀 `best_wave`／`best_output`，
		#   於是 wave10／wave25／wave50／out20／out50 **五條成就永遠達成不了**。
		"best_wave": int(Difficulty.best_any(save)["wave"]),
		"best_output": int(floor(float(Difficulty.best_any(save)["output"]))),
		"tech": int(((save.get("tech", {}) as Dictionary).get("unlocked", []) as Array).size()),
		"tycoon_level": int(tycoon.get("level", 1)),
		"tycoon_tokens": int(tycoon.get("tokens", 0)),
		"recruited": int(((save.get("roster", {}) as Dictionary)
			.get("recruited", []) as Array).size()),
		"blueprints": int((save.get("blueprints", []) as Array).size()),
		"daily": daily_runs,
		"tower": Levels.level_of(save, Levels.TOWER),
		"line": Levels.level_of(save, Levels.LINE),
	}


## 已達成的成就 id（順序照 `LIST`）。
static func done(save: Dictionary) -> Array[String]:
	var m := metrics(save)
	var out: Array[String] = []
	for a: Dictionary in rows():
		if int(m.get(String(a["metric"]), 0)) >= int(a["need"]):
			out.append(String(a["id"]))
	return out


## 成就一路上發出去的升級材料（**累計值**，不是餘額）。
static func components(save: Dictionary) -> int:
	return _sum(save, "component")


## ★ 成就發出去的聲望券。`Roster.earned()` 把這一支加進去（第四條路）。
static func tokens(save: Dictionary) -> int:
	return _sum(save, "token")


static func _sum(save: Dictionary, key: String) -> int:
	var got := done(save)
	var sum := 0
	for a: Dictionary in rows():
		if got.has(String(a["id"])):
			sum += int(a[key])
	return sum


# ── 公司等級（共享進度條，§7.15）─────────────────────────────────────

## 一個點數換一個等級的分母。
const COMPANY_STEP := 120

## 每一項進度值幾點。**塔防那幾項與 tycoon 那一項都在裡面**，
## 所以「兩層都推得動公司等級」是式子本身的性質，不是一句宣稱。
const COMPANY_WEIGHTS := {
	"stars": 10, "best_wave": 2, "tech": 8, "tycoon_level": 12,
}


## ★ 公司等級。**推導的，沒有自己的欄位、也不發任何獎勵。**
##
## 掛上獎勵它就變成第四套經濟（科技數據／升級材料／聲望券之外），
## 而 §3.8 的防膨脹指標擋的正是這種東西。它存在的唯一理由是彙總。
static func company_level(save: Dictionary) -> int:
	return 1 + company_points(save) / COMPANY_STEP


static func company_points(save: Dictionary) -> int:
	var m := metrics(save)
	var pts := 0
	for key: String in COMPANY_WEIGHTS:
		# 廠等從 1 起跳，所以計點要扣掉那個底——沒扣的話，一份全新的存檔
		# 會白拿 12 點，而「公司等級 1」看起來就不是從零開始的。
		var v := int(m[key]) - (1 if key == "tycoon_level" else 0)
		pts += maxi(0, v) * int(COMPANY_WEIGHTS[key])
	pts += done(save).size() * 15
	pts += (int(m["tower"]) + int(m["line"])) * 6
	return pts


## 離下一級還差幾點（進度條用）。
static func company_progress(save: Dictionary) -> Array[int]:
	var pts := company_points(save)
	return [pts % COMPANY_STEP, COMPANY_STEP]
