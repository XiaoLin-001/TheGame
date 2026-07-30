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
	"size": Vector2i(20, 12),
	"core": Vector2i(18, 7),
	"waypoints": [Vector2i(0, 2), Vector2i(14, 2), Vector2i(14, 7), Vector2i(18, 7)],
	"start_ore": 300,
	"prep_time": 60.0,
	"crossings": [],
	"ore": [Vector2i(16, 9), Vector2i(10, 9), Vector2i(4, 6), Vector2i(6, 10)],
	"waves": Enemies.L1_WAVES,
}

const L1_DEMO := [
	# ① 最短的一條產線：礦點就在核心的斜對角，一段導管就入帳。
	["place", "extractor", Vector2i(16, 9)],
	["conduit", Vector2i(16, 9), Vector2i(18, 7)],
	# ② 第二座採集器餵發電機，剩下的順著同一條線繼續進核心。
	["place", "extractor", Vector2i(10, 9)],
	["place", "generator", Vector2i(12, 9)],
	["conduit", Vector2i(10, 9), Vector2i(12, 9)],
	["conduit", Vector2i(12, 9), Vector2i(16, 9)],
	["wait", 200],   # 20 秒：先讓產線賺出塔的錢，這才是玩家真正的順序

	# ③ 三座錨，**都退開路徑 2 格**——walk-by 打不到（§3.5）。
	#    (17,10) 那座蓋在核心旁邊：**漏過來的必須有人打得到**，否則
	#    一隻走到底的漂蟲就是必輸——它站在核心上啃，而沒有一座塔搆得著。
	["place", "anchor", Vector2i(12, 5)],
	["conduit", Vector2i(12, 5), Vector2i(12, 9)],
	["place", "anchor", Vector2i(17, 10)],
	["conduit", Vector2i(17, 10), Vector2i(16, 9)],
	["place", "anchor", Vector2i(8, 5)],
	["conduit", Vector2i(8, 5), Vector2i(12, 9)],
]



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

const L2_DEMO := [
	# ① 過橋的那條線：垂直穿過 (9,2) 橋面。橋 ±1 格免疫，引道不會被打斷（§3.5）。
	["place", "relay", Vector2i(9, 5)],
	["place", "extractor", Vector2i(9, 0)],
	["conduit", Vector2i(9, 0), Vector2i(9, 5)],
	["place", "relay", Vector2i(9, 9)],
	["conduit", Vector2i(9, 5), Vector2i(9, 9)],
	["place", "relay", Vector2i(14, 9)],
	["conduit", Vector2i(9, 9), Vector2i(14, 9)],
	["place", "extractor", Vector2i(12, 7)],
	["conduit", Vector2i(12, 7), Vector2i(14, 9)],
	# ② 幹線斜切到南邊，繞過路徑的轉角再接核心。
	["place", "relay", Vector2i(18, 13)],
	["conduit", Vector2i(14, 9), Vector2i(18, 13)],
	["place", "relay", Vector2i(19, 13)],
	["conduit", Vector2i(18, 13), Vector2i(19, 13)],
	["place", "generator", Vector2i(20, 14)],
	["conduit", Vector2i(19, 13), Vector2i(20, 14)],
	["place", "relay", Vector2i(21, 13)],
	["conduit", Vector2i(20, 14), Vector2i(21, 13)],
	["place", "relay", Vector2i(22, 12)],
	["conduit", Vector2i(21, 13), Vector2i(22, 12)],
	["place", "relay", Vector2i(24, 10)],
	["conduit", Vector2i(22, 12), Vector2i(24, 10)],
	["conduit", Vector2i(24, 10), Vector2i(23, 10)],

	["wait", 300],   # 30 秒：讓產線自己賺出防線的錢

	# ③ ★ 稜鏡的菱形：發電機 (20,14) 左右各一條線繞上來，10 ＋ 10 ＝ 20。
	#    少了任何一邊，它就只有半速——這一關要玩家親眼看到的就是這件事。
	["place", "prism", Vector2i(20, 12)],
	["conduit", Vector2i(19, 13), Vector2i(20, 12)],
	["conduit", Vector2i(21, 13), Vector2i(20, 12)],
	# ④ 錨蓋在核心旁邊：**漏過來的必須有人打得到**（稜鏡的貫穿線搆不到核心）。
	["place", "anchor", Vector2i(22, 13)],
	["conduit", Vector2i(22, 13), Vector2i(21, 13)],
	# ⑤ 儲槽掛在錨那一側：赤字的 4 點要從**這條線**補進來，
	#    掛到發電機那一側的話它得先擠過已經滿載的菱形（§3.1 充放電受自身導管 cap 約束）。
	["place", "silo", Vector2i(22, 14)],
	["conduit", Vector2i(22, 14), Vector2i(21, 13)],
]


