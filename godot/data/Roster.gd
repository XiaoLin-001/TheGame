extends RefCounted
## 名冊與招募（`10_GDD.md` §3.9、§7.13；B2.4）。**數值的唯一來源。**
## 不宣告 `class_name`，一律以路徑 preload（資料表連測試都要拿得到）。
##
## ── 這一批的核心決定：擁有清單是**推導**出來的，不是存出來的 ────────────
## 「我有哪些角色」＝「戰役開到第幾關」＋「招募過哪幾隻」。前者已經是存檔裡的
## 事實（`campaign.stars`），所以**只有招募結果需要存**。
##
## 平行存一份 `owned` 清單會有兩個事實講同一件事，而它們遲早會漂——漂掉的那天
## 玩家會看到「第 3 關通了但潮鳴還鎖著」，而兩個欄位各自都「對」。
## 這是 sv2 砍掉 `campaign.cleared` 的同一條理由（`SaveService.gd` 的註解）。

const CampaignData := preload("res://data/Campaign.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 招募池（§3.9：6 隻稀有角色；M2 的內容矩陣是 3 隻，§5）。
##
## **不重複、有畢業**：抽到的必定是尚未擁有的，抽完就不再消耗券。
## 隨機的是**順序**，不是有沒有——所以這裡不需要權重欄位，也不該有。
const RECRUIT_POOL: Array[String] = ["longcall", "frostreef", "ballast"]

## 聲望券的兩條遊玩途徑（§7.13）。**沒有第三份計數器**——見 `tokens()`。
##
## 戰役滿星 15 顆 ÷ 5 ＝ 3 券 ＝ 剛好畢業。這個對齊是刻意的：B6 說「6 隻稀有
## 角色全部都能純靠遊玩取得」，而**純戰役就能畢業**是這句話最短的證明
## （`roster_test` 直接斷言它）。無盡那條是給不想再刷星的人的第二條路。
const STAR_PER_TOKEN := 5
const WAVE_PER_TOKEN := 10


## 這名玩家擁有哪些角色（塔）。順序照 `NodeDefs.BUILDABLE`，讓建造欄不會跳動。
##
## 確定性解鎖就是**戰役的解鎖階梯本身**（§7.9）：開得到那一關，就等於擁有
## 那一關給你的那幾顆鈕。不另外寫一張「哪一關送哪一隻」的表——那張表會是
## `data/Campaign.gd` 的第二份副本，而副本會漂。
static func owned(save: Dictionary) -> Array[String]:
	var stars: Dictionary = (save.get("campaign", {}) as Dictionary).get("stars", {})
	var got: Dictionary = {}
	for i in CampaignData.open_count(stars):
		for type: String in (CampaignData.at(i) as Dictionary)["unlocked"]:
			if is_character(type):
				got[type] = true
	for type: Variant in (save.get("roster", {}) as Dictionary).get("recruited", []):
		if is_character(String(type)):
			got[String(type)] = true
	var out: Array[String] = []
	for type: String in NodeDefs.BUILDABLE:
		if got.has(type):
			out.append(type)
	return out


## 這一局蓋得出哪些節點＝生產節點全部 ＋ 擁有的角色。
##
## ⚠ **只給無盡與每日自由配置榜用**。戰役各關的建造欄由關卡自己宣告（§7.9）
## ——那是難度階梯，用名冊去交集它會讓「通關第 4 關卻蓋不出碎浪」變成可能，
## 而那一關的參考解需要它。統一配置榜走 `Daily.UNIFORM_BUILD`（§7.11）。
static func buildable(save: Dictionary) -> Array[String]:
	var own := owned(save)
	var out: Array[String] = []
	for type: String in NodeDefs.BUILDABLE:
		if not is_character(type) or own.has(type):
			out.append(type)
	return out


## 角色＝塔（§3.4「塔＝角色」）。生產節點不是角色，不進名冊。
static func is_character(type: String) -> bool:
	return bool(NodeDefs.of(type).get("tower", false))


## 全部角色，圖鑑的顯示順序。
static func all() -> Array[String]:
	var out: Array[String] = []
	for type: String in NodeDefs.BUILDABLE:
		if is_character(type):
			out.append(type)
	return out


## 已招募的（存檔裡唯一需要存的那一份）。
static func recruited(save: Dictionary) -> Array:
	return (save.get("roster", {}) as Dictionary).get("recruited", [])


## 還沒收集到的稀有角色數。**UI 常駐顯示這個數字**（§3.9 DoD）——
## 「還剩 2 隻」是一個看得到終點的進度條，「稀有度 3%」是一個沒有終點的賭局。
static func remaining(save: Dictionary) -> int:
	return RECRUIT_POOL.size() - _pool_owned(save).size()


## 畢業了嗎？畢業之後招募鈕不再消耗券（§3.9）。
static func graduated(save: Dictionary) -> bool:
	return remaining(save) <= 0


## 一路上總共賺到幾張聲望券。**里程碑，不是掉落**：玩家看得到「再 2 顆星就有券」。
##
## ★ **第三條路是潮汐公司**（B2.5）：第 4 階起的訂單各附一張券。
##   它是**加法**不是替代——`roster_test._free_to_play_can_graduate()` 仍然斷言
##   「純戰役滿星就能畢業」，所以 tycoon 只是讓不想再刷星的人多一條路，
##   不是把畢業綁到掛機上（憲法 B6：所有東西都能純靠遊玩取得）。
static func earned(save: Dictionary) -> int:
	var stars: Dictionary = (save.get("campaign", {}) as Dictionary).get("stars", {})
	var total := 0
	for id: String in CampaignData.ids():
		total += int(stars.get(id, 0))
	var best_wave := int((save.get("endless", {}) as Dictionary).get("best_wave", 0))
	var from_tycoon := int((save.get("tycoon", {}) as Dictionary).get("tokens", 0))
	return total / STAR_PER_TOKEN + best_wave / WAVE_PER_TOKEN + from_tycoon


## 手上還有幾張券 ＝ 賺到的 − 花掉的。
##
## ★ **刻意不存一個計數器**。券只有一種用途（招募），而招募結果本來就要存，
## 所以「花掉幾張」是可推導的。存一份會漂，而漂掉的那天玩家看到的是
## 「我有 2 張券但只招募過 1 次」——沒有任何畫面說得清那是誰對。
##
## （§3.12 的付費購買券會需要一個真的計數器，那是 M4 的事；到時候加的是
## `roster.bought` 一個鍵，這支函式加一項，推導的部分不變。）
static func tokens(save: Dictionary) -> int:
	return maxi(0, earned(save) - _pool_owned(save).size())


## 抽一隻。**回傳的必定是尚未擁有的稀有角色**（§3.9：隨機的是順序不是有沒有）。
## 池空了回空字串——呼叫端要先問 `graduated()`，這裡只是不讓它爆。
##
## `rng` 由呼叫端注入（`Rng.stream()`），不碰全域狀態：測試要能斷言
## 「同一個種子抽出同一個順序」，而那是「不重複」唯一驗得起來的方式。
static func pull(save: Dictionary, rng: RandomNumberGenerator) -> String:
	var have := _pool_owned(save)
	var left: Array[String] = []
	for type: String in RECRUIT_POOL:
		if not have.has(type):
			left.append(type)
	if left.is_empty():
		return ""
	return left[rng.randi() % left.size()]


## 招募池裡已經到手的那幾隻。
##
## ⚠ 問的是 `owned()` 而不是 `recruited`：稀有角色**日後也可能由別的途徑給出**
## （§3.9 的成就、商店直購）。只看 `recruited` 的話，一隻由成就送的角色會讓
## 「還剩 N 隻」永遠少不掉一格，而抽卡還會把它再抽一次。
static func _pool_owned(save: Dictionary) -> Array[String]:
	var own := owned(save)
	var out: Array[String] = []
	for type: String in RECRUIT_POOL:
		if own.has(type):
			out.append(type)
	return out


## 這隻角色怎麼拿到手（圖鑑上寫在鎖住的卡片上）。
##
## **鎖住要說清楚條件**，一個沒有下文的灰色方塊會讓玩家以為是壞掉了
## （`Campaign.gd` 卡片的同一條）。
static func unlock_hint(type: String) -> String:
	if RECRUIT_POOL.has(type):
		return "招募取得"
	for i in CampaignData.count():
		if ((CampaignData.at(i) as Dictionary)["unlocked"] as Array).has(type):
			if i <= 0:
				return "開局即有"
			return "通過第 %d 關" % i
	return "尚未開放"
