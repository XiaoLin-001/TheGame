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

const L6_DEMO := [
	# ① 兩條過橋線，在 y=7 併成北岸幹線。
	["place", "relay", Vector2i(10, 7)],
	["place", "extractor", Vector2i(10, 0)],
	["conduit", Vector2i(10, 0), Vector2i(10, 7)],
	["place", "relay", Vector2i(18, 7)],
	["place", "extractor", Vector2i(18, 0)],
	["conduit", Vector2i(18, 0), Vector2i(18, 7)],
	["conduit", Vector2i(10, 7), Vector2i(18, 7)],
	["place", "extractor", Vector2i(7, 7)],
	["conduit", Vector2i(7, 7), Vector2i(10, 7)],
	["place", "extractor", Vector2i(4, 10)],
	["conduit", Vector2i(4, 10), Vector2i(7, 7)],
	["place", "extractor", Vector2i(14, 11)],
	["conduit", Vector2i(14, 11), Vector2i(18, 7)],
	# ② 幹線斜切到東南角的防線區。
	#
	#    ⚠ **每一格都要離路徑 2 格以上**。第一版把轉接的中繼放在 (23,12)，
	#    它緊貼下坡列的最後一格 (24,12)——walk-by 每 tick 啃相鄰 1 格（§3.5），
	#    於是**整條幹線在第二波就被咬斷**，發電機斷糧、稜鏡沒電、核心自己撐。
	#    實跑的樣子是「產能 0.12、擊殺 26、核心 −4」：看起來像防線太弱，
	#    真正壞掉的是**一格中繼的位置**。
	["place", "relay", Vector2i(22, 11)],
	["conduit", Vector2i(18, 7), Vector2i(22, 11)],
	["place", "relay", Vector2i(22, 14)],
	["conduit", Vector2i(22, 11), Vector2i(22, 14)],
	["place", "extractor", Vector2i(21, 14)],
	["conduit", Vector2i(21, 14), Vector2i(22, 14)],

	["wait", 250],   # 25 秒：先讓產線賺出防線的錢

	# ③ ★ 幹線走 y=14 那一列，**發電機掛在支線上、不串在幹線裡**。
	#
	#    ⚠ 第一版把兩台發電機直接串在幹線上（幹線 → 甲 → 樞紐 → 乙 → 核心）。
	#    它**通關了**，而且核心只掉 55——但產能積分是 0.13，剩了 1086 礦砂沒花。
	#    原因是節點先吃滿自己才轉發（`sim/FlowNetwork`）：幹線 cap 10，
	#    兩台發電機各吃 4，**進核心的只剩 2 礦砂/秒**。
	#    「通關了」和「產線是好的」是兩件事，而只有後者拿得到三星。
	["place", "relay", Vector2i(23, 14)],
	["conduit", Vector2i(22, 14), Vector2i(23, 14)],
	["place", "relay", Vector2i(25, 14)],
	["conduit", Vector2i(23, 14), Vector2i(25, 14)],
	["place", "relay", Vector2i(27, 14)],
	["conduit", Vector2i(25, 14), Vector2i(27, 14)],
	["conduit", Vector2i(27, 14), Vector2i(27, 12)],   # 礦砂進核心
	["place", "generator", Vector2i(22, 15)],
	["conduit", Vector2i(22, 14), Vector2i(22, 15)],
	# 東邊那台**兩條出線**：一條餵稜鏡、一條餵兩座錨。
	# 併成一條的話它自己那 20 塞不進 cap 10（§3.1「能量是流率不是水池」）。
	["place", "generator", Vector2i(26, 15)],
	["conduit", Vector2i(26, 15), Vector2i(25, 14)],
	["conduit", Vector2i(26, 15), Vector2i(27, 14)],

	["wait", 200],

	# ④ ★ 稜鏡貼在下坡列 x=24 的正下方，**和那九格同列**。
	#    兩條進線各 10 ＝ 20（§7.2 的菱形，第 2 關那一課在這裡再考一次），
	#    而且**兩條來自不同的發電機**——同一台的兩條會在它自己的出口就塞住。
	["place", "prism", Vector2i(24, 15)],
	["conduit", Vector2i(23, 14), Vector2i(24, 15)],
	["conduit", Vector2i(25, 14), Vector2i(24, 15)],
	# ⑤ 兩座錨守核心：**漏過來的必須有人打得到**（稜鏡的貫穿線搆不到核心）。
	#    (28,14)／(28,15) 而不是 (28,13)：後者貼著核心那一格 (27,12) 的破壞半徑。
	#    守核心的塔**自己要站在破壞半徑外**，否則它和核心一起被啃。
	["place", "anchor", Vector2i(28, 14)],
	["conduit", Vector2i(27, 14), Vector2i(28, 14)],
	["place", "anchor", Vector2i(28, 15)],
	["conduit", Vector2i(27, 14), Vector2i(28, 15)],

	["wait", 250],

	# ⑥ ★ 幹線加粗到 1 級（cap 16，**只要礦砂不要合金**，§7.2）。
	#    cap 10 的時候發電機吃掉 8、核心拿 2；加粗之後核心才拿得到像樣的量。
	#    這一關的合金留給玩家自己決定要不要煉——參考解不是最佳解。
	["upgrade", Vector2i(18, 7), Vector2i(22, 11), 1],
	["upgrade", Vector2i(22, 11), Vector2i(22, 14), 1],
	["upgrade", Vector2i(22, 14), Vector2i(23, 14), 1],
	["upgrade", Vector2i(23, 14), Vector2i(25, 14), 1],
	["upgrade", Vector2i(25, 14), Vector2i(27, 14), 1],
	["upgrade", Vector2i(27, 14), Vector2i(27, 12), 1],
	["upgrade", Vector2i(10, 7), Vector2i(18, 7), 1],
]


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

