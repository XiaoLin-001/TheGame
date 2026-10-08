extends RefCounted
## 戰役五關（`10_GDD.md` §7.9）。**數值的唯一來源**——不在程式碼裡即興發明。
## 不宣告 `class_name`，一律以路徑 preload。
##
## ── 一關由五件事構成 ────────────────────────────────────────────────
##   `map`       地圖本身（尺寸／核心／轉折點／礦點／跨越點／起始礦砂／準備期）
##   `unlocked`  這一關玩家手上有哪幾顆建造鈕 —— **難度階梯就是這一欄**（§7.9）
##   `star_throughput`  ★★★ 的產能積分門檻（§7.6 的同一個分數，不另發明）
##   `reward`    首通基礎獎勵，實得 ＝ `reward × 星數`，補星只補差額
##   `demo`      ★ 參考解（見下）
##
## ── 參考解是什麼、不是什麼 ──────────────────────────────────────────
## 它是**這一關可以被通關**的證據，由 `tests/campaign_test.gd` 每次回歸實跑
## （B1.2 DoD：「第 1–2 關以新手可通關為硬性驗收」）。它刻意樸素：
## 沒有極限擺位、沒有卡角度、用的節點數接近下限——因為它要證明的是
## **一個剛學會的人做得到**，不是最佳解。
##
## `["wait", ticks]` 把腳本切成幾段：**分段建造才是玩家真正的樣子**，
## 一口氣全蓋起來只會逼得起始礦砂虛高，而起始礦砂是關卡參數（§7.7），
## 虛高等於偷偷把難度調低。

const Demos := preload("res://data/CampaignDemos.gd")
const Enemies := preload("res://data/Enemies.gd")

## 依序解鎖的建造欄。每一關「新解鎖的那一顆」就是它要教的機制（§7.9）。
const L1_BUILD := ["extractor", "generator", "relay", "anchor"]
const L2_BUILD := ["extractor", "generator", "relay", "silo", "anchor", "prism"]
const L3_BUILD := [
	"extractor", "generator", "relay", "silo", "anchor", "prism", "knell", "reclaimer",
]
const L4_BUILD := [
	"extractor", "generator", "smelter", "relay", "silo",
	"anchor", "prism", "knell", "reclaimer",
]
## 第 5 關全解鎖（＝ `NodeDefs.BUILDABLE` 全部十種）。
const L5_BUILD := [
	"extractor", "generator", "smelter", "relay", "silo",
	"anchor", "prism", "knell", "reclaimer", "breaker",
]


# ── 第 1 關「潮口」──────────────────────────────────────────────────
## 教的是核心循環：**礦砂 → 能量 → 塔**，一條線走完。
##
## 三個新手參數同時到位（§7.7，全部看得見）：**零座橋**（網路怎麼縫都對）、
## 只有漂蟲、準備期 60 秒。塔只給錨——4 能量/秒，基礎 cap 10 綽綽有餘，
## 學電力數學的第一課不該從「你的塔永遠餵不飽」開始（§7.9）。
const L1 := {
	"id": "tidemouth",
	"name": "潮口",
	"biome": "shoal",
	"size": Vector2i(20, 12),
	"core": Vector2i(18, 7),
	"waypoints": [Vector2i(0, 2), Vector2i(14, 2), Vector2i(14, 7), Vector2i(18, 7)],
	"start_ore": 300,
	"prep_time": 60.0,
	"crossings": [],
	"ore": [Vector2i(16, 9), Vector2i(10, 9), Vector2i(4, 6), Vector2i(6, 10)],
	"waves": Enemies.L1_WAVES,
}

