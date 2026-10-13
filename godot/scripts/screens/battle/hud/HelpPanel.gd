extends Node
## 說明面板：一頁講完這個遊戲的規則（它是唯一一個跟局面無關的浮層）。

const BuildBar := preload("res://scripts/screens/battle/hud/BuildBar.gd")
const PriorityPanel := preload("res://scripts/screens/battle/hud/PriorityPanel.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 同伴模組。
var buildbar: BuildBar = null
## 同伴模組。
var priopanel: PriorityPanel = null


var help_panel: Control = null

var help_button: Button = null


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
		priopanel.bridge_line(),
		"　節點不能蓋在敵人路徑上",
		"　敵人走過時會打壞相鄰 1 格的東西 → 塔與導管退開 2 格就安全",
		"　塔只有交戰時吃電，待機 0",
		"",
		"底欄　快進 4×（只有準備期）｜提前召喚（提早開波換掉落倍率）｜優先權（缺料時誰先餓死）",
	]:
		if line == "":
			col.add_child(buildbar.spacer(6))
			continue
		var head := not line.begins_with("　")
		col.add_child(UiKit.label(
			line, 15 if head else 14,
			Palette.ORDER_BRIGHT if head else Palette.TEXT_PRIMARY, false
		))
	# （不吃滑鼠由 `UiKit.panel()` 保證——這一張曾經預設開在玩家要放第一個
	#   節點的位置上並把那片點擊整片吞掉，等於教學把遊戲擋住了。RG-39）
	scr.add_child(box)
	help_panel = box
	# ★ **預設不開**（B2.4.7，使用者指定）。原本空地圖時自動彈出，理由是
	#   「這局還沒開始，正是需要它的時刻」——但它整片是文字，蓋在地圖上，
	#   而每一局開頭都會再來一次。提示列（`_hint`）本來就在講下一步，
	#   說明鈕也一直在底欄。**要看的人按得到，不要看的人不必關掉它。**
	box.visible = false
	help_button.set_pressed_no_signal(false)


func on_toggle_help(open: bool) -> void:
	help_panel.visible = open