const L7_DEMO := [
	# ① 兩條過橋線，y=7 併成北岸幹線。
	["place", "relay", Vector2i(9, 7)],
	["place", "extractor", Vector2i(9, 0)],
	["conduit", Vector2i(9, 0), Vector2i(9, 7)],
	["place", "relay", Vector2i(18, 7)],
	["place", "extractor", Vector2i(18, 0)],
	["conduit", Vector2i(18, 0), Vector2i(18, 7)],
	["conduit", Vector2i(9, 7), Vector2i(18, 7)],
	["place", "extractor", Vector2i(6, 10)],
	["conduit", Vector2i(6, 10), Vector2i(9, 7)],
	["place", "extractor", Vector2i(3, 13)],
	["conduit", Vector2i(3, 13), Vector2i(6, 10)],
	["place", "extractor", Vector2i(13, 12)],
	["conduit", Vector2i(13, 12), Vector2i(18, 7)],
	# ② 幹線斜切到東南角。轉接點 (24,13) 離下坡列 x=26 有 2 格——
	#    第 6 關就是在這一格上摔的（貼著路徑的中繼會被 walk-by 咬斷）。
	["place", "relay", Vector2i(24, 13)],
	["conduit", Vector2i(18, 7), Vector2i(24, 13)],
	["place", "relay", Vector2i(24, 15)],
	["conduit", Vector2i(24, 13), Vector2i(24, 15)],
	["place", "extractor", Vector2i(23, 16)],
	["conduit", Vector2i(23, 16), Vector2i(24, 15)],

	["wait", 250],

	# ③ 幹線走 y=15，發電機掛支線（第 6 關量出來的那一課：串在幹線裡的
	#    發電機會把進核心的礦砂吃到剩兩點）。
	["place", "relay", Vector2i(25, 15)],
	["conduit", Vector2i(24, 15), Vector2i(25, 15)],
	["place", "relay", Vector2i(27, 15)],
	["conduit", Vector2i(25, 15), Vector2i(27, 15)],
	["place", "relay", Vector2i(29, 15)],
	["conduit", Vector2i(27, 15), Vector2i(29, 15)],
	["conduit", Vector2i(29, 15), Vector2i(29, 13)],   # 礦砂進核心
	# (23,15) 而不是 (23,16)：後者已經是那顆礦的採集器
	# （改礦點座標時撞上的——兩個「往樞紐斜過去」的位置本來就只有那幾格）。
	["place", "generator", Vector2i(23, 15)],
	["conduit", Vector2i(23, 15), Vector2i(24, 15)],
	["place", "generator", Vector2i(28, 16)],
	["conduit", Vector2i(28, 16), Vector2i(27, 15)],
	["conduit", Vector2i(28, 16), Vector2i(29, 15)],

	["wait", 200],

	# ④ 稜鏡貼在下坡列 x=26 的正下方，兩條進線來自**不同的發電機**。
	["place", "prism", Vector2i(26, 16)],
	["conduit", Vector2i(25, 15), Vector2i(26, 16)],
	["conduit", Vector2i(27, 15), Vector2i(26, 16)],
	# ⑤ ★ 潮鳴仍然蓋——它對苔群與甲殼有效，對潛涌沒效。
	#    這一關的重點不是「別蓋光環」，是「光環不是全部的答案」。
	["place", "knell", Vector2i(25, 16)],
	["conduit", Vector2i(25, 15), Vector2i(25, 16)],
	# ⑥ 兩座錨守核心（潛涌會直接衝到底，而稜鏡的貫穿線搆不到核心）。
	["place", "anchor", Vector2i(30, 15)],
	["conduit", Vector2i(29, 15), Vector2i(30, 15)],
	["place", "anchor", Vector2i(30, 16)],
	["conduit", Vector2i(29, 15), Vector2i(30, 16)],
	# ⑦ ★ 第三台發電機，**擺在西半邊、兩條出線**。
	#
	#    ⚠ 第一版這裡是一座儲槽，而這一關**輸掉**（核心 −2、擊殺 55）。
	#    原因不是總電力不夠（40 對 37），是**西半邊全部吊在一條 cap 10 的邊上**：
	#    潮鳴 9 ＋ 稜鏡的西腿 10 ＝ 19 要從 (24,15) 擠過去，而那條線只有 10。
	#    頂欄會顯示供給 40、需求 37，看起來綽綽有餘——真正的赤字在一條邊上。
	#    這正是 §3.1「能量是流率不是水池」最貴的一次示範，而儲槽救不了它
	#    （儲槽的充放電**同樣受它自己那條導管的 cap 約束**）。
	["place", "generator", Vector2i(24, 16)],
	["conduit", Vector2i(24, 16), Vector2i(24, 15)],
	["conduit", Vector2i(24, 16), Vector2i(25, 15)],

	["wait", 250],

	# ⑧ 幹線加粗到 1 級（cap 16，只要礦砂）。
	["upgrade", Vector2i(18, 7), Vector2i(24, 13), 1],
	["upgrade", Vector2i(24, 13), Vector2i(24, 15), 1],
	["upgrade", Vector2i(24, 15), Vector2i(25, 15), 1],
	["upgrade", Vector2i(25, 15), Vector2i(27, 15), 1],
	["upgrade", Vector2i(27, 15), Vector2i(29, 15), 1],
	["upgrade", Vector2i(29, 15), Vector2i(29, 13), 1],
	["upgrade", Vector2i(9, 7), Vector2i(18, 7), 1],
]


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