# ── 第 3 關「窄橋」──────────────────────────────────────────────────
## 新解鎖：**潮鳴・回收者**。教的是**一座橋就是一條幹線**。
##
## 北岸兩顆礦、南岸兩顆，而全圖只有一座橋——北岸的產能全部要擠過
## (12,4) 那一條線，**那條線的 cap 就是這一關的瓶頸**。加粗它只要
## 20 礦砂（1 級不用合金，§7.2），這是玩家第一次非加粗不可。
const L3 := {
	"id": "narrows",
	"name": "窄橋",
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

const L3_DEMO := [
	# ① 北岸集線：兩座採集器併到 (12,2)，再垂直穿過橋。
	["place", "relay", Vector2i(12, 2)],
	["place", "extractor", Vector2i(12, 1)],
	["conduit", Vector2i(12, 1), Vector2i(12, 2)],
	["place", "extractor", Vector2i(17, 2)],
	["conduit", Vector2i(17, 2), Vector2i(12, 2)],
	["place", "relay", Vector2i(12, 7)],
	["conduit", Vector2i(12, 2), Vector2i(12, 7)],
	["upgrade", Vector2i(12, 2), Vector2i(12, 7), 1],   # ★ 12/秒塞不進 cap 10
	# ② 幹線斜切到南緣，發電機蹲在稜鏡菱形的頂點上。
	["place", "relay", Vector2i(17, 12)],
	["conduit", Vector2i(12, 7), Vector2i(17, 12)],
	["place", "generator", Vector2i(20, 15)],
	["conduit", Vector2i(17, 12), Vector2i(20, 15)],
	["place", "relay", Vector2i(23, 15)],
	["conduit", Vector2i(20, 15), Vector2i(23, 15)],
	["place", "relay", Vector2i(25, 13)],
	["conduit", Vector2i(23, 15), Vector2i(25, 13)],
	["conduit", Vector2i(25, 13), Vector2i(25, 12)],

	["wait", 300],

	# ③ 稜鏡的菱形，這次貼在下坡那一列 x=22 的正下方。
	["place", "relay", Vector2i(21, 14)],
	["conduit", Vector2i(20, 15), Vector2i(21, 14)],
	["place", "relay", Vector2i(21, 16)],
	["conduit", Vector2i(20, 15), Vector2i(21, 16)],
	["place", "prism", Vector2i(22, 15)],
	["conduit", Vector2i(21, 14), Vector2i(22, 15)],
	["conduit", Vector2i(21, 16), Vector2i(22, 15)],
	# ④ 第二台發電機（稜鏡 20 ＋ 錨 4 一台餵不動）與守核心的錨。
	["place", "generator", Vector2i(18, 15)],
	["conduit", Vector2i(18, 15), Vector2i(20, 15)],
	["place", "anchor", Vector2i(24, 15)],
	["conduit", Vector2i(24, 15), Vector2i(23, 15)],

	["wait", 300],

	# ⑤ 南岸那顆礦最後補上——它走的是另一條線，不佔橋。幹線一併撐開。
	["place", "extractor", Vector2i(20, 9)],
	["conduit", Vector2i(20, 9), Vector2i(17, 12)],
	["upgrade", Vector2i(12, 7), Vector2i(17, 12), 1],
	["upgrade", Vector2i(17, 12), Vector2i(20, 15), 1],
	["upgrade", Vector2i(20, 15), Vector2i(23, 15), 1],
	["upgrade", Vector2i(23, 15), Vector2i(25, 13), 1],
]


# ── 第 4 關「熔渣灣」────────────────────────────────────────────────
## 新解鎖：**熔爐**。教的是**第三資源**。
##
## 兩座橋、兩條北岸產線，礦砂夠了；但沒有合金時導管最多 16（1 級），
## 而稜鏡的菱形要占掉兩條線。熔爐煉出合金 → 幹線加粗到 2 級 cap 22，
## **一條線終於扛得動整組防線**。合金同時是碎浪的門票（第 5 關才給）。
const L4 := {
	"id": "slagbay",
	"name": "熔渣灣",
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

const L4_DEMO := [
	# ① 兩條過橋線，各自垂直穿過自己那座橋，在 y=7 併成一條北岸幹線。
	["place", "relay", Vector2i(8, 7)],
	["place", "extractor", Vector2i(8, 1)],
	["conduit", Vector2i(8, 1), Vector2i(8, 7)],
	["place", "relay", Vector2i(18, 7)],
	["place", "extractor", Vector2i(18, 1)],
	["conduit", Vector2i(18, 1), Vector2i(18, 7)],
	["conduit", Vector2i(8, 7), Vector2i(18, 7)],
	# ② 發電機與南岸的礦。
	["place", "generator", Vector2i(10, 9)],
	["conduit", Vector2i(10, 9), Vector2i(8, 7)],
	["place", "extractor", Vector2i(11, 10)],
	["conduit", Vector2i(11, 10), Vector2i(10, 9)],
	["place", "extractor", Vector2i(21, 10)],
	["conduit", Vector2i(21, 10), Vector2i(18, 7)],
	# ③ 幹線沿南緣往東接核心。
	#    ★ B1.6.1：原本是 (10,9)→(16,15) 一條 45°，而它和上面那條
	#    (11,10)→(10,9) **同一個斜向**——兩條線疊在同一排格上（使用者回報
	#    「有重疊」）。改成「先垂直下來、再水平往東」，順帶把採集器 (11,10)
	#    留在自己的支線上。
	["place", "relay", Vector2i(10, 15)],
	["conduit", Vector2i(10, 9), Vector2i(10, 15)],
	["place", "relay", Vector2i(16, 15)],
	["conduit", Vector2i(10, 15), Vector2i(16, 15)],
	["place", "relay", Vector2i(22, 15)],
	["conduit", Vector2i(16, 15), Vector2i(22, 15)],
	["place", "relay", Vector2i(25, 15)],
	["conduit", Vector2i(22, 15), Vector2i(25, 15)],
	["conduit", Vector2i(25, 15), Vector2i(27, 13)],
	# 四座採集器 24/秒塞不進 cap 10。1 級加粗不用合金（§7.2），先撐到 16。
	["upgrade", Vector2i(8, 7), Vector2i(18, 7), 1],
	["upgrade", Vector2i(10, 9), Vector2i(10, 15), 1],
	["upgrade", Vector2i(10, 15), Vector2i(16, 15), 1],
	["upgrade", Vector2i(16, 15), Vector2i(22, 15), 1],
	["upgrade", Vector2i(22, 15), Vector2i(25, 15), 1],
	["upgrade", Vector2i(25, 15), Vector2i(27, 13), 1],

	["wait", 400],

	# ④ ★ 熔爐。它**待機也吃 10 能量/秒**——這是它與塔最大的不同（§7.3）。
	["place", "smelter", Vector2i(13, 12)],
	["conduit", Vector2i(13, 12), Vector2i(10, 15)],
	["conduit", Vector2i(13, 12), Vector2i(16, 15)],
	# ⑤ 第二台發電機蹲在菱形頂點，稜鏡貼著下坡那一列 x=24。
	["place", "generator", Vector2i(22, 16)],
	["conduit", Vector2i(22, 15), Vector2i(22, 16)],
	["place", "relay", Vector2i(23, 15)],
	["conduit", Vector2i(22, 16), Vector2i(23, 15)],
	["place", "relay", Vector2i(23, 17)],
	["conduit", Vector2i(22, 16), Vector2i(23, 17)],
	["place", "prism", Vector2i(24, 16)],
	["conduit", Vector2i(23, 15), Vector2i(24, 16)],
	["conduit", Vector2i(23, 17), Vector2i(24, 16)],
	["place", "anchor", Vector2i(26, 15)],
	["conduit", Vector2i(26, 15), Vector2i(25, 15)],
	# 潮鳴減速下坡段：稜鏡射速固定 0.5，敵人慢一點＝同一段路多挨兩發。
	["place", "knell", Vector2i(22, 14)],
	["conduit", Vector2i(22, 14), Vector2i(22, 15)],
	["place", "silo", Vector2i(21, 16)],
	["conduit", Vector2i(21, 16), Vector2i(22, 16)],

	["wait", 600],

	# ⑥ ★ 合金到帳：幹線加粗到 2 級（cap 22）。這是全案第一次「非合金不可」
	#    的加粗（1 級不要合金，§7.2）。順手把最後一顆礦接上。
	["upgrade", Vector2i(10, 9), Vector2i(10, 15), 1],
	["upgrade", Vector2i(10, 15), Vector2i(16, 15), 1],
	["upgrade", Vector2i(16, 15), Vector2i(22, 15), 1],
	["place", "extractor", Vector2i(14, 17)],
	["conduit", Vector2i(14, 17), Vector2i(16, 15)],
]


# ── 第 5 關「潮汐之喉」──────────────────────────────────────────────
## 新解鎖：**碎浪**。全解鎖綜合考。
##
## 三座橋、礦點大半在對岸、五波混編（第 5 波 14 隻漂蟲間距 0.5 秒——
## 碎浪的濺射就是為這種隊列存在的，§7.4）。這一關不教新東西，
## 它問的是「前四關那四件事你能不能同時做」。
const L5 := {
	"id": "tidethroat",
	"name": "潮汐之喉",
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

const L5_DEMO := [
	# ① 三條過橋線，在 y=7 併成一條北岸幹線。
	["place", "relay", Vector2i(7, 7)],
	["place", "extractor", Vector2i(7, 1)],
	["conduit", Vector2i(7, 1), Vector2i(7, 7)],
	["place", "relay", Vector2i(15, 7)],
	["place", "extractor", Vector2i(15, 1)],
	["conduit", Vector2i(15, 1), Vector2i(15, 7)],
	["place", "relay", Vector2i(23, 7)],
	["place", "extractor", Vector2i(23, 1)],
	["conduit", Vector2i(23, 1), Vector2i(23, 7)],
	["conduit", Vector2i(7, 7), Vector2i(15, 7)],
	["conduit", Vector2i(15, 7), Vector2i(23, 7)],
	# ② 兩台發電機掛在幹線南側。**不要蓋到北岸**——y=4 那一列只有三格橋
	#    可以穿過去，蓋在對岸的東西電送不回來。
	["place", "generator", Vector2i(13, 9)],
	["conduit", Vector2i(13, 9), Vector2i(15, 7)],
	["place", "generator", Vector2i(21, 9)],
	["conduit", Vector2i(21, 9), Vector2i(23, 7)],
	# ③ 幹線沿南緣接核心。
	["place", "extractor", Vector2i(11, 11)],
	["conduit", Vector2i(11, 11), Vector2i(13, 9)],
	["place", "relay", Vector2i(21, 17)],
	["conduit", Vector2i(13, 9), Vector2i(21, 17)],
	["place", "relay", Vector2i(26, 17)],
	["conduit", Vector2i(21, 17), Vector2i(26, 17)],
	["place", "relay", Vector2i(27, 17)],
	["conduit", Vector2i(26, 17), Vector2i(27, 17)],
	["place", "relay", Vector2i(29, 17)],
	["conduit", Vector2i(27, 17), Vector2i(29, 17)],
	["place", "relay", Vector2i(29, 16)],
	["conduit", Vector2i(29, 17), Vector2i(29, 16)],
	["conduit", Vector2i(29, 16), Vector2i(31, 14)],

	["wait", 300],

	# ④ 熔爐 ＋ 稜鏡（貼著下坡那一列 x=28）＋ 守核心的錨。
	["place", "smelter", Vector2i(17, 17)],
	["conduit", Vector2i(17, 17), Vector2i(21, 17)],
	["place", "relay", Vector2i(26, 15)],
	["conduit", Vector2i(26, 17), Vector2i(26, 15)],
	# ★ 稜鏡貼在下坡那一列 x=28 的旁邊，由幹線上的**兩個中繼**各分一條線進去。
	#    中繼不吃電，所以錨那條線穿過它們不會被吃掉——這正是不能拿塔當接點的
	#    理由（`sim/FlowNetwork` 的節點先吃滿自己才轉發）。
	["place", "prism", Vector2i(28, 16)],
	["conduit", Vector2i(27, 17), Vector2i(28, 16)],
	["conduit", Vector2i(29, 17), Vector2i(28, 16)],
	["place", "anchor", Vector2i(30, 17)],
	["conduit", Vector2i(30, 17), Vector2i(29, 17)],
	["place", "extractor", Vector2i(24, 13)],
	["conduit", Vector2i(24, 13), Vector2i(26, 15)],
	# (19,15) 那顆礦接**熔爐**而不是 (21,17)：接後者的話那條線會和主幹線
	# (13,9)→(21,17) 同一個斜向、疊在一起（B1.6.1）。
	["place", "extractor", Vector2i(19, 15)],
	["conduit", Vector2i(19, 15), Vector2i(17, 17)],
	["place", "knell", Vector2i(26, 13)],
	["conduit", Vector2i(26, 13), Vector2i(26, 15)],
	["place", "silo", Vector2i(27, 16)],
	["conduit", Vector2i(27, 16), Vector2i(26, 17)],
	# ★ 第三台發電機。全開的防線要 55 能量/秒，兩台只有 40——
	#    這一關的峰值電力算術是前四關的總和。
	# ★ 第三台發電機要掛在**幹線的下游**，也就是塔群這一側。
	#    掛到上游（(22,16)→(21,17)）的話它那 20 能量/秒得跟其他所有東西
	#    一起擠過 (21,17)→(26,17) 那一段，塔全部餓著而頂欄卻顯示供給 60。
	#    這是「能量是流率不是水池」在關卡佈局上的直接後果（§3.1）。
	["place", "generator", Vector2i(25, 16)],
	["conduit", Vector2i(25, 16), Vector2i(26, 17)],

	["wait", 400],

	# ⑤ ★ 合金到帳：幹線加粗到 2 級，撐得起整條南緣。
	["upgrade", Vector2i(13, 9), Vector2i(21, 17), 2],
	["upgrade", Vector2i(21, 17), Vector2i(26, 17), 2],
	["upgrade", Vector2i(7, 7), Vector2i(15, 7), 1],
	["upgrade", Vector2i(15, 7), Vector2i(23, 7), 1],
	# ★ 這一段要加粗到 2 級（cap 22）：稜鏡當接點之後，**錨在它的下游**——
	#    稜鏡吃掉 20 之後還得留得下錨的 4，不然核心旁邊那座塔一發都打不出來
	#    （而頂欄會顯示供給 60，因為問題從來不在發電量上）。
	["upgrade", Vector2i(26, 17), Vector2i(27, 17), 2],
	["upgrade", Vector2i(27, 17), Vector2i(29, 17), 1],
	["upgrade", Vector2i(29, 17), Vector2i(29, 16), 1],
	["upgrade", Vector2i(29, 16), Vector2i(31, 14), 1],

	["wait", 400],

	# ⑥ 碎浪守下坡段：140 礦砂 ＋ 60 合金，全案最貴的一座塔。
	["place", "breaker", Vector2i(26, 11)],
	["conduit", Vector2i(26, 11), Vector2i(26, 13)],
	# ★ 東側防線全開要 45 能量/秒（稜鏡 20 ＋ 碎浪 12 ＋ 潮鳴 9 ＋ 錨 4），
	#    而每一條進去的線預設只有 10——**第三台發電機自己那條線就是第一個瓶頸**
	#    （20 的輸出塞不進 cap 10，§7.2 那一課的最後一次考試）。
	#    這幾段擺在最後：2 級加粗一條要 20 合金，五條就是 100，得等熔爐煉出來。
	["upgrade", Vector2i(25, 16), Vector2i(26, 17), 2],
	["upgrade", Vector2i(26, 17), Vector2i(26, 15), 1],
	# 潮鳴／碎浪那條支線**刻意不加粗**：合金已經花完了（五條 2 級 ＝ 100），
	# 而參考解本來就不該是最佳解——它只要證明這一關過得了。
	["upgrade", Vector2i(26, 15), Vector2i(26, 13), 1],
]


## 五關，**依序**。索引即關卡序（第 N 關解鎖第 N+1 關，§7.9）。
##
## ★ `star_throughput` 是**實測校準**的，不是拍腦袋：B1.2 用 `campaign_test`
## 把每一關的參考解跑到底量出產能積分（0.80／0.48／0.38／0.29／0.19），
## 門檻取它的 1.3–2 倍。所以三星的意思很具體：**你的產線得比「剛好夠打」
## 那一版好一半以上**。門檻**隨關卡遞減**不是筆誤——後面的圖更長（導管更多）、
## 消費者更多（熔爐與第三台發電機都吃礦砂），而積分的分母含整局時間。
const LEVELS := [
	{
		"map": L1, "demo": L1_DEMO, "unlocked": L1_BUILD,
		"star_throughput": 1.0, "reward": 30,
		"lesson": "礦砂 → 能量 → 塔：一條線走完核心循環",
	},
	{
		"map": L2, "demo": L2_DEMO, "unlocked": L2_BUILD,
		"star_throughput": 0.7, "reward": 40,
		"lesson": "峰值電力：一座稜鏡吃掉一整台發電機，儲槽補赤字",
	},
	{
		"map": L3, "demo": L3_DEMO, "unlocked": L3_BUILD,
		"star_throughput": 0.6, "reward": 55,
		"lesson": "一座橋就是一條幹線：北岸的產能全擠在它身上",
	},
	{
		"map": L4, "demo": L4_DEMO, "unlocked": L4_BUILD,
		"star_throughput": 0.5, "reward": 70,
		"lesson": "第三資源：合金把幹線加粗到 22，一條線才餵得飽稜鏡",
	},
	{
		"map": L5, "demo": L5_DEMO, "unlocked": L5_BUILD,
		"star_throughput": 0.4, "reward": 90,
		"lesson": "全解鎖綜合考：三座橋、礦在對岸、五波混編",
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
