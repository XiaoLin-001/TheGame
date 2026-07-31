extends Node
## 音訊匯流排與全域靜音（autoload）。
##
## 鐵律 2（30_TECH_DESIGN.md §4.1）：TL_SHOT 或 TL_MUTE 存在時自動全域靜音。
## **絕不在沒有測試鉤子的情況下開遊戲視窗做自動化驗證** —— 使用者可能正在工作。
##
## ★ B1.4：三條分軌（Master / BGM / SFX）與音量在這裡落地。
## **BGM 與 SFX 目前沒有東西可播**（音源排 B1.5），但滑桿接的是真的匯流排——
## 接一個假的滑桿到 B1.5 再換掉，等於保證那時沒有人記得要換。

## 分軌名稱。BGM 與 SFX 都掛在 Master 底下，所以主音量一動兩邊一起動。
const BUSES := ["BGM", "SFX"]

## 靜音時實際套用的分貝。`-80` 是 Godot 的實質無聲下限。
const SILENT_DB := -80.0

var muted: bool = false


func _ready() -> void:
	_ensure_buses()
	muted = Env.want_mute()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if muted:
		print("[TL] audio muted")


## 專案裡只宣告了 Master，其餘在執行期補上。
## **寫在程式碼而不是 `default_bus_layout.tres`**：分軌名稱要和 `settings` 的
## 鍵對得起來，而那個對應關係放在同一個檔案裡才不會各改各的。
func _ensure_buses() -> void:
	for name: String in BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")


## 把 `settings` 的三個 0..1 音量套到匯流排上。
##
## ★ **靜音時不寫音量**：測試鉤子在跑的時候把音量寫回去，等於讓一個
## 「絕不出聲」的承諾取決於玩家存檔裡剛好存了什麼（鐵律 2）。
func apply(settings: Dictionary) -> void:
	if muted:
		return
	_set_volume("Master", float(settings.get("master", 0.8)))
	_set_volume("BGM", float(settings.get("bgm", 0.6)))
	_set_volume("SFX", float(settings.get("sfx", 0.8)))


## 0..1 的線性音量 → 分貝。**用 `linear_to_db` 而不是自己乘**：
## 人耳是對數的，線性套上去會讓滑桿的前 20% 什麼都聽不出來、後面又爆掉。
## 0 一律送到 `SILENT_DB`（`linear_to_db(0)` 是 −inf，寫進去會出事）。
func _set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, SILENT_DB if v <= 0.0 else linear_to_db(v))


## 目前的分貝（設定畫面的自檢要能問「這個滑桿真的接到東西了嗎」）。
func volume_db(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return SILENT_DB if i < 0 else AudioServer.get_bus_volume_db(i)
