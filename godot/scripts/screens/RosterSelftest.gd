extends RefCounted
## `Roster.gd` 的自檢（`TL_CLICKTEST`）。開發用：由 `Hooks.run_selftest()` 以路徑載入，
## 畫面本身的程式碼不靠它。
##
## 由 `Roster.gd` 拆出（B3.14）：只改搬家，不改行為。

const Host := preload("res://scripts/screens/Roster.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Progress := preload("res://scripts/meta/Progress.gd")
const RosterData := preload("res://data/Roster.gd")

var host: Host


func _init(screen: Host) -> void:
	host = screen


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=roster`）。
##
## 這個畫面的全部價值是「招募鈕點得到、真的扣券、而且抽不到重複的」。
## 存檔在有鉤子時是預設值（零進度＝零券），所以先塞進度再點——**不寫檔**
## （`SaveService.persist=false`），玩家的真實進度碰不到（`Tech` 的同一條）。
func run() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	# 零進度：只有第 1 關給的那一隻（錨），招募鈕買不起且說得出還差多少。
	var start_owned: Array = RosterData.owned(GameState.data)
	var starts_with_anchor: bool = start_owned.size() == 1 and start_owned.has("anchor")
	# ★ 「差多少」要在**畫面上**說得具體。斷言看的是那句話，不是鈕的 disabled
	#   ——灰掉的鈕只說「不行」，湊不出下一步。
	var broke: bool = host._recruit_button.disabled and host._recruit_note.text.contains("還差")

	# 塞滿星戰役（滿星的券數恆等於招募池大小 ＝ 剛好畢業，§7.13）。
	# 這一段本來就是逐 `ids()` 塞的，所以戰役加到八關它自己就對了。
	var stars: Dictionary = (GameState.data["campaign"] as Dictionary)["stars"]
	for id: String in preload("res://data/Campaign.gd").ids():
		stars[id] = 3
	host._build()
	await host.get_tree().process_frame
	# 五關全通＝五隻確定性角色全到手；招募池那三隻仍然一隻都沒有。
	var deterministic: bool = RosterData.owned(GameState.data).size() == 5
	var three_tokens: bool = RosterData.tokens(GameState.data) == 3
	var open: bool = not host._recruit_button.disabled and host._recruit_note.text.contains("還剩 3 隻")

	# ★ 連按三次＝抽完全池。**每一次都必須是新的一隻**（§3.9 不重複）。
	var pulls: Array[String] = []
	for _i in 3:
		var before: Array = RosterData.recruited(GameState.data).duplicate()
		await UiKit.click(host._recruit_button)
		var after: Array = RosterData.recruited(GameState.data)
		if after.size() == before.size() + 1:
			pulls.append(String(after[after.size() - 1]))
	var no_dupes: bool = pulls.size() == 3 and _unique(pulls)
	var all_pool: bool = no_dupes and _covers_pool(pulls)

	# 畢業：鈕變成「已收集完畢」，而且**再按也不會扣券**（§3.9 明文）。
	var graduated: bool = RosterData.graduated(GameState.data) and host._recruit_button.disabled
	# ★ 兩層都要驗：鈕按不下去（畫面層），**而且直接呼叫規則層也不會給**。
	#   只驗鈕的話，「畢業後不再消耗券」這條規則其實是靠一顆 `disabled` 撐著的
	#   ——那不是規則，那是版面。
	var spent_before: int = RosterData.recruited(GameState.data).size()
	await UiKit.click(host._recruit_button)
	var rule_refuses: bool = Progress.apply_recruit(
		GameState.data, Rng.stream(1)
	) == ""
	var no_overdraw: bool = (
		RosterData.recruited(GameState.data).size() == spent_before and rule_refuses
	)

	# 抽到的三隻真的進得了建造欄——名冊不進 `buildable()` 的話，這整個系統
	# 在局內是零效果的，而畫面上會看起來完全正常。
	var into_battle: bool = RosterData.buildable(GameState.data).size() == NodeDefs.BUILDABLE.size()

	# 捲到底之後最後一張卡整張在畫面內（RG-47／RG-60 的同一條）。
	host._scroll.scroll_vertical = 999999
	await host.get_tree().process_frame
	var last: Label = host._card_titles[host._card_titles.size() - 1]
	var reachable: bool = (
		last.global_position.y >= 0.0
		and last.global_position.y + last.size.y <= float(host.size.y)
	)

	var esc_back: bool = await UiKit.esc_reaches(host)

	var ok: bool = (
		starts_with_anchor and broke and deterministic and three_tokens and open
		and no_dupes and all_pool and graduated and no_overdraw and into_battle
		and reachable and esc_back
	)
	print("[TL_CLICKTEST/roster] start=%s broke=%s deterministic=%s tokens=%s open=%s no_dupes=%s(%s) pool=%s graduated=%s no_overdraw=%s buildable=%s last_reachable=%s esc_back=%s → %s" % [
		starts_with_anchor, broke, deterministic, three_tokens, open, no_dupes,
		", ".join(pulls), all_pool, graduated, no_overdraw, into_battle, reachable,
		esc_back, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		host.get_tree().quit(0 if ok else 1)
		return
	# ★ **配 `TL_SHOT` 時把畫面留在「有券可招募」那一格**（CLAUDE.md「拍只有
	#   互動才到得了的狀態」）。零進度拍出來招募鈕是灰的、抽完拍出來是「已收集
	#   完畢」——而要看的正是中間那個狀態，它在沒有進度的存檔上到不了。
	#   放在全部斷言跑完之後，所以一項都沒有被跳過。
	((GameState.data["roster"] as Dictionary)["recruited"] as Array).clear()
	host._build()


func _unique(list: Array[String]) -> bool:
	var seen: Dictionary = {}
	for s: String in list:
		if seen.has(s):
			return false
		seen[s] = true
	return true


func _covers_pool(list: Array[String]) -> bool:
	for type: String in RosterData.RECRUIT_POOL:
		if not list.has(type):
			return false
	return true