# ── 第 2 關「雙灣」──────────────────────────────────────────────────
## 新解鎖：**儲槽・稜鏡**。教的是**峰值電力**。
##
## ★ 稜鏡有兩個限制同時咬住玩家，這一關就是它們的教室：
##   ① 它交戰吃 20 能量/秒，而導管基礎 cap 是 10 —— **一條線餵不飽它**。
##      正解是繞成一個菱形：發電機 →（左中繼／右中繼）→ 稜鏡，10 ＋ 10。
##   ② 它的貫穿是**沿著一條軸線**（`sim/Combat.pierce_indices`），
##      所以它必須和某一段路徑**同排或同列**才打得到整段（§7.4 對齊謎題）。
##      (20,12) 站在敵人下坡那一列 x=20 的正下方，一發貫穿八格。
## 北岸那顆礦要過橋（唯一一座）：導管**穿過**橋面，不能停在橋上（§3.2）。
const L2 := {
	"id": "twinbay",
	"name": "雙灣",
	"biome": "shoal",
	"size": Vector2i(26, 15),
	"core": Vector2i(23, 10),
	"waypoints": [Vector2i(0, 2), Vector2i(20, 2), Vector2i(20, 10), Vector2i(23, 10)],
	"start_ore": 430,
	"prep_time": 60.0,
	"crossings": [Vector2i(9, 2)],
	"ore": [
		Vector2i(9, 0),                    # 北岸：非得過橋不可
		Vector2i(12, 7), Vector2i(5, 8), Vector2i(4, 11), Vector2i(16, 13),
	],
	"waves": Enemies.L2_WAVES,
}

# ── 第 3 關「窄橋」──────────────────────────────────────────────────
## 新解鎖：**潮鳴・回收者**。教的是**一座橋就是一條幹線**。
##
## 北岸兩顆礦、南岸兩顆，而全圖只有一座橋——北岸的產能全部要擠過
## (12,4) 那一條線，**那條線的 cap 就是這一關的瓶頸**。加粗它只要
## 20 礦砂（1 級不用合金，§7.2），這是玩家第一次非加粗不可。
const L3 := {
	"id": "narrows",
	"name": "窄橋",
	"biome": "reef",
	"size": Vector2i(28, 17),
	"core": Vector2i(25, 12),
	"waypoints": [Vector2i(0, 4), Vector2i(22, 4), Vector2i(22, 12), Vector2i(25, 12)],
	"start_ore": 540,
	"prep_time": 45.0,
	"crossings": [Vector2i(12, 4)],
	"ore": [
		Vector2i(12, 1), Vector2i(17, 2), Vector2i(6, 2),   # 北岸三顆，共用一座橋
		Vector2i(20, 9), Vector2i(5, 10),
	],
	"waves": Enemies.L3_WAVES,
}

# ── 第 4 關「熔渣灣」────────────────────────────────────────────────
## 新解鎖：**熔爐**。教的是**第三資源**。
##
## 兩座橋、兩條北岸產線，礦砂夠了；但沒有合金時導管最多 16（1 級），
## 而稜鏡的菱形要占掉兩條線。熔爐煉出合金 → 幹線加粗到 2 級 cap 22，
## **一條線終於扛得動整組防線**。合金同時是碎浪的門票（第 5 關才給）。
const L4 := {
	"id": "slagbay",
	"name": "熔渣灣",
	"biome": "slag",
	"size": Vector2i(30, 18),
	"core": Vector2i(27, 13),
	"waypoints": [Vector2i(0, 4), Vector2i(24, 4), Vector2i(24, 13), Vector2i(27, 13)],
	"start_ore": 720,
	"prep_time": 45.0,
	"crossings": [Vector2i(8, 4), Vector2i(18, 4)],
	"ore": [
		Vector2i(8, 1), Vector2i(18, 1),                     # 北岸，一橋一線
		Vector2i(11, 10), Vector2i(21, 10), Vector2i(5, 12), Vector2i(14, 17),
	],
	"waves": Enemies.L4_WAVES,
}

# ── 第 5 關「潮汐之喉」──────────────────────────────────────────────
## 新解鎖：**碎浪**。全解鎖綜合考。
##
## 三座橋、礦點大半在對岸、五波混編（第 5 波 14 隻漂蟲間距 0.5 秒——
## 碎浪的濺射就是為這種隊列存在的，§7.4）。這一關不教新東西，
## 它問的是「前四關那四件事你能不能同時做」。
const L5 := {
	"id": "tidethroat",
	"name": "潮汐之喉",
	"biome": "trench",
	"size": Vector2i(34, 18),
	# ★ B1.6.1：核心從 (31,15) 上移到 (31,14)。理由是**流量網路的一條硬語意**：
	# 節點會先吃滿自己的需求才轉發，所以**把塔擺在幹線的接點上，會餓死它下游
	# 的一切**。稜鏡要兩條進線就得當接點，而那條幹線同時要餵核心旁邊的錨——
	# 兩件事互斥。核心上移一格之後 y=16 空出來，稜鏡可以貼在下坡列旁邊、
	# 由**兩個中繼**（不吃電）分岔進去，錨的線就不用穿過任何消費者。
	"core": Vector2i(31, 14),
	"waypoints": [Vector2i(0, 4), Vector2i(28, 4), Vector2i(28, 14), Vector2i(31, 14)],
	"start_ore": 1240,
	"prep_time": 45.0,
	"crossings": [Vector2i(7, 4), Vector2i(15, 4), Vector2i(23, 4)],
	"ore": [
		Vector2i(7, 1), Vector2i(15, 1), Vector2i(23, 1),    # 北岸三顆，三座橋
		Vector2i(11, 11), Vector2i(19, 15), Vector2i(24, 13), Vector2i(5, 13),
	],
	"waves": Enemies.L5_WAVES,
}

