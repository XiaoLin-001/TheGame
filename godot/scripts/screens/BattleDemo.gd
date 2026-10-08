extends RefCounted
## 截圖用的示範佈局（TL_PANEL=battle 等）。開發用。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const MapsData := preload("res://data/Maps.gd")

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


#
# 指令表在 `data/Maps.gd`，與 `TL_SIM` 的 headless 跑局共用同一份——
# 截圖與數字看的必須是同一個局面。
func run() -> void:
	# ★ 戰役關卡用它自己的參考解（`data/Campaign.gd`），與 `campaign_test`
	#   跑的是同一份腳本——**截圖與那支測試印出來的數字保證是同一個局面**。
	#   `TL_DEMO_TICKS` 給得夠大就會跑到局末，星等面板才拍得到。
	if not battle.level.is_empty():
		var step := func(st: RefCounted) -> void: BattleController.step(st)
		for f: Dictionary in BuildController.apply_timeline(battle.s, battle.level["demo"], step):
			push_warning("參考解第 %d 步失敗：%s" % [f["index"], f["reason"]])
		for _i in Hooks.demo_ticks:
			BattleController.step(battle.s)
		return

	var sandbox: bool = Hooks.panel == "sandbox"
	# 沙盤的佈局全部是純礦砂造價（沒有加粗），所以那邊不發合金——
	# **合金要從畫面上那座熔爐煉出來，那正是那張圖要證明的事。**
	battle.s.alloy = 0.0 if sandbox else MapsData.DEMO_ALLOY
	var failures := BuildController.apply_ops(
		battle.s, MapsData.SANDBOX_DEMO if sandbox else MapsData.SHOAL_DEMO
	)
	for f: Dictionary in failures:
		push_warning("示範佈局第 %d 步失敗：%s" % [f["index"], f["reason"]])
	# 快轉到敵潮進入塔的射程。等真實時間跑 86 秒等於讓使用者的桌面開著一個
	# 視窗發呆一分半，模擬本來就不吃 delta，直接推 tick 就好。
	#
	# ★ **推的是 tick，不是階段**（B0.6 改）：讓準備期自己倒數完、波次自己開。
	# 舊寫法直接呼叫 `start_wave()` 把倒數跳過去，B0.5 還沒差別，B0.6 之後
	# 那等於一次滿額的提前召喚（倍率 1.5），截圖的掉落數字會和 `TL_SIM`
	# （自然開波）對不起來。現在 `TL_DEMO_TICKS=N` 與 `TL_SIM=N` 是同一個局面。
	for _i in Hooks.demo_ticks:
		BattleController.step(battle.s)
