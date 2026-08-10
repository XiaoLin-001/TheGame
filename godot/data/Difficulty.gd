extends RefCounted
## 難度層（`10_GDD.md` §3.11、§7.16；B2.6）。**前 3 層**，§5 內容矩陣的 M3 目標是 12。
##
## 和 `Tech`／`Levels` 一樣是**一張表 ＋ 讀它的函式**：純函式、零副作用、零 RNG
## （`CLAUDE.md`「`data/` 與 `scripts/meta/` 的分界」——加一層是加一列）。
##
## ── 這張表為什麼存在 ───────────────────────────────────────────────
## 憲法 B2 ② 的硬性配套：等級軸滿級 **×1.80** 是**可以課金加速**的那一軸，
## 「必須被難度層同步吃掉」。所以第 3 層的敵人血量倍率**就是 1.80**——
## 它不是一個調出來好看的數字，是等級軸滿級的鏡像（`_calibrated_to_max_level()`
## 在 `difficulty_test` 裡逐位元比對這兩個數，任一邊動了另一邊就變紅）。
##
## 買到滿級換到的是「打得動第 3 層」，不是「把第 0 層碾平」。
##
## ── 每層加一條新規則 ──────────────────────────────────────────────
## 血量 → 破壞速度 → 耗能。三條打的是三件不同的事（塔夠不夠、線撐不撐得住、
## 電夠不夠），**一次只多一條**玩家才說得出自己卡在哪一關口。
## 一層同時多三條的話，「這層難」會是唯一的心得。
##
## ⚠ **血量是校準軸，每一層都動**（它是等級軸的鏡像，見上）。所以「第 N 層有
## N 條規則」數的是 `rules`，而第 1 層那一條就是血量本身。
##
## ⚠ **準備期不在這裡**：§7.1 的 `PREP_TIME_HARD`（30 秒）明文屬於難度層 4+。

const Levels := preload("res://data/Levels.gd")
const Campaign := preload("res://data/Campaign.gd")

## 本批做到第幾層（0 ＝ 標準）。`TIERS` 的長度就是它 ＋1。
const MAX_TIER := 3

## 解鎖下一層的門檻：在上一層撐過幾波。
##
## 10 波是「這一層我已經站穩了」而不是「我試過一次」——無盡的血量曲線
## `1.11^(w-1)`（§7.10）在第 10 波是 ×2.56，那時能不能站住已經是產線的問題。
const UNLOCK_WAVE := 10

## ★ 三個倍率都乘在**同一個 `mods` 字典**上（`Tech.NO_MODS` 的骨架）。
## 不另開一條「難度參數」的傳遞路徑：模擬層已經有一個吃 `mods` 的入口，
## 第二條路徑的代價是每個讀取端都要記得問兩個地方。
const TIERS := [
	{
		# 規則列刻意是**空的**，不是一句「沒有額外規則」：`rules` 的長度就是
		# 「這一層疊了幾條」，塞一句佔位的話那個等式當場失效（畫面自己會補這句話）。
		"name": "標準", "enemy_hp": 1.00, "enemy_damage": 1.00, "engage": 1.00,
		"rules": [],
	},
	{
		"name": "漲潮", "enemy_hp": 1.25, "enemy_damage": 1.00, "engage": 1.00,
		"rules": ["敵人血量 ×1.25"],
	},
	{
		"name": "暴潮", "enemy_hp": 1.50, "enemy_damage": 1.50, "engage": 1.00,
		"rules": ["敵人血量 ×1.50", "敵人破壞建築 ×1.50"],
	},
	{
		"name": "深潮", "enemy_hp": 1.80, "enemy_damage": 1.50, "engage": 1.20,
		"rules": ["敵人血量 ×1.80", "敵人破壞建築 ×1.50", "塔交戰耗能 ×1.20"],
	},
]


static func count() -> int:
	return TIERS.size()