# ══ 第二幕（第 6–10 關，B3.3）═══════════════════════════════════════
## 第二幕全部沿用第 5 關的建造欄——**全解鎖之後沒有鈕可以發了**。
## 階梯改由波次表承擔（`Enemies.gd` L6_WAVES 的長註解）：一關多一條敵人規則。
const ACT2_BUILD := L5_BUILD


# ── 第 6 關「苔灘」──────────────────────────────────────────────────
## 新規則：**苔群**（一次來一團）。教的是**濺射與貫穿的價值**。
##
## 前五關的敵人是一隻一隻來的，於是「單體塔排成一列」一路都是對的答案。
## 苔群把壓力的**形狀**換掉：總量和漂蟲同一個量級，但六隻擠在 6 格內
## ——稜鏡的貫穿線一發吃掉整段，而同樣的電費打單體只換得到一隻。
##
## 地形讓這件事看得見：**下坡那一整列 x=24 是筆直的九格**，稜鏡貼在
## (24,15) 與它同列，一團苔群走進去就是一整條。
const L6 := {
	"id": "mossflat",
	"name": "苔灘",
	"biome": "moss",
	"size": Vector2i(30, 16),
	"core": Vector2i(27, 12),
	"waypoints": [Vector2i(0, 3), Vector2i(24, 3), Vector2i(24, 12), Vector2i(27, 12)],
	"start_ore": 1100,
	"prep_time": 45.0,
	"crossings": [Vector2i(10, 3), Vector2i(18, 3)],
	"ore": [
		Vector2i(10, 0), Vector2i(18, 0),                    # 北岸兩顆，兩座橋
		Vector2i(7, 7), Vector2i(4, 10), Vector2i(14, 11), Vector2i(21, 14),
	],
	"waves": Enemies.L6_WAVES,
}

# ── 第 7 關「逆流」──────────────────────────────────────────────────
## 新規則：**潛涌**（免疫減速）。教的是**光環有一個洞**。
##
## 潮鳴從第 3 關就在，而它的減速 −40% 到這一關為止對**每一隻**敵人都有效
## ——「先蓋一座潮鳴」是一個沒有代價的答案。潛涌從光環裡照原速走出去，
## 玩家第一次得問「那我拿什麼打它」，而答案是既有的爆發單體。
##
## 參考解**刻意留著那座潮鳴**：它對苔群與甲殼仍然是對的，
## 而「同一座塔對這隻有效、對那隻沒效」正是這一關要留下的印象。
const L7 := {
	"id": "backwash",
	"name": "逆流",
	"biome": "current",
	"size": Vector2i(32, 17),
	"core": Vector2i(29, 13),
	"waypoints": [Vector2i(0, 3), Vector2i(26, 3), Vector2i(26, 13), Vector2i(29, 13)],
	"start_ore": 1200,
	"prep_time": 45.0,
	"crossings": [Vector2i(9, 3), Vector2i(18, 3)],
	"ore": [
		Vector2i(9, 0), Vector2i(18, 0),                     # 北岸兩顆，兩座橋
		Vector2i(6, 10), Vector2i(3, 13), Vector2i(13, 12), Vector2i(23, 16),
	],
	"waves": Enemies.L7_WAVES,
}

