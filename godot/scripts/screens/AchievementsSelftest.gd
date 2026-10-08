extends RefCounted
## `Achievements.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Achievements.gd` 拆出（B3.14）：只改搬家，不改行為。

const Achievements := preload("res://data/Achievements.gd")
const CampaignData := preload("res://data/Campaign.gd")
const Host := preload("res://scripts/screens/Achievements.gd")
const Progress := preload("res://scripts/meta/Progress.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=achievements`）。
##
## 這個畫面沒有鈕可按（返回那一顆除外），所以自檢驗的是**資料真的長在畫面上**：
##   · 20 列全部建出來（`Achievements.count()`，不是寫死的 20）
##   · 零進度時已達成 0 條、公司等級 1
##   · 塞一筆進度進去（**不寫檔**）之後那一列真的變成已達成，而且材料餘額跟著動
##   · 捲到底之後**最後一列整條在畫面內**（RG-47／RG-60 的同一課）
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var all_rows: bool = host._rows.size() == Achievements.count()
	var virgin: bool = (
		Achievements.done(GameState.data).is_empty()
		and Achievements.company_level(GameState.data) == 1
	)

	# 「初次通關」＝ 通關 1 關。給第 1 關 1 顆星。
	var before := Progress.components(GameState.data)
	((GameState.data["campaign"] as Dictionary)["stars"] as Dictionary)[CampaignData.id_at(0)] = 1
	host._build()
	await host.get_tree().process_frame
	var got: Array[String] = Achievements.done(GameState.data)
	var earned: bool = got.has("clear1")
	# ★ **達成的當下獎勵就在餘額裡**——沒有領取鈕，所以這一條就是那句話的斷言。
	var paid: bool = Progress.components(GameState.data) == before + 20
	var level_up: bool = Achievements.company_level(GameState.data) >= 1

	host._scroll.scroll_vertical = 999999
	await host.get_tree().process_frame
	var last: Control = host._rows[host._rows.size() - 1]
	var reachable: bool = (
		last.global_position.y >= 0.0
		and last.global_position.y + last.size.y <= float(host.size.y)
	)

	var esc_back: bool = await UiKit.esc_reaches(host)

	var ok: bool = (
		all_rows and virgin and earned and paid and level_up and reachable and esc_back
	)
	print("[TL_CLICKTEST/achievements] rows=%s(%d) virgin=%s earned=%s paid=%s company=%s last_reachable=%s esc_back=%s → %s" % [
		all_rows, host._rows.size(), virgin, earned, paid, level_up, reachable, esc_back,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
