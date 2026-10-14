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
## `TL_PANEL=battle` 的示範佈局要先推幾個 tick 再交給畫面。
## 預設 860 ＝ 60 秒準備期 ＋ 26 秒戰鬥，正好是敵潮進入塔射程的時刻；
## 給小一點就拍得到準備期（提前召喚倍率、階段色調要兩張圖才比得出來）。
## **`0` ＝ 完全不要示範佈局**，用來拍玩家真正的第一眼（`50_QA_PLAN.md` §4.4）。
var demo_ticks: int = 860
## `TL_CLICKTEST=1`：開局內畫面，**用合成的滑鼠事件真的點地圖**，驗證輸入層通了。
## 由 `screens/Battle.gd` 執行（它才知道格子在螢幕上的哪裡）。
var click_test: bool = false
## ★ `TL_STRESS=1`：局內畫面換成壓力情境（`data/Maps.gd` 的 500 節點／2000 導管），
## **模擬凍結**、只量渲染，跑完 `STRESS_FRAMES` 幀印出幀時間後退出（B1.7、RG-8）。
## 模擬那一半量不到這裡（它每 tick 要好幾秒，會把幀時間整個吃掉），走 `perf_test.gd`。
var stress: bool = false
## ★ `TL_STRESS` 配 `TL_DEMO_TICKS`（真實關卡）時**模擬照常跑**（B3.15）：量的是玩家真正會碰到的渲染——
## 敵人進出、血量與流量每個 tick 在變——而不是「凍結的一格＋假裝每個 tick 全部都變」。
## 合成的壓力場景（沒給 `TL_DEMO_TICKS`）仍然凍結：它單 tick 要 30 秒。
var stress_live: bool = false
## `TL_LEVEL=1..5`：`TL_PANEL=campaign` 時直接進那一關（1-based，0 ＝ 停在關卡選擇）。
## 截圖與 `TL_SIM` 要指定關卡都走這裡。
var level: int = 0
## ★ `TL_FOCUS="x,y,zoom"`：把鏡頭對到某一格並放大 N 倍（B1.6）。
##
## 為什麼要有它：**特效是 0.2 秒、十幾個像素的東西**，在 fit 倍率的全圖截圖上
## 根本判不出好壞——我會一直宣稱「碎片爆做好了」而沒有真的看過它。
## 空字串＝照原本的 fit 全景。
var focus: Vector2i = Vector2i(-1, -1)
var focus_zoom: float = 1.0
## ★ `TL_PICK=wire`：合照那一張改成**選一條導管**（B3.7）。
##
## 同 `TL_FOCUS` 的理由：檢視面板是**純互動狀態**，沒有鉤子就拍不到，
## 於是「導管面板做好了」只能用宣稱的。預設（空字串）選一座塔，維持 B3.6 那張圖。
var pick: String = ""
## ★ `TL_STAGE=3d`：局內畫面用 `Stage3D`（B4.0 脊椎，**實驗性**）。預設 `Stage2D`。
##
## 這是**唯一**讓主畫面知道「哪一種舞台」的地方（`Battle._build_modules()`）。要把它做成玩家的設定時
## （`docs/70_3D_MIGRATION.md` D5），改的也只有這一行判斷。
var stage3d: bool = false
## ★ `TL_PROF=1`：逐段計時（B3.15，`core/Prof.gd`）。要配 `TL_STRESS`——它在量測結束時印報表。
var prof: bool = false