const L8_DEMO := [
	# ① 三條過橋線，y=7 併成北岸幹線。
	["place", "relay", Vector2i(8, 7)],
	["place", "extractor", Vector2i(8, 0)],
	["conduit", Vector2i(8, 0), Vector2i(8, 7)],
	["place", "relay", Vector2i(16, 7)],
	["place", "extractor", Vector2i(16, 0)],
	["conduit", Vector2i(16, 0), Vector2i(16, 7)],
	["place", "relay", Vector2i(24, 7)],
	["place", "extractor", Vector2i(24, 0)],
	["conduit", Vector2i(24, 0), Vector2i(24, 7)],
	["conduit", Vector2i(8, 7), Vector2i(16, 7)],
	["conduit", Vector2i(16, 7), Vector2i(24, 7)],
	["place", "extractor", Vector2i(5, 10)],
	["conduit", Vector2i(5, 10), Vector2i(8, 7)],
	["place", "extractor", Vector2i(2, 13)],
	["conduit", Vector2i(2, 13), Vector2i(5, 10)],
	["place", "extractor", Vector2i(13, 10)],
	["conduit", Vector2i(13, 10), Vector2i(16, 7)],
	# ② 幹線斜切到東南角。
	["place", "relay", Vector2i(26, 9)],
	["conduit", Vector2i(24, 7), Vector2i(26, 9)],
	["place", "relay", Vector2i(26, 15)],
	["conduit", Vector2i(26, 9), Vector2i(26, 15)],
	["place", "extractor", Vector2i(20, 15)],
	["conduit", Vector2i(20, 15), Vector2i(26, 15)],

	["wait", 250],

	# ③ 幹線走 y=15，發電機全部掛支線。
	["place", "relay", Vector2i(27, 15)],
	["conduit", Vector2i(26, 15), Vector2i(27, 15)],
	["place", "relay", Vector2i(29, 15)],
	["conduit", Vector2i(27, 15), Vector2i(29, 15)],
	["place", "relay", Vector2i(31, 15)],
	["conduit", Vector2i(29, 15), Vector2i(31, 15)],
	["conduit", Vector2i(31, 15), Vector2i(31, 13)],   # 礦砂進核心
	["place", "generator", Vector2i(25, 16)],
	["conduit", Vector2i(25, 16), Vector2i(26, 15)],
	["place", "generator", Vector2i(30, 16)],
	["conduit", Vector2i(30, 16), Vector2i(29, 15)],
	["conduit", Vector2i(30, 16), Vector2i(31, 15)],

	["wait", 200],

	# ④ 稜鏡貼在下坡列 x=28 的正下方。
	["place", "prism", Vector2i(28, 16)],
	["conduit", Vector2i(27, 15), Vector2i(28, 16)],
	["conduit", Vector2i(29, 15), Vector2i(28, 16)],
	# ⑤ 兩座錨守核心 ＋ 回收者（癒殼價值 34，回收 60% 換能量，
	#    正好補這一關第一次出現的電力赤字）。
	["place", "anchor", Vector2i(32, 15)],
	["conduit", Vector2i(31, 15), Vector2i(32, 15)],
	["place", "anchor", Vector2i(32, 16)],
	["conduit", Vector2i(31, 15), Vector2i(32, 16)],
	["place", "reclaimer", Vector2i(27, 16)],
	["conduit", Vector2i(27, 15), Vector2i(27, 16)],

	["wait", 250],

	# ⑥ ★ 第三台發電機。**掛在防線這一側**（幹線的下游）——
	#    掛到上游的話那 20 得跟其他所有東西擠過同一段，
	#    塔全部餓著而頂欄卻顯示供給充足（§3.1，第 5 關那一課的複習）。
	["place", "generator", Vector2i(26, 16)],
	["conduit", Vector2i(26, 16), Vector2i(26, 15)],
	# ⑦ 幹線加粗到 1 級。
	["upgrade", Vector2i(24, 7), Vector2i(26, 9), 1],
	["upgrade", Vector2i(26, 9), Vector2i(26, 15), 1],
	["upgrade", Vector2i(26, 15), Vector2i(27, 15), 1],
	["upgrade", Vector2i(27, 15), Vector2i(29, 15), 1],
	["upgrade", Vector2i(29, 15), Vector2i(31, 15), 1],
	["upgrade", Vector2i(31, 15), Vector2i(31, 13), 1],
	["upgrade", Vector2i(8, 7), Vector2i(16, 7), 1],
	["upgrade", Vector2i(16, 7), Vector2i(24, 7), 1],
]


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