## 第 `tier` 層。**越界一律夾回範圍內**——難度層會被存檔與畫面各讀一次，
## 回一個空字典等於讓「存檔裡有個 7」變成一局沒有任何倍率的遊戲。
static func of(tier: int) -> Dictionary:
	return TIERS[clampi(tier, 0, MAX_TIER)]


static func name_of(tier: int) -> String:
	return "第 %d 層　%s" % [clampi(tier, 0, MAX_TIER), String(of(tier)["name"])]


static func rules_of(tier: int) -> Array:
	return of(tier)["rules"]


## ★ 難度層 → `mods`（`Tech.NO_MODS` 的骨架）。**原地變更並回傳**，同 `Levels.apply()`。
##
## `engage_mult` 用的是既有的那一格：科技的「能量效率」降它、難度層抬它，
## 兩者連乘。多開一個 `difficulty_engage` 只會讓耗能的讀取端要乘兩次。
static func apply(mods: Dictionary, tier: int) -> Dictionary:
	var d := of(tier)
	mods["engage_mult"] = float(mods.get("engage_mult", 1.0)) * float(d["engage"])
	mods["enemy_hp_mult"] = float(mods.get("enemy_hp_mult", 1.0)) * float(d["enemy_hp"])
	mods["enemy_damage_mult"] = (
		float(mods.get("enemy_damage_mult", 1.0)) * float(d["enemy_damage"])
	)
	return mods


# ── 解鎖與紀錄（推導，不存） ──────────────────────────────────────────

## 這份存檔的無盡個人最佳。`{wave, output}`，沒打過就是 0/0。
##
## sv3 起紀錄**逐層各一筆**（`SaveService` 的說明）：同一個「12 波」在標準層
## 與深潮層不是同一件事，共用一格會讓其中一個永遠洗不掉另一個。
static func best(save: Dictionary, tier: int) -> Dictionary:
	var all: Dictionary = (save.get("endless", {}) as Dictionary).get("best", {})
	var row: Dictionary = all.get(str(clampi(tier, 0, MAX_TIER)), {})
	return {"wave": int(row.get("wave", 0)), "output": float(row.get("output", 0.0))}


## ★ 解鎖到第幾層。**推導的**（sv2 砍 `campaign.cleared`、B2.4 不存 `owned`、
## B2.5 不存產線佔用、B2.7 不存材料餘額的同一條）——存一份「已解鎖到第 N 層」
## 就是讓同一個事實有兩個版本，而漂掉的那天玩家看到的是「紀錄在第 2 層、
## 但第 2 層是鎖著的」。
##
## 規則（§3.11「通關戰役後解鎖，逐層疊加」）：
##   · 第 1 層：**戰役全通**（每一關至少 1 星）
##   · 第 N 層：在第 N−1 層撐過 `UNLOCK_WAVE` 波
static func unlocked(save: Dictionary) -> int:
	if not campaign_cleared(save):
		return 0
	var top := 1
	while top < MAX_TIER and int(best(save, top)["wave"]) >= UNLOCK_WAVE:
		top += 1
	return top


## 戰役每一關都至少 1 星。**問的是全部關卡**，不是 `open_count()`——
## 後者回答的是「第幾關可以點」，而最後一關可以點的時候它還沒被打過。
static func campaign_cleared(save: Dictionary) -> bool:
	var stars: Dictionary = (save.get("campaign", {}) as Dictionary).get("stars", {})
	for id: String in Campaign.ids():
		if int(stars.get(id, 0)) < 1:
			return false
	return true


## 鎖著的話，要做什麼才開得了。**空字串＝沒鎖。**
## 一個沒有下文的灰色方塊會讓玩家以為是壞掉了（`screens/Campaign.gd` 同一條）。
static func why_locked(save: Dictionary, tier: int) -> String:
	if tier <= unlocked(save):
		return ""
	if not campaign_cleared(save):
		return "先通關戰役全部 %d 關" % Campaign.count()
	return "先在%s撐過 %d 波" % [name_of(tier - 1), UNLOCK_WAVE]
