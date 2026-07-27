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
	# 測試圖給得寬鬆：B0.3 要能一口氣蓋出「礦砂線 ＋ 發電機 ＋ 儲槽」整套來驗證。
	# 真正吃緊的起始礦砂是關卡設計的事（B0.7 手作圖、B1.2 戰役五關）。
	"start_ore": 300,
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
## 它蓋出 B0.3 要證明的兩件事：
##   ① 礦砂線：採集器 →（45°）→ 中繼 →（過橋 30,9）→ 中繼 → 中繼 → 核心。
##      東岸的核心只能經跨越點抵達——這條線就是「產線往危險方向拉」的字面樣子。
##   ② 能量線：採集器 → 發電機 → 儲槽。**發電機輸出 20 塞不進 cap 10**，
##      那條線立刻滿載變亮（`10_GDD.md` §7.2）。
const SHOAL_DEMO := [
	["place", "relay", Vector2i(28, 9)],
	["place", "relay", Vector2i(33, 9)],
	["place", "relay", Vector2i(33, 13)],
	["place", "extractor", Vector2i(25, 12)],
	["conduit", Vector2i(25, 12), Vector2i(28, 9)],
	["conduit", Vector2i(28, 9), Vector2i(33, 9)],
	["conduit", Vector2i(33, 9), Vector2i(33, 13)],
	["conduit", Vector2i(33, 13), Vector2i(34, 14)],
	["place", "extractor", Vector2i(16, 8)],
	["place", "generator", Vector2i(16, 11)],
	["conduit", Vector2i(16, 8), Vector2i(16, 11)],
	["place", "silo", Vector2i(20, 15)],
	["conduit", Vector2i(16, 11), Vector2i(20, 15)],
]


## 敵人路徑（有序，供 B0.4 的推進使用；B0.3 只用它做建造合法性）。
static func path_of(map: Dictionary) -> Array:
	if String(map.get("id", "")) != "shoal":
		return []
	var cells: Array[Vector2i] = []
	for x in range(0, 31):
		cells.append(Vector2i(x, 4))
	for y in range(5, 15):
		cells.append(Vector2i(30, y))
	for x in range(31, 35):
		cells.append(Vector2i(x, 14))
	return cells


## 這張圖的波次表（`data/Enemies.gd`）。B1.2 的五關各自一張。
static func waves_of(map: Dictionary) -> Array:
	if String(map.get("id", "")) != "shoal":
		return []
	return Enemies.SHOAL_WAVES


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
