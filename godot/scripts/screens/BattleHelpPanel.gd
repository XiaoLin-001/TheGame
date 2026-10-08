class_name BattleHelpPanel
extends RefCounted
## 操作說明抽屜。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

var help_panel: Control = null

var help_button: Button = null

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ 操作說明抽屜（`50_QA_PLAN.md` §4.4）。
##
## **它存在的理由是一句實測回饋**：使用者拿到 B0.7 的 build，第一句話是
## 「你沒教我要怎麼操作」。當時提示列只講「下一步的目標」，從頭到尾沒有任何
## 地方講過「蓋東西」＝左欄選一種、再左鍵點地圖——那是一條靠試錯才學得到的規則，
## 而試錯要花掉的正是那 60 秒準備期。
##
## **預設開在空地圖上、有東西之後就不再擋路**：不用存檔旗標（那要跨局狀態），
## 用「這一局蓋了東西沒有」判斷——玩家一放下第一個節點就代表他會操作了。
## 這張圖有幾座橋，說明就講幾座。零座也是一句有用的話——
## 「這一關不用擔心過路徑」本身就是關卡設計要傳達的訊息（§7.9 第 1 關）。
func _bridge_line() -> String:
	var n: int = (battle.s.sets["crossings"] as Dictionary).size()
	if n <= 0:
		return "　導管不能跨過敵人路徑（紫帶）。這張圖沒有橋，所有東西都在同一側"
	return "　導管要過敵人路徑（紫帶）只能走「橋」，也就是路徑上那 %d 段架高結構" % n


func build_help_panel() -> void:
	var box := UiKit.panel(0.94)
	box.position = Vector2(150, 250)
	var col := UiKit.vbox(3)
	box.add_child(col)
	for line: String in [
		"操作　左鍵做事、中鍵移動視野、滾輪縮放、ESC 開選單",
		"　蓋節點：左欄選一種 → 左鍵點地圖上的一格",
		"　拉導管：從一個節點按住左鍵，拖到另一個節點放開（隨時都能拖）",
		"　檢　視：左鍵點一座建築或一條導管 → 右邊出現它的數據，升級與拆除也在那個面板上",
		"　　　　　升級：每一級加的東西不同，耗能一律 +25%／級，上限 5 級，隨局結束消失｜拆除返還 75%",
		"　取　消：再點一次同一個東西＝收起面板；再按一次左欄的節點鈕＝放下手上那一種",
		"　移　動：按住滑鼠中鍵拖動地圖（放大之後才需要）",
		"",
		"規則",
		"　導管只能走 水平／垂直／45°，要轉彎先放一個「中繼」",
		# ★ 座數讀地圖，不寫死（B1.2）：第 1 關一座橋都沒有，跟新手講
		#   「路徑上那三段架高結構」只會讓他去找一個畫面上不存在的東西。
		_bridge_line(),
		"　節點不能蓋在敵人路徑上",
		"　敵人走過時會打壞相鄰 1 格的東西 → 塔與導管退開 2 格就安全",
		"　塔只有交戰時吃電，待機 0",
		"",
		"底欄　快進 4×（只有準備期）｜提前召喚（提早開波換掉落倍率）｜優先權（缺料時誰先餓死）",
	]:
		if line == "":
			col.add_child(battle.bars.spacer(6))
			continue
		var head := not line.begins_with("　")
		col.add_child(UiKit.label(
			line, 15 if head else 14,
			Palette.ORDER_BRIGHT if head else Palette.TEXT_PRIMARY, false
		))
	# （不吃滑鼠由 `UiKit.panel()` 保證——這一張曾經預設開在玩家要放第一個
	#   節點的位置上並把那片點擊整片吞掉，等於教學把遊戲擋住了。RG-39）
	battle.add_child(box)
	help_panel = box
	# ★ **預設不開**（B2.4.7，使用者指定）。原本空地圖時自動彈出，理由是
	#   「這局還沒開始，正是需要它的時刻」——但它整片是文字，蓋在地圖上，
	#   而每一局開頭都會再來一次。提示列（`_hint`）本來就在講下一步，
	#   說明鈕也一直在底欄。**要看的人按得到，不要看的人不必關掉它。**
	box.visible = false
	help_button.set_pressed_no_signal(false)


func on_toggle_help(open: bool) -> void:
	help_panel.visible = open
