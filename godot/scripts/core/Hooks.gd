extends Node
## 測試鉤子的執行者（autoload，載入順序第一）。
##
## 解析 TL_* 環境變數並執行兩個會「接管整個行程」的鉤子：
##   TL_SHOT  → 等 N 秒 → 截圖 → 退出
##   TL_SIM   → 不開視窗跑 N 個 tick → 輸出 JSON → 退出
## 其餘鉤子只是解析後放著，由需要的人來讀（例：Main 讀 panel / naked）。
##
## 規格：30_TECH_DESIGN.md §4.1

var shot_path: String = ""
var shot_delay: float = 3.0
var panel: String = ""
var naked: bool = false
var sim_ticks: int = 0


func _ready() -> void:
	shot_path = Env.str_of("TL_SHOT")
	shot_delay = Env.float_of("TL_SHOT_DELAY", 3.0)
	panel = Env.str_of("TL_PANEL")
	naked = Env.flag("TL_NAKED")
	sim_ticks = Env.int_of("TL_SIM", 0)

	if Env.any_hook():
		print("[TL] hooks: %s" % Env.active_summary())
		print("[TL] persist=false（有鉤子時不寫真存檔）")

	# TL_SIM 優先於 TL_SHOT：headless 模擬不需要畫面。
	if sim_ticks > 0:
		_run_sim.call_deferred()
	elif shot_path != "":
		_run_shot()


## headless 模擬：跑 N 個 tick，輸出狀態摘要 JSON 到 stdout 後退出。
## B0.1 尚無模擬層（sim/ 於 B0.2 建立），此處先輸出可被解析的骨架，
## 讓下游的平衡工具與回歸腳本現在就能接上格式。
func _run_sim() -> void:
	var out := {
		"version": GameState.VERSION,
		"seed": Rng.seed_value,
		"ticks_requested": sim_ticks,
		"ticks_run": 0,
		"state": {},
		"note": "B0.1：模擬層尚未建立（sim/ 於 B0.2 實作），此為輸出格式骨架",
	}
	print(JSON.stringify(out, "  "))
	get_tree().quit(0)


## 截圖驗證：等動效跑完 → 抓 viewport → 存 png → 退出。
## err=0 才算成功；跑完必須親眼讀那張圖（CLAUDE.md「跑與測」）。
func _run_shot() -> void:
	await get_tree().create_timer(shot_delay).timeout
	# 確保這一幀已經畫完再抓，否則可能截到空畫面。
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("[TL_SHOT] path=%s size=%dx%d err=%d" % [shot_path, img.get_width(), img.get_height(), err])
	get_tree().quit(0 if err == OK else 1)