# ── 第 8 關「殼場」──────────────────────────────────────────────────
## 新規則：**癒殼**（每秒回最大血 4%）。教的是**dps 有一個地板**。
##
## 前七關的「電不夠」都只是**慢一點**——射速線性下降，敵人晚一點死。
## 癒殼把那條斜率換成一個門檻：dps 掉到再生之下，那一隻就**永遠不會死**，
## 它會一路走到核心。這是 §3.1 峰值電力第一次以「打不死」的形式現身。
##
## 所以這一關的參考解第一次蓋**三台發電機**：
## 前七關的答案是「電夠用就好」，這一關的答案是「電要有餘裕」。
const L8 := {
	"id": "shellfield",
	"name": "殼場",
	"biome": "shell",
	"size": Vector2i(34, 17),
	"core": Vector2i(31, 13),
	"waypoints": [Vector2i(0, 3), Vector2i(28, 3), Vector2i(28, 13), Vector2i(31, 13)],
	"start_ore": 1400,
	"prep_time": 45.0,
	"crossings": [Vector2i(8, 3), Vector2i(16, 3), Vector2i(24, 3)],
	"ore": [
		Vector2i(8, 0), Vector2i(16, 0), Vector2i(24, 0),    # 北岸三顆，三座橋
		Vector2i(5, 10), Vector2i(2, 13), Vector2i(13, 10), Vector2i(20, 15),
	],
	"waves": Enemies.L8_WAVES,
}

# ── 第 9 關「亂潮」──────────────────────────────────────────────────
## 三條規則**同時**來。前三關各教一條，這一關把它們疊在同一波裡。
##
## 疊法是**兩兩配對**（`Enemies.L9_WAVES`）：苔群＋潛涌、癒殼＋苔群。
## 每一對都是一個**分配問題**——同一份電先餵誰，而那正是優先權滑桿存在的理由。
##
## ⚠ 參考解**不動滑桿**（腳本只有放置／接線／加粗三種指令），所以它證明的是
## 「這一關用預設優先權也過得了」。滑桿是玩家的餘裕，不是通關的門票。
const L9 := {
	"id": "riptide",
	"name": "亂潮",
	"biome": "riptide",
	"size": Vector2i(36, 18),
	"core": Vector2i(33, 14),
	"waypoints": [Vector2i(0, 4), Vector2i(30, 4), Vector2i(30, 14), Vector2i(33, 14)],
	"start_ore": 1500,
	"prep_time": 45.0,
	"crossings": [Vector2i(8, 4), Vector2i(16, 4), Vector2i(24, 4)],
	"ore": [
		Vector2i(8, 1), Vector2i(16, 1), Vector2i(24, 1),    # 北岸三顆，三座橋
		Vector2i(5, 11), Vector2i(12, 12), Vector2i(22, 16),
	],
	"waves": Enemies.L9_WAVES,
}

# ── 第 10 關「深喉」──────────────────────────────────────────────────
## **六種敵人全上**，第二幕的畢業考。六波，最後一波六種同時出場。
##
## 這一關的參考解是全案唯一一份同時用上**熔爐 → 合金 → 碎浪**與
## 稜鏡菱形與潮鳴的佈局：苔群要濺射、甲殼要破甲、癒殼要爆發、潛涌要單體。
## 一種塔擋不住六條規則，而這正是第一幕十顆按鈕存在的理由。
const L10 := {
	"id": "deepthroat",
	"name": "深喉",
	"biome": "trench",
	"size": Vector2i(38, 19),
	"core": Vector2i(35, 15),
	"waypoints": [Vector2i(0, 4), Vector2i(32, 4), Vector2i(32, 15), Vector2i(35, 15)],
	"start_ore": 1800,
	"prep_time": 45.0,
	"crossings": [Vector2i(6, 4), Vector2i(14, 4), Vector2i(22, 4), Vector2i(28, 4)],
	"ore": [
		Vector2i(6, 1), Vector2i(14, 1), Vector2i(22, 1), Vector2i(28, 1),   # 北岸四顆，四座橋
		Vector2i(4, 10), Vector2i(12, 10), Vector2i(25, 13),
	],
	"waves": Enemies.L10_WAVES,
}