func _ready() -> void:
	shot_path = Env.str_of("TL_SHOT")
	shot_delay = Env.float_of("TL_SHOT_DELAY", 3.0)
	panel = Env.str_of("TL_PANEL")
	naked = Env.flag("TL_NAKED")
	sim_ticks = Env.int_of("TL_SIM", 0)
	demo_ticks = Env.int_of("TL_DEMO_TICKS", 860)
	click_test = Env.flag("TL_CLICKTEST")
	stress = Env.flag("TL_STRESS")
	level = Env.int_of("TL_LEVEL", 0)
	pick = Env.str_of("TL_PICK")
	stage3d = Env.str_of("TL_STAGE").to_lower() == "3d"
	prof = Env.flag("TL_PROF")
	var f := Env.str_of("TL_FOCUS")
	if f != "":
		var parts := f.split(",")
		if parts.size() >= 2:
			focus = Vector2i(int(parts[0]), int(parts[1]))
			focus_zoom = float(parts[2]) if parts.size() >= 3 else 2.0
	# 預設驗局內畫面；明寫 `TL_PANEL` 時尊重它（B1.2 起關卡選擇也要驗一次
	# ——那個畫面的全部價值就是「一顆鈕點得到」）。
	if click_test and panel == "":
		panel = "battle"
	# 壓力情境是局內畫面的事，而且它自己就是佈局——示範佈局要關掉。
	# ★ 但**明寫 `TL_DEMO_TICKS` 時尊重它**（B3.14）：`TL_STRESS=1 TL_PANEL=campaign TL_LEVEL=10
	#   TL_DEMO_TICKS=3000` 量的是**真實關卡**跑到第 3000 tick 時的渲染幀時間（模擬凍結在那一格）——
	#   「壓力情境很慢」不等於「玩家玩到的很慢」，兩者要分開量。
	stress_live = stress and Env.str_of("TL_DEMO_TICKS") != ""
	if stress:
		if panel == "":
			panel = "battle"
		if Env.str_of("TL_DEMO_TICKS") == "":
			demo_ticks = 0
	if click_test:
		# 空地圖才驗得到「點一下有沒有蓋出東西」。但明寫 `TL_DEMO_TICKS` 時尊重它——
		# 那是「我要的是示範佈局跑到第 N tick 的畫面，只是需要有人幫我開浮層」。
		if Env.str_of("TL_DEMO_TICKS") == "":
			demo_ticks = 0

	# ★ 自動化開出來的視窗盡量**不接實體滑鼠**（B3.15，盡力而為）：整個視窗設成滑鼠穿透（只留左上角一個 1 像素的三角形）。
	#   兩個理由：① 截圖要確定性——游標剛好停在視窗上會多出一個落點預覽或按鈕的 hover（campaign_L7 因此差了 5299 個像素、
	#   campaign_L8 差了 4572 個，而那是桌面上的滑鼠，不是程式碼）；② 使用者可能正在工作，自動化的視窗不該吃掉他的點擊
	#   （CLAUDE.md 鐵律 3 的同一個精神）。合成的滑鼠事件走 `Input.parse_input_event()`，不經過作業系統的視窗命中，
	#   所以 `TL_CLICKTEST` 不受影響。⚠ 沒有證明它能 100% 擋住：截圖不相符時先重拍一次，同一處再差才是程式碼。
	if (shot_path != "" or click_test or stress) and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))

	if Env.any_hook():
		print("[TL] hooks: %s" % Env.active(true))
		print("[TL] persist=false（有鉤子時不寫真存檔）")

	# TL_SIM 優先於 TL_SHOT：headless 模擬不需要畫面。
	if sim_ticks > 0:
		_run_sim.call_deferred()
	elif shot_path != "":
		_run_shot()


