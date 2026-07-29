extends RefCounted
## 手作地圖資料（`10_GDD.md` §7.3 地圖元素）。不宣告 `class_name`，一律 preload。

const Enemies := preload("res://data/Enemies.gd")
##
## **戰役關卡硬性一屏可見**（`CLAUDE.md`）：36×19 格 × 32px = 1152×608，
## 放進 1280×720 的設計基準還剩邊界給浮層。B0.3 只需要一張測試圖，
## 戰役的 5 關在 B1.2、程序生成在 B2.1。
##
## 難度只能用**玩家看得見的關卡參數**表達（§7.7）：礦點分佈、核心距離、
## 跨越點座數、起始礦砂、準備期。這裡沒有任何隱藏係數。

## 測試圖「淺灘 Shoal」。
##
## 敵潮從左緣沿 y=4 東行，在 x=30 轉南，於 y=14 折東抵達核心 (34,14)。
## 三座跨越點：兩座在橫段、一座在縱段——**礦點刻意分佈在路徑兩側**，
## 北岸的礦要入帳就非得過橋不可（橋上導管不受攻擊，是可規劃的安全動線）。
const SHOAL := {
	"id": "shoal",
	"name": "淺灘",
	"size": Vector2i(36, 19),
	"core": Vector2i(34, 14),
	# 轉折點，最後一點必為核心。展開規則見 `path_of()`。
	"waypoints": [Vector2i(0, 4), Vector2i(30, 4), Vector2i(30, 14), Vector2i(34, 14)],
	"waves": Enemies.SHOAL_WAVES,
	# 測試圖給得寬鬆：示範佈局要能一口氣蓋出「礦砂線 ＋ 電網 ＋ 四隻塔 ＋ 加粗幹線」
	# 整套，否則驗證不了核心取捨。B0.5 由 300 調高到 1400（示範佈局要 1291）。
	# 真正吃緊的起始礦砂是關卡設計的事（B0.7 手作圖、B1.2 戰役五關）。
	"start_ore": 1400,
	"prep_time": 60.0,  # PREP_TIME_TUTORIAL（§7.1）
	"crossings": [Vector2i(10, 4), Vector2i(22, 4), Vector2i(30, 9)],
	"ore": [
		Vector2i(5, 1), Vector2i(14, 1),    # 北岸：要過橋才入得了帳
		Vector2i(7, 10), Vector2i(16, 8), Vector2i(12, 15), Vector2i(25, 12),
	],
}


## 示範佈局：一組建造指令，`TL_PANEL=battle` 的截圖與 `TL_SIM` 的 headless
## 跑局共用同一份——**兩條驗證路徑看的必須是同一個局面**，否則截圖證明不了數字。
##
## 它蓋出 B0.3–B0.5 要證明的三件事：
##   ① 礦砂線：採集器 →（45°）→ 中繼 →（過橋 30,9）→ 中繼 → 中繼 → 核心。
##      東岸的核心只能經跨越點抵達——這條線就是「產線往危險方向拉」的字面樣子。
##   ② 能量線：採集器 → 發電機 → 儲槽。**發電機輸出 20 塞不進 cap 10**，
##      那條線立刻滿載變亮（`10_GDD.md` §7.2）。
##   ③ ★ 核心取捨（B0.5）：四隻塔全部掛在同一個電網上。**一台發電機 20/秒，
##      四座塔交戰時要 40/秒**——波次一開打，儲槽開始放電、塔的射速掉到約
##      七成五。這是「同一份能量，餵塔還是餵生產線」第一次真的成立。
##
##   塔的擺位本身就是三道題：
##     稜鏡 (33,4) 與橫段路徑**同一列** → 一次貫穿整段（§7.4 的對齊謎題）
##     回收者 (28,6) 蹲在稜鏡的擊殺點上，**不是它自己射得最爽的地方**（§3.3）
##     潮鳴 (28,12) 與錨 (32,12) 守南段，全部退開路徑 2 格 → walk-by 打不到
## 示範佈局要花掉的合金（五條幹線升到 2/3 級，§7.2 的新造價）。
##
## ★ **這不是關卡參數。** 玩家在「淺灘」開局的合金是 0——第一塊合金一律得
## 自己蓋熔爐煉。這個常數只給示範佈局用：示範佈局本來就代表一個「已經跑了
## 好幾分鐘」的中盤局面（四座塔、五條加粗幹線），發它那段時間本來就會產出的
## 合金，和 `start_ore` 1400 給的是同一種便利，不是難度上的隱藏係數。
##
## 五個呼叫端（截圖、`TL_SIM`、determinism、hud、`Battle` 的 demo）都要先發，
## **忘了發的那一條路徑會靜靜地少掉三級加粗**——畫面上一切正常，幹線卻是細的。
const DEMO_ALLOY := 300.0