## 五關，**依序**。索引即關卡序（第 N 關解鎖第 N+1 關，§7.9）。
##
## ★ `star_throughput` 是**實測校準**的，不是拍腦袋：B1.2 用 `campaign_test`
## 把每一關的參考解跑到底量出產能積分（0.80／0.48／0.38／0.29／0.19），
## 門檻取它的 1.3–2 倍。所以三星的意思很具體：**你的產線得比「剛好夠打」
## 那一版好一半以上**。門檻**隨關卡遞減**不是筆誤——後面的圖更長（導管更多）、
## 消費者更多（熔爐與第三台發電機都吃礦砂），而積分的分母含整局時間。
const LEVELS := [
	{
		"map": L1, "demo": Demos.L1_DEMO, "unlocked": L1_BUILD,
		"star_throughput": 1.0, "reward": 30,
		"lesson": "礦砂 → 能量 → 塔：一條線走完核心循環",
	},
	{
		"map": L2, "demo": Demos.L2_DEMO, "unlocked": L2_BUILD,
		"star_throughput": 0.7, "reward": 40,
		"lesson": "峰值電力：一座稜鏡吃掉一整台發電機，儲槽補赤字",
	},
	{
		"map": L3, "demo": Demos.L3_DEMO, "unlocked": L3_BUILD,
		"star_throughput": 0.6, "reward": 55,
		"lesson": "只有一座橋：北岸的產能全要從它過",
	},
	{
		"map": L4, "demo": Demos.L4_DEMO, "unlocked": L4_BUILD,
		"star_throughput": 0.5, "reward": 70,
		"lesson": "第三資源：合金把幹線加粗到 22（稜鏡吃 20 能量/秒）",
	},
	{
		"map": L5, "demo": Demos.L5_DEMO, "unlocked": L5_BUILD,
		"star_throughput": 0.4, "reward": 90,
		"lesson": "全解鎖綜合考：三座橋、礦在對岸、五波混編",
	},
	{
		"map": L6, "demo": Demos.L6_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.55, "reward": 100,
		"lesson": "苔群：六隻擠在 6 格內，貫穿與濺射一發打完整段",
	},
	{
		"map": L7, "demo": Demos.L7_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.40, "reward": 110,
		"lesson": "潛涌：免疫減速，潮鳴與霜礁對它無效",
	},
	{
		"map": L8, "demo": Demos.L8_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.60, "reward": 125,
		"lesson": "癒殼：每秒回最大血 4%，dps 追不上就打不死",
	},
	{
		"map": L9, "demo": Demos.L9_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.35, "reward": 140,
		"lesson": "混編：苔群、潛涌、癒殼兩兩同時來",
	},
	{
		"map": L10, "demo": Demos.L10_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.55, "reward": 160,
		"lesson": "畢業考：六種敵人，最後一波同時出場",
	},
]


static func count() -> int:
	return LEVELS.size()


## 第 `index` 關（0-based）。越界回空字典，呼叫端自己擋——
## 回一個假的第 1 關會讓「關卡選擇壞掉」看起來像「玩家點錯了」。
static func at(index: int) -> Dictionary:
	if index < 0 or index >= LEVELS.size():
		return {}
	return LEVELS[index]


## 地圖 id → 關卡序。存檔存的是 id 不是索引（插關不會讓舊存檔錯位）。
static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if String(((LEVELS[i] as Dictionary)["map"] as Dictionary)["id"]) == id:
			return i
	return -1


static func id_at(index: int) -> String:
	var lv := at(index)
	return "" if lv.is_empty() else String((lv["map"] as Dictionary)["id"])


## ★ 已經開到第幾關（回傳可遊玩的關卡數）。第 1 關永遠開著；之後要前一關
## ≥1 星（§7.9；sv2 起沒有另一份 `cleared` 清單）。
##
## **這條規則只該有一份**（B2.4）：關卡選擇畫面問「這張卡能不能點」，名冊問
## 「這幾隻角色是不是我的」——同一個事實兩個問法。各判一次的話，日後改成
## 「要 2 星才開下一關」時只會有一邊跟著改，而名冊那邊沒有任何畫面會抗議。
static func open_count(stars: Dictionary) -> int:
	var n := 1
	while n < LEVELS.size() and int(stars.get(id_at(n - 1), 0)) >= 1:
		n += 1
	return n


## 全部關卡 id（依關序）。統計進度時用，免得呼叫端自己寫一次 `for i in count()`。
static func ids() -> Array[String]:
	var out: Array[String] = []
	for i in LEVELS.size():
		out.append(id_at(i))
	return out