const L9_DEMO := [
	# ① 三條過橋線，y=8 併成北岸幹線。
	["place", "relay", Vector2i(8, 8)],
	["place", "extractor", Vector2i(8, 1)],
	["conduit", Vector2i(8, 1), Vector2i(8, 8)],
	["place", "relay", Vector2i(16, 8)],
	["place", "extractor", Vector2i(16, 1)],
	["conduit", Vector2i(16, 1), Vector2i(16, 8)],
	["place", "relay", Vector2i(24, 8)],
	["place", "extractor", Vector2i(24, 1)],
	["conduit", Vector2i(24, 1), Vector2i(24, 8)],
	["conduit", Vector2i(8, 8), Vector2i(16, 8)],
	["conduit", Vector2i(16, 8), Vector2i(24, 8)],
	["place", "extractor", Vector2i(5, 11)],
	["conduit", Vector2i(5, 11), Vector2i(8, 8)],
	["place", "extractor", Vector2i(12, 12)],
	["conduit", Vector2i(12, 12), Vector2i(16, 8)],
	# ② 幹線斜切到東南角，再垂直落到防線那一列。
	["place", "relay", Vector2i(26, 10)],
	["conduit", Vector2i(24, 8), Vector2i(26, 10)],
	["place", "relay", Vector2i(26, 16)],
	["conduit", Vector2i(26, 10), Vector2i(26, 16)],
	["place", "extractor", Vector2i(22, 16)],
	["conduit", Vector2i(22, 16), Vector2i(26, 16)],

	["wait", 250],

	# ③ 幹線走 y=16，發電機全部掛支線（第 6 關量出來的那一課）。
	["place", "relay", Vector2i(28, 16)],
	["conduit", Vector2i(26, 16), Vector2i(28, 16)],
	["place", "relay", Vector2i(31, 16)],
	["conduit", Vector2i(28, 16), Vector2i(31, 16)],
	["place", "relay", Vector2i(33, 16)],
	["conduit", Vector2i(31, 16), Vector2i(33, 16)],
	["conduit", Vector2i(33, 16), Vector2i(33, 14)],   # 礦砂進核心
	["place", "generator", Vector2i(25, 17)],
	["conduit", Vector2i(25, 17), Vector2i(26, 16)],
	["place", "generator", Vector2i(27, 17)],
	["conduit", Vector2i(27, 17), Vector2i(28, 16)],
	["place", "generator", Vector2i(32, 17)],
	["conduit", Vector2i(32, 17), Vector2i(31, 16)],
	["conduit", Vector2i(32, 17), Vector2i(33, 16)],

	["wait", 200],

	# ④ 稜鏡貼在下坡列 x=30 的正下方，兩條進線來自**不同的發電機**
	#    （西邊那條繞 (29,17)，東邊那條直接從 (31,16) 下來）。
	["place", "relay", Vector2i(29, 17)],
	["conduit", Vector2i(28, 16), Vector2i(29, 17)],
	["place", "prism", Vector2i(30, 17)],
	["conduit", Vector2i(29, 17), Vector2i(30, 17)],
	["conduit", Vector2i(31, 16), Vector2i(30, 17)],
	# ⑤ 兩座錨守核心 ＋ 潮鳴（對苔群與癒殼有效，對潛涌沒效——這一關同時有三種）。
	["place", "anchor", Vector2i(34, 16)],
	["conduit", Vector2i(33, 16), Vector2i(34, 16)],
	["place", "anchor", Vector2i(34, 17)],
	["conduit", Vector2i(33, 16), Vector2i(34, 17)],
	["place", "knell", Vector2i(28, 17)],
	["conduit", Vector2i(28, 16), Vector2i(28, 17)],

	["wait", 250],

	# ⑥ 幹線加粗到 1 級。
	["upgrade", Vector2i(24, 8), Vector2i(26, 10), 1],
	["upgrade", Vector2i(26, 10), Vector2i(26, 16), 1],
	["upgrade", Vector2i(26, 16), Vector2i(28, 16), 1],
	["upgrade", Vector2i(28, 16), Vector2i(31, 16), 1],
	["upgrade", Vector2i(31, 16), Vector2i(33, 16), 1],
	["upgrade", Vector2i(33, 16), Vector2i(33, 14), 1],
	["upgrade", Vector2i(8, 8), Vector2i(16, 8), 1],
	["upgrade", Vector2i(16, 8), Vector2i(24, 8), 1],
]