## headless 模擬：不開視窗跑 N 個 tick，輸出狀態摘要 JSON 到 stdout 後退出。
##
## **平衡調校的主力工具**（`CLAUDE.md`「跑與測」）：它跑的是與 `TL_PANEL=battle`
## 截圖**同一份**示範佈局（`data/Maps.gd` 的 `SHOAL_DEMO`），所以圖上看到的線
## 和這裡印出來的數字保證是同一個局面——截圖不會和數字各說各話。
func _run_sim() -> void:
	var SessionState := preload("res://scripts/game/SessionState.gd")
	var BattleController := preload("res://scripts/game/BattleController.gd")
	var BuildController := preload("res://scripts/game/BuildController.gd")
	var MapsData := preload("res://data/Maps.gd")

	var s: RefCounted = SessionState.new()
	s.setup(MapsData.SHOAL)
	s.alloy = MapsData.DEMO_ALLOY   # 示範佈局的加粗要合金（`Maps.DEMO_ALLOY`）
	var failures := BuildController.apply_ops(s, MapsData.SHOAL_DEMO)
	for _i in sim_ticks:
		BattleController.step(s)

	var flows: Dictionary = {}
	for c: Dictionary in s.conduits:
		flows["%s→%s" % [c["a"], c["b"]]] = snappedf(
			float((s.rates["conduit_flow"] as Dictionary).get(c["id"], 0.0)), 0.01
		)

	# 每座塔的能量滿足率＝它此刻的射速比例（§7.4）。**平衡調校主要看這一欄**：
	# 「蓋滿塔會讓誰餓死」在這裡是一排數字，不是感覺。
	var NodeDefs := preload("res://data/NodeDefs.gd")
	var towers: Dictionary = {}
	for n: Dictionary in s.nodes:
		if not NodeDefs.of(String(n["type"])).get("tower", false):
			continue
		towers["%s%s" % [NodeDefs.label(String(n["type"])), n["cell"]]] = {
			"sat": snappedf(float((s.rates["satisfaction"] as Dictionary).get(n["id"], 1.0)), 0.01),
			"buffer": snappedf(float(n["buffer"]), 0.01),
		}

	# 三態徽章只印**不正常的那些**（`10_GDD.md` §3.1：`正常` 不畫任何東西）。
	# 全部印出來的話這一欄會跟畫面一樣，把要找的那一個埋進 14 行雜訊裡。
	var Score := preload("res://scripts/sim/Score.gd")
	var badges: Dictionary = {}
	for n: Dictionary in s.nodes:
		var st: int = int((s.rates["node_state"] as Dictionary).get(int(n["id"]), 0))
		if st != 0:
			badges["%s%s" % [NodeDefs.label(String(n["type"])), n["cell"]]] = (
				"缺料" if st == 1 else "滿溢"
			)

	var throughput: float = Score.throughput(s.delivered_total, s.tick_count, 0.1)
	print(JSON.stringify({
		"version": GameState.VERSION,
		"seed": Rng.seed_value,
		"map": s.map.get("id", ""),
		"ticks_requested": sim_ticks,
		"ticks_run": s.tick_count,
		"build_failures": failures,
		"state": {
			"phase": s.phase,
			"wave": s.wave_index,
			"enemies": s.enemies.size(),
			"core_hp": snappedf(s.core_hp(), 0.01),
			"ore": snappedf(s.ore, 0.01),
			"ore_in_per_sec": snappedf(float(s.rates["ore_in"]), 0.01),
			"alloy": snappedf(s.alloy, 0.01),
			"alloy_in_per_sec": snappedf(float(s.rates["alloy_in"]), 0.01),
			"power_supply": snappedf(float(s.rates["power_supply"]), 0.01),
			"power_demand": snappedf(float(s.rates["power_demand"]), 0.01),
			"silo": "%.1f/%.0f" % [s.rates["silo_charge"], s.rates["silo_capacity"]],
			"engaged": s.rates["engaged"],
			"kills": s.kills,
			"salvage_ore": snappedf(s.salvage_total, 0.01),
			"reclaimed_power": snappedf(s.reclaimed_total, 0.01),
			"badges": badges,
			"wave_bonus": s.wave_bonus,
			"delivered_total": snappedf(s.delivered_total, 0.01),
			"throughput_score": snappedf(throughput, 0.01),
			"research_data": snappedf(
				Score.research_data(s.wave_index, throughput, s.bonus_data), 0.01
			),
			"towers": towers,
			"nodes": s.nodes.size(),
			"conduit_flow_per_sec": flows,
		},
	}, "  "))
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
