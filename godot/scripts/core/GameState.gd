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
const VERSION := "0.26.5"

const GAME_NAME := "潮與線"
const GAME_NAME_EN := "Tide & Line"
const TAGLINE := "你的生產線就是你的防線"

## 持久資料。結構見 30_TECH_DESIGN.md §3。
## **原地變更，絕不重新賦值**（§2.3）——重新賦值會讓已持有引用的面板拿到斷裂的舊物件。
var data: Dictionary = {}


const Motion := preload("res://scripts/render/Motion.gd")


func _ready() -> void:
	# autoload 順序把 SaveService 排在 GameState 之前，所以這裡它已經就緒。
	SaveService.load_into(data)
	apply_settings()


## ★ 把存檔裡的設定套到會受影響的地方（B1.4）。**開機一次、設定畫面改一次動一次**，
## 只有這一支——散在各畫面的 `_ready()` 裡讀設定的話，新加一個畫面就多一個
## 會忘記讀的地方，而忘記的那個畫面看起來完全正常。
func apply_settings() -> void:
	var settings: Dictionary = data.get("settings", {})
	AudioBus.apply(settings)
	Motion.reduce = bool(settings.get("reduce_motion", false))
	# ★ 有測試鉤子時不動視窗：`TL_SHOT` 的「同參數在任何機器上拍出同一張圖」
	#   不能取決於這台機器的玩家把解析度設成什麼（RG-61 的同一條紀律）。
	if Env.any_hook():
		return
	if bool(settings.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var sizes: Array = SaveService.RESOLUTIONS
	var i := clampi(int(settings.get("resolution", 0)), 0, sizes.size() - 1)
	DisplayServer.window_set_size(sizes[i])