const SHOAL_DEMO := [
	# ① 東岸礦線：採集器 →（45°）→ 中繼 →（過橋 30,9）→ 中繼 → 中繼 → 核心
	["place", "relay", Vector2i(28, 9)],
	["place", "relay", Vector2i(33, 9)],
	["place", "relay", Vector2i(33, 13)],
	["place", "extractor", Vector2i(25, 12)],
	["conduit", Vector2i(25, 12), Vector2i(28, 9)],
	["conduit", Vector2i(28, 9), Vector2i(33, 9)],
	["conduit", Vector2i(33, 9), Vector2i(33, 13)],
	["conduit", Vector2i(33, 13), Vector2i(34, 14)],

	# ② 西岸電廠：採集器 → 發電機 →（加粗 ×2）→ 幹線中繼
	#    基礎 cap 10 塞不下發電機的 20，所以這一段一定要加粗（§7.2）。
	["place", "extractor", Vector2i(16, 8)],
	["place", "generator", Vector2i(16, 11)],
	["conduit", Vector2i(16, 8), Vector2i(16, 11)],
	["place", "relay", Vector2i(20, 15)],
	["conduit", Vector2i(16, 11), Vector2i(20, 15)],
	["upgrade", Vector2i(16, 11), Vector2i(20, 15), 2],

	# ③ 儲槽掛在幹線旁的**支線**上，不在幹線上。
	#    它的充放電速率＝它自己那條線的 cap（§3.1），支線維持基礎 10：
	#    所以波次期它只補得上 10/秒——這正是 §7.4 那張表裡「儲槽線需要加粗」
	#    的情境，玩家在畫面上會看到這條支線滿載。
	["place", "silo", Vector2i(20, 17)],
	["conduit", Vector2i(20, 15), Vector2i(20, 17)],

	# ④ 幹線東送，加粗到頂（28）：**瓶頸要落在發電量上，不是管子上**
	["place", "relay", Vector2i(26, 9)],
	["conduit", Vector2i(20, 15), Vector2i(26, 9)],
	["upgrade", Vector2i(20, 15), Vector2i(26, 9), 3],
	["conduit", Vector2i(26, 9), Vector2i(28, 9)],
	["upgrade", Vector2i(26, 9), Vector2i(28, 9), 3],
	["upgrade", Vector2i(28, 9), Vector2i(33, 9), 3],

	# ⑤ 四隻塔。擺位本身就是三道題：
	#    稜鏡 (33,4) 與橫段路徑**同一列** → 一次貫穿整段（§7.4 的對齊謎題）
	#    回收者 (28,6) 蹲在稜鏡的擊殺點上，**不是它自己射得最爽的地方**（§3.3）
	#    全部退開路徑 2 格 → walk-by 打不到（§3.5）
	["place", "reclaimer", Vector2i(28, 6)],
	["conduit", Vector2i(28, 6), Vector2i(28, 9)],
	["place", "knell", Vector2i(28, 12)],
	["conduit", Vector2i(28, 12), Vector2i(28, 9)],
	["place", "anchor", Vector2i(32, 12)],
	["conduit", Vector2i(32, 12), Vector2i(33, 13)],
	["place", "prism", Vector2i(33, 4)],
	["conduit", Vector2i(33, 4), Vector2i(33, 9)],
	["upgrade", Vector2i(33, 4), Vector2i(33, 9), 3],  # 一座稜鏡就要 20/秒
]