# ── 第 10 關「深喉」──────────────────────────────────────────────────
## **六種敵人全上**，第二幕的畢業考。六波，最後一波六種同時出場。
##
## 這一關的參考解是全案唯一一份同時用上**熔爐 → 合金 → 碎浪**與
## 稜鏡菱形與潮鳴的佈局：苔群要濺射、甲殼要破甲、癒殼要爆發、潛涌要單體。
## 一種塔擋不住六條規則，而這正是第一幕十顆按鈕存在的理由。
const L10 := {
	"id": "deepthroat",
	"name": "深喉",
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

const L10_DEMO := [
	# ① 四座橋，**併成兩條獨立的幹線**（西邊兩座、東邊兩座）。
	#
	#    ★ 這是這一關和前面九關最大的結構差異，而它是量出來的：
	#      全部併成一條的版本產能積分 **0.05**——下游掛著三台發電機（12 礦砂/秒）
	#      **加一座熔爐（8 礦砂/秒，而且待機也吃 10 能量/秒）**，
	#      而 1 級的 cap 只有 16。進核心的幾乎是 0。
	#      加粗到 2 級要合金，而合金正是那座熔爐要煉的東西——**先有雞還是先有蛋**。
	#      兩條線把頻寬直接翻倍，一塊合金都不用，而地圖本來就給了四座橋。
	["place", "relay", Vector2i(6, 8)],
	["place", "extractor", Vector2i(6, 1)],
	["conduit", Vector2i(6, 1), Vector2i(6, 8)],
	["place", "relay", Vector2i(14, 8)],
	["place", "extractor", Vector2i(14, 1)],
	["conduit", Vector2i(14, 1), Vector2i(14, 8)],
	["conduit", Vector2i(6, 8), Vector2i(14, 8)],
	["place", "extractor", Vector2i(4, 10)],
	["conduit", Vector2i(4, 10), Vector2i(6, 8)],
	["place", "extractor", Vector2i(12, 10)],
	["conduit", Vector2i(12, 10), Vector2i(14, 8)],
	["place", "relay", Vector2i(22, 8)],
	["place", "extractor", Vector2i(22, 1)],
	["conduit", Vector2i(22, 1), Vector2i(22, 8)],
	["place", "relay", Vector2i(28, 8)],
	["place", "extractor", Vector2i(28, 1)],
	["conduit", Vector2i(28, 1), Vector2i(28, 8)],
	["conduit", Vector2i(22, 8), Vector2i(28, 8)],
	# ② 西線：斜切到 y=16，橫過去接防線的樞紐。
	["place", "relay", Vector2i(22, 16)],
	["conduit", Vector2i(14, 8), Vector2i(22, 16)],
	["place", "extractor", Vector2i(25, 13)],
	["conduit", Vector2i(25, 13), Vector2i(22, 16)],
	["place", "relay", Vector2i(29, 16)],
	["conduit", Vector2i(22, 16), Vector2i(29, 16)],
	# ③ 東線：斜切下來再垂直落到同一個樞紐。
	["place", "relay", Vector2i(30, 10)],
	["conduit", Vector2i(28, 8), Vector2i(30, 10)],
	["place", "relay", Vector2i(30, 17)],
	["conduit", Vector2i(30, 10), Vector2i(30, 17)],
	["conduit", Vector2i(29, 16), Vector2i(30, 17)],

	["wait", 250],

	# ④ 幹線走 y=17，**串過** (31,17)（不從它頭上跨過去，否則和支線疊兩格）。
	["place", "relay", Vector2i(31, 17)],
	["conduit", Vector2i(30, 17), Vector2i(31, 17)],
	["place", "relay", Vector2i(33, 17)],
	["conduit", Vector2i(31, 17), Vector2i(33, 17)],
	["place", "relay", Vector2i(35, 17)],
	["conduit", Vector2i(33, 17), Vector2i(35, 17)],
	["conduit", Vector2i(35, 17), Vector2i(35, 15)],   # 礦砂進核心
	# ★ 熔爐**直接掛在樞紐上**，不排在發電機下游。
	#    節點先吃滿自己才轉發，而它一個人就要 8 礦砂/秒——排在後面的話它煉不出來。
	["place", "smelter", Vector2i(29, 17)],
	["conduit", Vector2i(29, 17), Vector2i(30, 17)],
	# ⑤ 四台發電機，全部掛支線。防線全開要 59 能量/秒
	#    （稜鏡 20 ＋ 碎浪 12 ＋ 潮鳴 9 ＋ 兩座錨 8 ＋ **熔爐待機 10**），
	#    三台的 60 是剃刀邊緣——熔爐那 10 點是前九關都沒算過的一筆。
	#    ⚠ 全部擺在 y=18，**不擺在幹線那一列**：擺在 (32,17) 的第一版，
	#      它左右兩條支線和幹線 (31,17)→(33,17) 各疊了兩格，當場 `overlaps`。
	#      幹線那一列是**過道**，不是可以停東西的地方。
	#    ⚠ 每一台都要**兩條出線**：一台 20 能量/秒塞不進一條 cap 10——
	#      只接一條的話，帳面上四台 80，實際只送得出 40。
	["place", "generator", Vector2i(29, 18)],
	["conduit", Vector2i(29, 18), Vector2i(30, 17)],
	["conduit", Vector2i(29, 18), Vector2i(29, 17)],
	["place", "generator", Vector2i(28, 18)],
	["conduit", Vector2i(28, 18), Vector2i(29, 17)],
	["place", "generator", Vector2i(34, 18)],
	["conduit", Vector2i(34, 18), Vector2i(33, 17)],
	["conduit", Vector2i(34, 18), Vector2i(35, 17)],
	["place", "generator", Vector2i(33, 18)],
	["conduit", Vector2i(33, 18), Vector2i(33, 17)],

	["wait", 200],

	# ⑥ 稜鏡貼在下坡列 x=32 的正下方，兩條進線來自不同的發電機。
	["place", "prism", Vector2i(32, 18)],
	["conduit", Vector2i(31, 17), Vector2i(32, 18)],
	["conduit", Vector2i(33, 17), Vector2i(32, 18)],
	# 第三條進線直接來自旁邊那台發電機：稜鏡吃 20，而前兩條各只給得起 10，
	# 兩條剛好打平就沒有任何餘裕給滿足率低於 1 的那些 tick。
	["conduit", Vector2i(33, 18), Vector2i(32, 18)],
	# ⑦ 兩座錨守核心 ＋ 潮鳴。
	["place", "anchor", Vector2i(36, 17)],
	["conduit", Vector2i(35, 17), Vector2i(36, 17)],
	["place", "anchor", Vector2i(36, 18)],
	["conduit", Vector2i(35, 17), Vector2i(36, 18)],
	["place", "knell", Vector2i(31, 18)],
	["conduit", Vector2i(31, 17), Vector2i(31, 18)],

	["wait", 300],

	# ⑧ 兩條幹線都加粗到 1 級（cap 16，只要礦砂）。
	["upgrade", Vector2i(28, 8), Vector2i(30, 10), 1],
	["upgrade", Vector2i(30, 10), Vector2i(30, 17), 1],
	["upgrade", Vector2i(22, 16), Vector2i(29, 16), 1],
	["upgrade", Vector2i(29, 16), Vector2i(30, 17), 1],
	["upgrade", Vector2i(14, 8), Vector2i(22, 16), 1],
	["upgrade", Vector2i(30, 17), Vector2i(31, 17), 1],
	["upgrade", Vector2i(31, 17), Vector2i(33, 17), 1],
	["upgrade", Vector2i(33, 17), Vector2i(35, 17), 1],
	["upgrade", Vector2i(35, 17), Vector2i(35, 15), 1],
	["upgrade", Vector2i(6, 8), Vector2i(14, 8), 1],
	["upgrade", Vector2i(22, 8), Vector2i(28, 8), 1],

	["wait", 500],

	# ⑨ ★ 碎浪（140 礦砂 ＋ 60 合金）。苔群一次七隻，它是這一關唯一的濺射。
	#    **兩條進線**：12 能量/秒塞不進一條 cap 10（§3.1 的老規矩）。
	["place", "breaker", Vector2i(28, 17)],
	["conduit", Vector2i(28, 17), Vector2i(29, 17)],
	["conduit", Vector2i(28, 17), Vector2i(28, 18)],
	# ⑩ ★ 剩下的合金花在**幹線**上（2 級，cap 22）。
	#    第一版把合金全存著——收尾時帳上 1310 塊，而產能積分只有 0.23。
	#    熔爐吃掉 8 礦砂/秒去煉一堆沒有用途的合金，那不是產線，是倉庫。
	["upgrade", Vector2i(30, 10), Vector2i(30, 17), 1],
	["upgrade", Vector2i(29, 16), Vector2i(30, 17), 1],
	["upgrade", Vector2i(30, 17), Vector2i(31, 17), 1],
	["upgrade", Vector2i(31, 17), Vector2i(33, 17), 1],
	["upgrade", Vector2i(33, 17), Vector2i(35, 17), 1],
	["upgrade", Vector2i(35, 17), Vector2i(35, 15), 1],
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
	{
		"map": L6, "demo": L6_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.55, "reward": 100,
		"lesson": "苔群：六隻擠在 6 格內，貫穿與濺射一發打完整段",
	},
	{
		"map": L7, "demo": L7_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.40, "reward": 110,
		"lesson": "潛涌：免疫減速，潮鳴的光環對它無效",
	},
	{
		"map": L8, "demo": L8_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.60, "reward": 125,
		"lesson": "癒殼：每秒回最大血 4%，dps 追不上就打不死",
	},
	{
		"map": L9, "demo": L9_DEMO, "unlocked": ACT2_BUILD,
		"star_throughput": 0.35, "reward": 140,
		"lesson": "混編：苔群、潛涌、癒殼兩兩同時來，一份電要分給三種答案",
	},
	{
		"map": L10, "demo": L10_DEMO, "unlocked": ACT2_BUILD,
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
