extends RefCounted
## 戰役各關的**參考解**（建造指令腳本）。B3.14 自 `data/Campaign.gd` 抽出。
##
## 參考解是這一關「過得了」的唯一證據：`tests/campaign_test.gd` 把它實跑到底，
## `TL_PANEL=campaign` 的截圖與示範佈局也是同一份腳本。它是**測試與示範的素材**，
## 不是關卡定義——關卡的地圖、解鎖清單、星等門檻、獎勵都在 `data/Campaign.gd`，
## 那邊的 `LEVELS[i]["demo"]` 指向這裡的 `Ln_DEMO`。
##
## 指令只有四種（`BuildController.apply_ops()`／`apply_timeline()` 執行）：
## `["place", 型別, 格]`、`["conduit", 起格, 迄格]`、`["upgrade", 起格, 迄格, 級]`、`["wait", tick]`。
## `wait` 把腳本切成幾段，分段建造才是玩家真正的樣子（說明見 `data/Campaign.gd` 開頭）。

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
