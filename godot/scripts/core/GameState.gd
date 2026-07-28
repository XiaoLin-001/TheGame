extends Node
## 跨局持久狀態的擁有者（autoload）。
##
## VERSION 是**盤點進度的第一手依據**（CLAUDE.md「開工前必做」）。
## 版本規則：`0.<全域批次序號>.<修補>`，一路遞增到 Gold 才 bump 為 1.0.0
## （30_TECH_DESIGN.md §6）。B0.1 = 0.1.0，B4.6 = 0.37.0。
##
## 局內狀態不放這裡 —— 那是 SessionState 的事（§2.3），局結束即銷毀。

## `0.<全域批次序號>.<修補>`。**批次編號就編在版本號裡**，所以這裡不再另存一個
## `BATCH` 字串——B0.6 與 B0.6.1 連續兩批都忘了同步它，標題畫面掛著 `B0.5` 三天。
## 兩個必須手動保持一致的常數，遲早會不一致；批次名稱在 `CHANGELOG.md` 與 git log。
const VERSION := "0.7.2"

const GAME_NAME := "潮與線"
const GAME_NAME_EN := "Tide & Line"
const TAGLINE := "你的生產線就是你的防線"

## 持久資料。結構見 30_TECH_DESIGN.md §3。
## **原地變更，絕不重新賦值**（§2.3）——重新賦值會讓已持有引用的面板拿到斷裂的舊物件。
var data: Dictionary = {}


func _ready() -> void:
	# autoload 順序把 SaveService 排在 GameState 之前，所以這裡它已經就緒。
	SaveService.load_into(data)