## ★ 沙盤「靜水」（B1.1）。**沒有敵人路徑、沒有波次**——`path_of()` 只認得
## `shoal`，其他 id 一律回空路徑，所以這張圖上只剩物流本身。
##
## 它存在的理由有兩個，兩個都是驗證用：
##   ① `flow_test` 要一個「三種資源同時在跑」的局面，而在淺灘上手刻一條
##      過橋礦線只會刻出第二份會過期的地圖知識。
##   ② **合金流動珠的顏色需要一張圖才證明得了**（R-3）。淺灘的示範佈局沒有
##      熔爐，所以合金那一列珠子在任何既有截圖裡都不會出現。
##      `TL_PANEL=sandbox` 拍的就是這張。
const SANDBOX := {
	"id": "sandbox",
	"name": "靜水",
	"size": Vector2i(20, 16),
	"core": Vector2i(10, 10),
	"start_ore": 9999,
	"prep_time": 600.0,   # 沒有波次表，倒數只是為了不要立刻判「通關」
	"crossings": [],
	"ore": [Vector2i(2, 2), Vector2i(2, 3)],
}

## 沙盤佈局：一座三路都接好的熔爐。
##
##   (2,2)採集器 ─┬─ (6,2)發電機 ──45°── (2,6)熔爐 ── (6,6)中繼 ──45°── (10,10)核心
##   (2,3)採集器 ─┘
##
## 兩台採集器 12 礦砂/秒 ＝ 發電機 4 ＋ 熔爐 8，剛好餵滿：所以這張圖上
## **礦砂入帳是 0 而合金入帳是 2/秒**——「兩張網各解各的」在畫面上就是這句話。
const SANDBOX_DEMO := [
	["place", "extractor", Vector2i(2, 2)],
	["place", "extractor", Vector2i(2, 3)],
	["place", "generator", Vector2i(6, 2)],
	["place", "smelter", Vector2i(2, 6)],
	["place", "relay", Vector2i(6, 6)],
	["conduit", Vector2i(2, 2), Vector2i(6, 2)],    # 礦 → 發電機
	["conduit", Vector2i(2, 2), Vector2i(2, 6)],    # 礦 → 熔爐
	["conduit", Vector2i(2, 3), Vector2i(2, 6)],    # 礦 → 熔爐
	["conduit", Vector2i(6, 2), Vector2i(2, 6)],    # 電 → 熔爐（45°）
	["conduit", Vector2i(2, 6), Vector2i(6, 6)],    # 合金 → 中繼
	["conduit", Vector2i(6, 6), Vector2i(10, 10)],  # 中繼 → 核心（45°）
]


## 敵人路徑（有序，供 B0.4 的推進使用；B0.3 只用它做建造合法性）。
##
## ★ B1.2：路徑改由地圖自己宣告 `waypoints`（轉折點，最後一點必為核心），
## 這裡只負責展開。原本是一支寫死 `shoal` 的 `if`——五關戰役再照抄四次，
## 就是五份會各自過期的地圖知識。**轉折一律 90°**（斜著走的敵人沒有意義：
## 「路徑格不可蓋節點」在對角線上會變成一條漏得到處都是的柵欄）。
static func path_of(map: Dictionary) -> Array:
	var pts: Array = map.get("waypoints", [])
	var cells: Array[Vector2i] = []
	for i in pts.size():
		var to: Vector2i = pts[i]
		if i == 0:
			cells.append(to)
			continue
		var from: Vector2i = pts[i - 1]
		var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
		# 起點已經在上一段的尾巴上了，從第二格開始接。
		var c := from + step
		while c != to:
			cells.append(c)
			c += step
		cells.append(to)
	return cells


## 這張圖的波次表（`data/Enemies.gd`）。戰役五關各自一張，都寫在資料層。
static func waves_of(map: Dictionary) -> Array:
	return map.get("waves", [])


## 地圖 → 解算與建造要用的集合形式（`Dictionary` 當 set，查詢 O(1)）。
## 每張圖只轉一次，存在 `SessionState` 裡。
static func to_sets(map: Dictionary) -> Dictionary:
	var path: Dictionary = {}
	for c: Vector2i in path_of(map):
		path[c] = true
	var crossings: Dictionary = {}
	for c: Vector2i in map.get("crossings", []):
		crossings[c] = true
	var ore: Dictionary = {}
	for c: Vector2i in map.get("ore", []):
		ore[c] = true
	return {
		"size": map.get("size", Vector2i.ZERO),
		"path": path,
		"crossings": crossings,
		"ore": ore,
		"core": map.get("core", Vector2i.ZERO),
	}
