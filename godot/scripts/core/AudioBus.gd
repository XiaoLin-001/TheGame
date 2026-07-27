extends Node
## 音訊匯流排與全域靜音（autoload）。
##
## 鐵律 2（30_TECH_DESIGN.md §4.1）：TL_SHOT 或 TL_MUTE 存在時自動全域靜音。
## **絕不在沒有測試鉤子的情況下開遊戲視窗做自動化驗證** —— 使用者可能正在工作。
##
## 分軌匯流排（BGM／SFX／UI）與音量滑桿排在 B1.5，本批只做 Master 靜音。

var muted: bool = false


func _ready() -> void:
	muted = Env.want_mute()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if muted:
		print("[TL] audio muted")


func set_muted(v: bool) -> void:
	muted = v
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), v)
