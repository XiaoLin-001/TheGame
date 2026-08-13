extends Control
## 局內畫面（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## B0.3 只做「建造與地圖」需要的部分：地圖繪製、四種建造模式、頂欄供需。
## 真正的 HUD（三態徽章、能量列脈動、提前召喚、局末結算）是 B0.6；
## 敵人與波次是 B0.4。**這一批要證明的是：線會亮、線會滿載、加粗會變粗。**

const Loadout := preload("res://scripts/sim/Loadout.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Score := preload("res://scripts/sim/Score.gd")
const MapGen := preload("res://scripts/sim/MapGen.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const Tech := preload("res://data/Tech.gd")
const CampaignData := preload("res://data/Campaign.gd")
const RosterData := preload("res://data/Roster.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const SettingsScreen := preload("res://scripts/screens/Settings.gd")

## ★ 「快」的門檻（B1.6.3、`20_ART_DIRECTION.md` §1.7）。超過就給拖尾與流線輪廓。
## 取在 1.2：現行三種是 1.6／1.0／0.6，門檻落在漂蟲（基準 1.0）之上一截，
## 所以 M3 補敵人時「比基準明顯快」才拿得到這個視覺，不是隨便快一點就有。
const SWIFT_SPEED := 1.2

## ★ 底欄的 y（B2.4.2 常數化）。它原本是三處各寫一次的 `668`，而 A-1 那個缺陷
## 正好是「建造欄長到蓋住底欄」——兩個會互相碰撞的東西，座標必須是同一個常數。
const BAR_Y := 668.0

## 建造清單捲動區的高度。**清單再長也只會在這個區域裡捲**，模式鈕永遠釘在
## 它下面、永遠碰不到底欄。
##
## 52 ＝ 動作鈕那一塊實際佔的高度：`vbox 間隔 2 ＋ 間隔物 4 ＋ 間隔 2 ＋ 一列 44`。
## ★ B3.7.1 從 100 降到 52：升級與拆除拿掉之後只剩「藍圖」一顆，**空出來的 48px
## 直接還給節點清單**（十三種節點，捲得越少越好）。
## ⚠ 這種「差幾個像素」的東西不要用眼睛判——第一版的 96 實測差 2px（第二列的底邊
## 落在 670，底欄在 668），`TL_CLICKTEST` 的 `pinned_ok` 當場印出來。
const BUILD_LIST_H := BAR_Y - 56.0 - 52.0

## ★ 「點在導管上」的命中半徑，單位是格（B3.7）。
##
## **刻意比 `conduit_near()` 的預設 0.5 窄。** 導管的中心線正好穿過它經過的每一格
## 的**格心**，所以 0.5 等於「整格都算在線上」——那會讓建造模式下再也蓋不出
## 「線從旁邊經過而不接它」的那種節點，而那是流量網路裡一個真的戰術選擇
## （`Build.can_connect()` 的原註寫著這條規則刻意不禁止穿過節點）。
##
## 0.3 讓線佔住格心那一條帶，格的四周仍然蓋得下去。代價是這條帶在 fit 倍率下
## 只有十幾個像素寬——低於 P3 的 44px 觸控門檻，所以手機移植時要靠放大操作。
## 已登記在 `40_PRODUCTION_PLAN.md` 的移植風險表。
const WIRE_PICK := 0.3

# ── 路徑層的格子偏移（B2.4.2）。**常數，不在 `_draw()` 的內圈裡重建陣列。** ──
## 一格的四個角（格點偏移），順時鐘。與 `SIDES` 同序：`SIDES[i]` 是 `CORNERS[i]`
## 到 `CORNERS[i+1]` 那條邊的外向法線方向。
const CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)
]
## 四個鄰邊的方向（上、右、下、左）。
const SIDES: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
## 一個格點周圍的四格。
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)
]
## 八方鄰居 ＋ 自己（walk-by 的 Chebyshev 距離 1）。
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## 地圖左上角。36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，
## 浮層與地圖**不重疊**（RG-20 的先行實踐，正式驗收在 B0.6）。
## ★ 地圖框架（B1.2.2，使用者要求）。**玩家看到的地圖區域恆定**，不隨關卡
## 大小變動：進場時自動縮放到剛好填滿它，之後玩家自由縮放。
##
## 這比「地圖必須小到放得進一屏」好在兩件事：關與關之間的視覺尺度一致
## （20×12 的第 1 關不再只佔左上角一小塊），而且**地圖尺寸不再受畫面限制**
## ——它變成純粹的關卡設計參數。代價是**格子的像素大小會隨圖變大而變小**，
## 而線寬／徽章那套視覺編碼有一個可讀性地板（`50_QA_PLAN.md` RG-58）。
##
## x=120 讓出左側建造欄，y=56 讓出頂欄，下緣停在 660（底欄鈕在 668）。
const FRAME := Rect2(Vector2(120.0, 56.0), Vector2(1152.0, 604.0))
## 縮放上限＝**下限**的幾倍。
##
## ★ 下限在 B2.1b 從「就是 fit」改成 `max(fit, 可讀性地板)`：
##   一屏可見的圖（全部戰役關卡）fit 本來就在地板之上 → 行為完全不變；
##   大過一屏的圖（無盡）fit 會讓一格掉到 24px 以下，而那正是 RG-59 說
##   「要重新驗收才能跨過」的線——**縮到看得見全圖但讀不出瓶頸，等於
##   把 R-3 的驗收轉包給玩家**。所以無盡看全圖的地方是小地圖，不是主畫面。
const ZOOM_MAX_MULT := 3.0
const ZOOM_STEP := 1.25

## 小地圖（B2.1b、`20_ART_DIRECTION.md` §1.8）。**只在地圖大過框架時出現**
## ——戰役全部一屏可見，問題節點就在畫面上，多一個浮層只是多一塊遮擋。
const MINIMAP_MAX := Vector2(232.0, 140.0)
const MINIMAP_PAD := 12.0
## 邊緣箭頭上限。**十個箭頭等於沒有箭頭**（§2 反模式：資訊過載）。
const ARROW_MAX := 3
const ARROW_SIZE := 11.0
## 箭頭的命中半徑。P3 手機移植預留條款要求 ≥ 44×44 px，所以半徑取 22。
const ARROW_HIT := 22.0

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## `TL_STRESS`：丟掉的暖身幀數與實際量測幀數。
const STRESS_WARMUP := 30
const STRESS_FRAMES := 240

## 流動珠（`20_ART_DIRECTION.md` §1.4a）：珠距、每單位流率的行進速度（px/秒）、
## 低於此流率就完全不畫。20/秒的幹線 ＝ 120 px/秒，一格 32px 約走四分之一秒。
const BEAD_GAP := 20.0
const BEAD_SPEED := 6.0
const BEAD_MIN_RATE := 0.05

## 能量收支面板的**固定列序**。列數與順序恆定，沒有值的列留在原位變暗，
## 面板才不會每個 tick 抖一次（B0.7.4）。`short0..2` 是餵不飽的節點清單。
const ENERGY_ROWS := [
	"gen", "silo_out", "reclaim", "sep1", "tower", "smelt", "silo_in", "silo_store", "sep2", "net",
	"short0", "short1", "short2", "tip", "tip2",
]
## 「餵不飽」最多列幾座，其餘收成一行「…還有 N 座」。
const SHORT_ROWS := 3

## ★ B1.3.1：`CONNECT` 與 `PAN` 兩個模式已刪。拉線一律是拖曳（B1.6.2 取代了
## 「連線」模式），平移是滑鼠中鍵按住拖——**兩件事都不該是模式**：
## 模式的代價是「忘記切回來時點地圖沒反應」，而這兩個動作都頻繁到會天天付這個代價。
## ★ B3.7.1：**「升級」與「拆除」兩顆模式鈕拿掉**（使用者指定）。
##
## B3.7 把兩個動詞搬到檢視面板上（點那個東西 → 鈕就在旁邊），模式鈕變成同一件事
## 的第二條路——而且是比較慢的那一條（切模式 → 點目標 → 切回建造）。
## 留著兩條路的代價不只是兩顆鈕：**它們是兩套要各自維護、各自驗的點擊語意**，
## 而 B1.3.1 拿掉「連線」與「移動」時的理由一字不改地適用。
enum Mode { BUILD, BLUEPRINT }

var s: RefCounted = null

## ★ 這一局打的是哪一關（`data/Campaign.gd` 的一筆）。**空字典＝測試圖／沙盤**，
## 那條路徑沒有星等、沒有解鎖限制、也不寫存檔。
## 由呼叫端在 `add_child()` **之前**指派——`_ready()` 一進來就要用它。
var level: Dictionary = {}
## ★ 無盡模式的地圖種子（B2.1a）。**0 ＝ 不是無盡局**。
## 刻意不塞進 `level`：那個字典的每個讀取端都假設有 `star_throughput`／`reward`，
## 而無盡沒有星等也沒有關卡獎勵——共用會換來一堆 `if level.has(...)`。
## 由呼叫端在 `add_child()` 之前指派，同 `level`。
var endless_seed: int = 0
## ★ 這一局的難度層（B2.6、§7.16）。**0 ＝ 標準**，只有無盡帶得進來——
## 戰役是難度階梯（§7.9）、每日兩榜要可比（§3.10），兩者都恆為 0。
## 由呼叫端在 `add_child()` 之前指派，同 `level`／`endless_seed`。
var difficulty: int = 0
## ★ 每日挑戰打的是哪一張榜（B2.2）。`""` ＝ 不是每日局。
## **地圖仍然走 `endless_seed`**——每日挑戰就是無盡跑在一個固定的日種子上
## （§3.10「兩榜共用同一套地圖、波次、模擬與計分」），這個欄位只決定兩件事：
## 起始配置吃不吃玩家的科技，以及成績寫進哪一格存檔。
var daily_board: String = ""
## 每日挑戰的日期鍵（`YYYY-MM-DD`）。成績要記在哪一天名下。
var daily_date: String = ""
## 回關卡選擇。測試圖沒有上一層，所以是 Callable 而不是寫死的場景切換。
var on_exit: Callable = Callable()

## 視野（B1.2.2）。`_fit` 是「剛好填滿框架」的倍率，也是縮放下限。
var _zoom: float = 1.0
var _fit: float = 1.0
## 平移（螢幕像素）。fit 時恆為 0（地圖與框架同大，居中就是全貌）。
var _pan: Vector2 = Vector2.ZERO
## ★ 平移的**目標**（B2.1d）。`_pan` 每幀朝它收斂，所以小地圖拖曳與一鍵跳
## 都是平滑的。**中鍵直接拖地圖不走這條**——直接拖曳加上緩動會變成「黏手」，
## 手指到哪畫面就該到哪。`reduce_motion` 開啟時一律直接到位（§1.6 的紀律：
## 動效是裝飾，關掉之後資訊一點都不能少）。
var _pan_goal: Vector2 = Vector2.ZERO
## 每秒收斂比率。14 在 60fps 下約 4 幀走完八成——快到不覺得延遲，
## 又慢到看得出是「滑過去」而不是「跳過去」（使用者要的是後者的反面）。
const PAN_EASE := 14.0
## 小地圖拖曳中。按住不放時視野持續跟著游標走。
var _mini_drag: bool = false
## ★ 小地圖的剩餘顯示秒數（B2.1d.1，使用者指定）。**不常駐**——它蓋在地圖
## 右下角，常駐等於那一塊永遠點不到（使用者：「有些地方會點不到」）。
## 縮放或平移時出現，靜止 `MINI_HOLD` 秒後自己退場。
var _mini_ttl: float = 0.0
const MINI_HOLD := 3.0
## 最後這段時間用來淡出，不要用消失的。
const MINI_FADE := 0.5
var _zoom_button: Button = null

var _mode: int = Mode.BUILD
var _build_type: String = "extractor"
## 拖曳拉線的起點（B1.6.2）。−1 ＝ 沒有在拉線。
var _drag_from: Vector2i = Vector2i(-1, -1)
## ★ 藍圖框選的起點（B2.3）。−1 ＝ 沒有在框。
var _bp_from: Vector2i = Vector2i(-1, -1)
## ★ 待展開的藍圖索引（B2.3）。−1 ＝ 沒有拿著藍圖。
## 拿著藍圖時左鍵點地圖＝把它放在那裡，而不是蓋一個節點。
var _bp_index: int = -1
var _bp_panel: PanelContainer = null
## 中鍵按著沒放（B1.3.1）＝正在平移地圖。
var _panning: bool = false
var _hover: Vector2i = Vector2i(-999, -999)
## ★ 被檢視的那一格（B3.6）。`(-1,-1)` ＝ 沒有選取。
## **不是模式**——選取是一個狀態，模式是一個動詞，兩者混在一起的話
## 「選著一座塔的時候還能不能蓋東西」會變成一個要另外回答的問題。
var _selected: Vector2i = Vector2i(-1, -1)
## ★ 被檢視的那條導管（B3.7）。存的是**導管 `id` 不是索引**，−1 ＝ 沒有選取。
##
## 索引會位移：拆掉任何一條線、或**敵人啃斷一條線**，後面每一條的索引都往前挪。
## 存索引的話面板會安靜地換成講另一條線——而那正好發生在戰鬥最亂的時候。
var _sel_wire: int = -1
## 游標的**格為單位浮點座標**。命中導管要靠它（格解析度分不出「壓在線上」）。
var _hover_p: Vector2 = Vector2(-999, -999)
var _accum: float = 0.0
var _message: String = ""

## 頂欄六欄的版面（B2.4.4，§7.2 的 B-2 ＋ B-3）。
##
## 每一欄 ＝ `[標籤 sm] [數值 vs 級·固定寬·右對齊] [註腳 sm·固定寬·右對齊]`。
##
## **三階不是為了好看，是為了回答不同的問題**（§7.2 B-2）：
##   · 主（22 ＝ `text.lg`）＝**能量／波次／核心**——「我現在會不會輸」的全部答案
##   · 次（16 ＝ `text.base`）＝礦砂、合金——「我買不買得起」
##   · 附屬（13 ＝ `text.sm`）＝`▲/秒`、儲槽、交戰、擊殺——上面那幾個的**註腳**
##
## **固定寬度是 §3 那條硬性要求的正解**（「資源數字跳動時不得左右位移」）。
## ⚠ 原稿說要開 OpenType `tnum`——**量過之後那是修一個不存在的問題**：微軟正黑體
## 的數字本來就等寬，同位數換數字（1111→8888）本來就不位移。真正會位移的是
## **跨位數**（999→1000），而 `tnum` 對它無效，只有固定寬度擋得住。
## 量測留在 `_topbar_selftest()`，兩種情況各一條斷言。
##
## 寬度是**猜的，然後由 `bar_clear` 驗**（頂欄不得長到撞上縮放鈕）。固定寬度讓
## 那條斷言從「這一刻的數值排得下」升級成「任何數值都排得下」。
##
## ★ **從七欄縮成五欄**：三階字級排不下 11 個數字（第一版實測超出 166px），
##   而 §2 反模式清單自己就寫著「每個畫面最多 4 個『主要數字』」。
##   **搬家不是刪除**（B-2 說資訊完備性不能砍）：
##     · 儲槽存量 → 能量面板（它是「充放電」那兩列的分母），地圖上每顆儲槽
##       身上還有一圈琥珀弧，「哪一顆滿了」讀得到
##     · 交戰座數 → 併進能量那一格的註腳（它就是能量需求的解釋）
##     · 擊殺 → 併進波次那一格的註腳（兩個都在講「這一波打得怎樣」）
const TOP_CELLS := [
	{"tag": "礦砂", "vw": 64, "vs": 16, "nw": 48},
	{"tag": "合金", "vw": 56, "vs": 16, "nw": 48},
	{"tag": "能量", "vw": 88, "vs": 22, "nw": 72},
	{"tag": "",     "vw": 144, "vs": 22, "nw": 120},
	{"tag": "核心", "vw": 116, "vs": 22, "nw": 0},
]

var _top: HBoxContainer = null
## 頂欄每一欄的數值／註腳標籤。**存參照而不是每次 `get_child(i).get_child(j)`**
## ——那種索引在版面改一次就會安靜地指到別格（RG-134 是同一個錯法的按鈕版）。
var _top_values: Array[Label] = []
var _top_notes: Array[Label] = []
var _hint: Label = null
var _mode_buttons: Dictionary = {}
var _build_buttons: Dictionary = {}
## 建造清單的捲動容器（B2.4.2）。模式鈕釘在它**下面**，所以清單再長也推不動它們。
var _build_scroll: ScrollContainer = null
var _ff_button: Button = null
var _summon_button: Button = null
var _over_panel: Control = null
var _prio_panel: Control = null
var _help_panel: Control = null
var _help_button: Button = null
var _energy_panel: Control = null
var _energy_button: Button = null
var _energy_rows: Dictionary = {}
var _codex_button: Button = null
var _codex_panel: Control = null
var _inspect_panel: Control = null
var _inspect_label: Label = null
## ★ 檢視面板上的兩顆動詞鈕（B3.7）。升級／加粗共用一顆——選的是什麼就升什麼。
var _inspect_up: Button = null
var _inspect_del: Button = null
var _codex_label: Label = null
var _codex_on: bool = true
var _prio_labels: Dictionary = {}
## 局內選單（ESC 或左上角「選單」鈕）。`null` ＝ 沒開。
var _menu_layer: Control = null
var _menu_button: Button = null
var _menu_buttons: Array[Button] = []
## 從局內選單開出來的設定浮層。開著時 ESC 由它自己處理（回到選單）。
var _settings_layer: Control = null
## 本幀交戰中的塔 `{id: Array}`。繪圖層自己算——它要畫的是「誰正在吃電」，
## 而模擬只留了一個座數（`rates.engaged`）。
var _engaged: Dictionary = {}
## 本幀每隻敵人身上的光環 `Vector2(減速, 破甲)`，與 `s.enemies` 同索引。
## 和 `_engaged` 一樣是**繪圖層自己算的**：模擬層每 tick 都在算同一份，
## 但它只把結果用在傷害上、沒有留下來，而畫面要畫的是「誰被抓住了」。
var _auras: Array = []
## ★ 音訊（B1.5）。上一幀的幾個數字，用來推導「這一幀發生了什麼」。
## **音效一律從畫面層推導，模擬層維持零副作用**（`CLAUDE.md` 技術慣例）：
## 在 `scripts/sim/` 裡塞一行 `AudioBus.play()` 就等於讓每日挑戰的重播會出聲。
var _audio_prev: Dictionary = {}
## 上一幀看到的 tick 序號（音訊與死因診斷共用的邊緣偵測）。
var _last_tick: int = -1
## 死因歸因的累計（B1.7）。純畫面層，模擬層不知道它的存在。
var _diag: Dictionary = {}
## `TL_STRESS` 的量測狀態。
var _stress_frames: int = 0
var _stress_total: float = 0.0
var _stress_worst: float = 0.0
## 本幀「正在被啃」的格（敵人相鄰 1 格內）。**純渲染推導，不新增任何狀態**
## ——同一份判定模擬層每 tick 都在做（`Tide.in_blast`），這裡只是把它畫出來。
var _threat: Dictionary = {}
## ★ 本幀「畫不出圖形」的節點類型（B2.4.6）。`_draw_nodes()` 的 match 每漏一種
## 就往這裡記一筆，`TL_CLICKTEST` 拿它當斷言。**這不是防禦性程式碼，是一支感測器**
## ——漏掉一種的後果是那座塔在地圖上完全隱形（蓋得下去、會開火、會吃電、會被
## 打壞，就是看不見），而十五支測試沒有一支會紅：它們驗數值與流量，沒有一支看畫面。
var _no_glyph: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	# ★ **`set_anchors_and_offsets_preset`，不是 `set_anchors_preset`。**
	# 後者只設錨點不動 offset，本節點的 `size` 一直是 **(0, 0)**——而
	# `_draw()` 用的是絕對座標、`CanvasItem` 的繪圖不受 Control 尺寸裁切，
	# 所以**畫面完全正常，但滑鼠命中區是空的**：整張地圖點不動（B0.7.2）。
	# 這是「看起來對」與「真的對」差最遠的一種缺陷。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ★ 「減少動態效果」（§4.4）。B1.6 之前這是**死設定**：存檔裡有、
	#   沒有任何人讀。設定畫面在 B1.4，在那之前它由存檔預設值（false）決定。
	# `Motion.reduce` 由 `GameState.apply_settings()` 統一設定（B1.4）——
	# 開機一次、設定畫面改一次動一次。這裡不再各讀一份。
	s = SessionState.new()
	# `TL_PANEL=sandbox`：沙盤「靜水」（`data/Maps.gd`）。**合金那一列流動珠
	# 只有這張圖上有**——淺灘的示範佈局沒有熔爐，所以第三種資源的視覺編碼
	# 在任何既有截圖裡都不會出現，而沒被看過的編碼不算通過 R-3。
	_setup_session()
	_build_ui()
	# 截圖驗證要看得到「流動中的網路」，空地圖證明不了任何事——
	# **除了首次體驗**（`50_QA_PLAN.md` §4.4），那正好要看玩家真正的第一眼，
	# 所以 `TL_DEMO_TICKS=0` 的語意是「不要示範佈局」。
	if Hooks.panel in ["battle", "sandbox", "campaign"] and Hooks.demo_ticks > 0:
		_demo_layout()
	if Hooks.click_test:
		_click_selftest.call_deferred()


## 一局的起手。戰役關卡帶著自己的地圖與解鎖清單；沒有關卡就是測試圖／沙盤。
func _setup_session() -> void:
	# ★ 局外科技（B1.3）。有測試鉤子時 `SaveService.persist=false` → 存檔是預設值
	#   → `unlocked` 為空 → mods 全中性，所以 `TL_*` 的任何一張截圖與任何一支自檢
	#   都不會因為這台機器上玩家買了什麼科技而改變（RG-61 的同一條紀律）。
	var meta := Loadout.of(GameState.data, difficulty)
	if not level.is_empty():
		s.setup(level["map"], level["unlocked"], meta)
	elif endless_seed != 0:
		# ★ 建造欄不再是「空陣列＝全部」（B2.4）。無盡與每日自由配置榜給的是
		#   **這名玩家的名冊**——招募池的三隻是抽到才有的，發給所有人等於沒有名冊。
		#
		# ★ 統一配置榜走一份**明列的固定清單**（`Daily.UNIFORM_BUILD`，§7.11）：
		#   它與玩家的任何進度與課金完全無關（憲法 B3），而「空陣列＝全部」會讓
		#   每加一隻角色就悄悄改變這張榜。這是 B2.2 記在 §7.11 的那筆債。
		#
		# ★ 兩榜的差異仍然**只在 `SessionState.setup()` 的參數**（§3.10 明文：
		#   不得為此拆成兩套邏輯）。同一張生成圖、同一套波次、同一支模擬。
		var build_list: Array = (
			Daily.UNIFORM_BUILD.duplicate() if daily_board == Daily.UNIFORM
			else RosterData.buildable(GameState.data)
		)
		# ★ 統一配置榜的**全部**局外成長由 `Daily.meta_for()` 一次歸零（憲法 B3）。
		#   一軸一道閘等於靠列舉守住憲法（`sim/Loadout.gd` 開頭）。
		s.setup(MapGen.generate(endless_seed), build_list, Daily.meta_for(daily_board, meta))
	elif Hooks.stress:
		# ★ 壓力情境（B1.7、RG-8）：只為了量渲染。模擬在 `_process` 裡凍結——
		#   這一份佈局的單 tick 要 30 秒（`perf_test.gd` 的說明），不凍結的話
		#   量到的會是模擬的耗時，而渲染一幀都畫不完。
		s.setup(MapsData.stress_map(), [], meta)
		s.ore = 9999999.0
		s.alloy = 9999999.0
		BuildController.apply_ops(s, MapsData.stress_ops())
		for i in MapsData.STRESS_ENEMIES:
			s.add_enemy(["drifter", "carapace", "ember"][i % 3])
		s.phase = "wave"
	else:
		s.setup(MapsData.SANDBOX if Hooks.panel == "sandbox" else MapsData.SHOAL, [], meta)
	_reset_view()
	_audio_reset()
	# 兩層一起起跑，戰鬥層先靜音（`AudioBus.music()` 的無縫切層前提）。
	AudioBus.music("battle")


# ── 視野：框架、fit、縮放、平移（B1.2.2）─────────────────────────────

## 縮放下限。一屏可見的圖就是 fit；大過一屏的圖是**可讀性地板**（24px／格）。
##
## `_fit` 這個欄位名沿用下來（它是「全景」鈕與縮放夾限共用的那一個值），
## 但語意在 B2.1b 之後是「看得最遠的倍率」，不一定看得到全圖。
func _fit_zoom() -> float:
	return maxf(
		Shapes.fit_zoom(s.map["size"], FRAME.size),
		Shapes.MIN_READABLE_CELL / Shapes.GRID
	)


## 地圖在目前倍率下裝不進框架嗎？＝ 需不需要小地圖與邊緣箭頭。
## **一屏可見的地圖一律 false**，所以戰役關卡不會多出這兩塊遮擋。
func _oversized() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	return px.x > FRAME.size.x + 0.5 or px.y > FRAME.size.y + 0.5


## 進場（與「全景」鈕）的視野：fit ＋ 居中。
func _reset_view() -> void:
	_fit = _fit_zoom()
	_zoom = _fit
	_pan = Vector2.ZERO
	_pan_goal = Vector2.ZERO
	_mini_ttl = MINI_HOLD
	# ★ `TL_FOCUS="x,y,zoom"`：拍特效的近照（B1.6）。**不會在真實遊玩中生效**
	#   ——它只在有鉤子時存在，而有鉤子時存檔已經是唯讀的。
	if Hooks.focus.x >= 0:
		_zoom = clampf(_fit * Hooks.focus_zoom, _fit, _fit * ZOOM_MAX_MULT)
		var px := Vector2(s.map["size"]) * Shapes.GRID
		_pan_to((px * 0.5 - _center(Hooks.focus)) * _zoom, true)


## 地圖左上角在螢幕上的位置。**框架內居中**，放大後由 `_pan` 帶著走。
func _map_origin() -> Vector2:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	return FRAME.position + (FRAME.size - px) * 0.5 + _pan


## 放大之後地圖比框架大，平移要有邊界——不然可以把地圖整片拖出畫面，
## 然後玩家會以為遊戲壞了。夾住之後框架永遠被地圖蓋滿。
func _clamp_pan() -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID * _zoom
	var slack := (px - FRAME.size) * 0.5
	_pan.x = clampf(_pan.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	_pan.y = clampf(_pan.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))
	_pan_goal.x = clampf(_pan_goal.x, -maxf(0.0, slack.x), maxf(0.0, slack.x))
	_pan_goal.y = clampf(_pan_goal.y, -maxf(0.0, slack.y), maxf(0.0, slack.y))


## 設定平移目標。`immediate` 為真時當場到位——中鍵拖曳、縮放錨定、
## 以及所有測試斷言都走這條（斷言要驗的是「目標對不對」，不是「補間跑完沒」）。
func _pan_to(p: Vector2, immediate: bool = false) -> void:
	# 視野一動，小地圖就現身（並重新計時）。
	_mini_ttl = MINI_HOLD
	_pan_goal = p
	if immediate or Motion.reduce:
		_pan = p
	_clamp_pan()
	queue_redraw()


## 讓補間立刻走完。測試專用——把「動畫還沒到」和「算錯位置」分開。
func _settle_view() -> void:
	_pan = _pan_goal
	_clamp_pan()
	queue_redraw()


## 縮放。`anchor` 是螢幕上要固定不動的那一點（滑鼠位置或框架中心）——
## 少了它，滾輪縮放會把玩家正在看的東西推出畫面。
func _zoom_by(mult: float, anchor: Vector2) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * mult, _fit, _fit * ZOOM_MAX_MULT)
	if is_equal_approx(before, _zoom):
		return
	# ★ 讓 `anchor` 底下的那一格在縮放前後**待在原地**。
	#
	#   B1.2.2 的版本寫成 `_pan += (anchor - _map_origin()) * (1 - k)`，錯了兩層：
	#     ① `_map_origin()` 讀的是**已經更新過**的 `_zoom`，量到的是新原點不是舊的；
	#     ② 更根本地，`_map_origin()` 本來就把地圖置中，那一半的位移是縮放自己
	#        帶來的、不該再由 pan 補一次。
	#   兩個加起來的結果是：**按一次「＋」畫面就甩到左上角，而且 pan 當場撞上夾限、
	#   再也拖不動。** `_view_selftest` 當時只斷言「倍率有變大」與「pan 夾得住」，
	#   兩條都還是綠的——這個缺陷是 B1.3.1 加中鍵平移自檢時，
	#   `mid_pan=false` 把它逼出來的。
	#
	#   所以直接照定義寫：新原點 = anchor − k × (anchor − 舊原點)，pan 就是它和
	#   置中位置的差。看得懂比省一行重要。
	var m := Vector2(s.map["size"]) * Shapes.GRID
	var origin_before := FRAME.position + (FRAME.size - m * before) * 0.5 + _pan
	var k := _zoom / before
	_pan_to(
		anchor - (anchor - origin_before) * k
		- (FRAME.position + (FRAME.size - m * _zoom) * 0.5),
		true
	)
	_refresh_zoom()
	queue_redraw()


func _on_zoom(mult: float) -> void:
	_zoom_by(mult, FRAME.position + FRAME.size * 0.5)


func _on_zoom_reset() -> void:
	_reset_view()
	_refresh_zoom()
	queue_redraw()


func _refresh_zoom() -> void:
	if _zoom_button == null:
		return
	# TL_NAKED 遮所有數值標籤；縮放倍率也是數值。
	if Hooks.naked:
		_zoom_button.text = "全景"
		return
	_zoom_button.text = "全景 %d%%" % roundi(_zoom / maxf(0.0001, _fit) * 100.0)


## 這一局蓋得出哪些節點。**空的 `unlocked` ＝ 全部**（測試圖與沙盤）。
##
## ★ B2.4 之後「全部」包含招募專屬的三隻，而測試圖與沙盤**刻意不吃名冊**：
## 那兩張圖是開發用的（主選單上寫著「測試圖」），要驗的是節點本身而不是進度。
## 真正的入口各自明講自己要什麼——戰役問關卡（§7.9）、無盡與自由榜問名冊、
## 統一榜走 `Daily.UNIFORM_BUILD`。**沒有一條路是靠這個預設值決定的。**
func _buildable() -> Array:
	var unlocked: Array = s.sets.get("unlocked", [])
	return NodeDefs.BUILDABLE if unlocked.is_empty() else unlocked


## ★ 輸入層自檢（`TL_CLICKTEST=1`）。**用合成的滑鼠事件真的走一次 Godot 的
## 輸入路由**——不是直接呼叫 `_act()`，那樣測不到 `mouse_filter` 這一層，
## 而 B0.7.2 的缺陷正好就在那一層（滿版 `Control` 預設 `STOP`，把事件吃掉，
## `_unhandled_input` 從來沒被呼叫過，地圖五批都點不動）。
##
## 這支自檢存在的意義就是「那個缺陷不會再發生一次而沒人知道」。
##
## ⚠ **必須開真視窗跑，`--headless` 過不了**：dummy display server 不做 GUI
## 滑鼠命中測試，`_gui_input` 完全不會被呼叫。它是唯一一個不能 headless 的
## 檢查——這也正是它抓得到的東西別的檢查都抓不到的原因。
##   `TL_CLICKTEST=1 TL_MUTE=1 <godot> --path godot --rendering-driver opengl3`
## 約 1 秒後自己退出（0 ＝ PASS）。
## ★ 每一種可建造節點都要畫得出一個圖形（B2.4.6）。
##
## **這一條是使用者用眼睛抓到的**（「長哨沒有模型顯示」），而 B2.4 當批
## 1290 條斷言全綠——因為十五支測試驗的是數值與流量，**沒有一支看畫面**。
## 三隻招募塔的資料表、戰鬥、耗電、存檔、招募全部正確，只是在地圖上是透明的。
##
## 手法：把每一種 `BUILDABLE` 直接塞進 `s.nodes`（`add_node` 不走成本與放置規則），
## 逼 `_draw_nodes()` 跑過每一個分支，再看 `_no_glyph` 有沒有東西。測完立刻移除，
## 所以它對後面每一條斷言都是不可見的。
##
## 探針格 `(-9, -9)` 在地圖外：任何實際格都可能被後面的建造斷言用到。
func _glyph_selftest() -> void:
	var before: int = s.nodes.size()   # `s.nodes` 未標型別 → `:=` 推不出來，會編譯錯
	# ★ 同時給 `TL_SHOT` 時排成一列**留在畫面上**：斷言只證明「有畫東西」，
	#   證明不了「一眼分得出是哪一隻」。後者只有人眼判得了，而那張圖沒有這個
	#   鉤子就拍不到——招募塔要有券才蓋得出來，零進度存檔永遠擺不出這一排。
	var gallery: bool = Hooks.shot_path != ""
	for i in NodeDefs.BUILDABLE.size():
		var ty := String(NodeDefs.BUILDABLE[i])
		s.add_node(ty, Vector2i(4 + i * 2, 14) if gallery else Vector2i(-9, -9))
	# ★ 敵人也排一列（B3.2）。**六隻在同一張圖上才判得出「一眼分得開嗎」**——
	#   而 M3 的三隻只在無盡第 9／12／15 波之後才出場，沒有這個鉤子就要打二十分鐘
	#   才拍得到一張合照。斷言只證明「畫得出東西」，分不分得開仍然是人眼判的。
	if gallery:
		var types: Array = Enemies.DEFS.keys()
		for i in types.size():
			var id: int = s.add_enemy(String(types[i]))
			for e: Dictionary in s.enemies:
				if int(e["id"]) == id:
					e["progress"] = float(4 + i * 3)
	# ★ 合照裡順便排出**升級級數的階梯**（B3.5，★ B3.9 改寫）：
	#   **同一種塔的 0..5 級排成第二列**。
	#
	#   B3.8 之前這個階梯是設在上面那一列的第 2..6 座上，而那是採集器、發電機、
	#   熔爐、中繼、儲槽——**五種不同的形狀，而且五級全都是「出力」**。
	#   於是這張照片答不了它唯一要答的兩個問題：一級和五級**大小**分得出來嗎
	#   （不同型別本來就不一樣大）、級章的**形狀**分得出來嗎（全是實心方）。
	#   換成一排錨之後兩個都答得了：它的階梯是 出力 → 射速 → 射程 → 出力 → 射速，
	#   四種形狀裡出現三種，而六座並排的塔身只差在級數。
	#   直接設欄位不走 `upgrade_node()`：這是**畫面**的驗收，不是規則的
	#   （規則由 `combat_test` 顧）。
	if gallery:
		for k in Build.NODE_MAX_LEVEL + 1:
			# `s` 未標型別 → `:=` 推不出來，會編譯錯（CLAUDE.md 的嚴格型別地雷）
			var id: int = s.add_node("anchor", Vector2i(4 + k * 2, 17))
			for n: Dictionary in s.nodes:
				if int(n["id"]) == id:
					n["level"] = k
	# ★ **擺放預覽也留在同一張圖上**（B3.4）。它擺在那一排真節點的正上方，
	#   所以這張圖同時回答兩件事：預覽畫的是不是那隻角色的形狀、
	#   以及它和真的蓋出來那一個長不長得一樣。
	#   預覽只在「選了一種節點 ＋ 滑鼠在圖上」的那一刻存在——那是純互動狀態，
	#   沒有這個鉤子就拍不到，於是那句「有預覽了」只能用宣稱的。
	#   選碎浪：四角爆散星是最不像方框的一個，證明力最強。
	if gallery:
		_mode = Mode.BUILD
		_build_type = "breaker"
		_hover = Vector2i(10, 11)
		# ★ 順便把**檢視**留在畫面上（B3.6）：選一座塔，射程圈、數據面板與
		#   「誰在餵它電」的高亮都只有在選取狀態下存在，那也是純互動狀態。
		#   選錨（合照那一排的第 6 個）——它有射程，圈畫得出來。
		# 挑一座**真的接了線**的塔：合照那一排是憑空長出來的，沒有任何導管，
		# 而「誰在餵它電」正是要靠導管才答得出來的問題。
		# ★ B3.7：`TL_PICK=wire` 改成選一條導管——導管面板同樣是純互動狀態。
		#   挑**這一刻真的有東西在流**的那一條：面板上「流量 x / cap」與「已滿載」
		#   是這一批要看的東西，選一條靜止的線只證明得了版面。
		if Hooks.pick == "wire" and not s.conduits.is_empty():
			var flows: Dictionary = s.rates["conduit_flow"]
			var best := 0
			for i in s.conduits.size():
				if float(flows.get((s.conduits[i])["id"], 0.0)) > float(
					flows.get((s.conduits[best])["id"], 0.0)
				):
					best = i
			_select_wire(int((s.conduits[best])["id"]))
		for n: Dictionary in s.nodes:
			if _sel_wire >= 0:
				break
			var ty := String(n["type"])
			if float(NodeDefs.of(ty).get("range", 0.0)) <= 0.0:
				continue
			# 跳過自己會發電的那兩種（回收者／儲槽）：它們的「供電」欄位講的是
			# 另一件事，而合照要示範的是最常見的情況——一座塔、幾台發電機。
			if ty in ["reclaimer", "silo"]:
				continue
			var wired := false
			for c: Dictionary in s.conduits:
				if c["a"] == n["cell"] or c["b"] == n["cell"]:
					wired = true
					break
			if not wired:
				continue
			# **優先挑正在交戰的那一座**：不交戰就不吃電，不吃電就沒有電流，
			# 而「誰在餵它電」正是要有電流才看得到的東西。挑錯的話合照上
			# 只會有一個射程圈，證明不了這一批真正做的那件事。
			_selected = n["cell"]
			if bool(_engaged.get(int(n["id"]), false)):
				break
	_no_glyph.clear()
	queue_redraw()
	for _i in 2:
		await get_tree().process_frame
	var missing := PackedStringArray()
	for ty: Variant in _no_glyph:
		missing.append(String(ty))
	missing.sort()
	if not gallery:
		s.nodes.resize(before)
	_no_glyph.clear()
	queue_redraw()
	# ★ 圖鑑說明是**同一個缺陷的另一半**：`_codex_lines()` 也是一張以 type 為鍵的
	#   表，`.get(type, "")` 漏掉時的症狀是「說明那一行是空白的」——一樣不會報錯。
	#   兩件事一起驗，因為它們是同一個錯法。
	var blank := PackedStringArray()
	for ty: String in NodeDefs.BUILDABLE:
		if _codex_lines(ty).size() < 2 or String(_codex_lines(ty)[1]).strip_edges() == "":
			blank.append(ty)
	blank.sort()
	var ok: bool = missing.is_empty() and blank.is_empty()
	print("[TL_CLICKTEST/glyph] %d 種節點｜畫不出來的：%s｜圖鑑沒說明的：%s → %s" % [
		NodeDefs.BUILDABLE.size(),
		"（無）" if missing.is_empty() else ",".join(missing),
		"（無）" if blank.is_empty() else ",".join(blank),
		"PASS" if ok else "FAIL",
	])
	# 隱形的塔是完整缺陷，不併進後面那個 `ok` ——直接擋掉。
	if not ok and Hooks.shot_path == "":
		get_tree().quit(1)


## ★ 頂欄的版面不得隨數值變動（§3 硬性要求：「資源數字跳動時不得左右位移」，B-3）。
##
## **這一條原本是用 grep 推的**（`tabular|FontVariation|monospace` 零命中 → 宣稱
## 「每秒橫向抖十次」），而 A-3 已經教過一次：沒有量過的宣稱只是一個願望（RG-141）。
## 所以先有這支量測，再談要不要修。
##
## 量兩件事，因為它們的難度不同：
##   ① **同位數不同數字**（1111 → 8888）：等寬數字（tabular figures）就擋得住。
##   ② **不同位數**（1111 → 99）：等寬數字擋不住，只有固定寬度容器擋得住。
## §3 的正文要的是②（「數字跳動時不得左右位移」沒有限定位數），備案也是②。
func _topbar_selftest() -> void:
	var ore_before: float = s.ore
	var xs := func() -> PackedFloat32Array:
		var out := PackedFloat32Array()
		for c: Node in _top.get_children():
			out.append((c as Control).global_position.x)
		return out
	var same := func(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
		if a.size() != b.size():
			return false
		for i in a.size():
			if absf(a[i] - b[i]) > 0.5:
				return false
		return true
	s.ore = 1111.0
	_refresh_top()
	await get_tree().process_frame
	var base: PackedFloat32Array = xs.call()
	s.ore = 8888.0
	_refresh_top()
	await get_tree().process_frame
	var digits_ok: bool = same.call(base, xs.call())
	s.ore = 99.0
	_refresh_top()
	await get_tree().process_frame
	var width_ok: bool = same.call(base, xs.call())
	s.ore = ore_before
	_refresh_top()
	print("[TL_CLICKTEST/topbar] 同位數不位移=%s 任意位數不位移=%s → %s" % [
		digits_ok, width_ok, "PASS" if (digits_ok and width_ok) else "FAIL",
	])


func _click_selftest() -> void:
	# ★★ **看門狗**（B3.6）。自檢裡的任何一個執行期錯誤都會**中止這支函式**，
	#   於是最後那行 `quit()` 跑不到——視窗就一直開著，而 `CLAUDE.md` 鐵律 3 是
	#   「絕不在沒有測試鉤子的情況下開遊戲視窗」。有鉤子卻不會關，等於同一件事。
	#   （B3.6 當場踩到：索引了一個不存在的模式鈕，測試掛住 5 分鐘。）
	#   `TL_SHOT` 在場時不設——那條路徑本來就是要把畫面留著給截圖。
	if Hooks.shot_path == "":
		_watchdog()
	await get_tree().process_frame
	await get_tree().process_frame
	await _glyph_selftest()
	await _topbar_selftest()
	if Hooks.panel == "endless":
		await _guide_selftest()
		return
	# 有示範佈局在場時只驗浮層：地圖上的格子被佔走了，建造斷言本來就不成立。
	if s.nodes.size() > 1:
		_energy_button.button_pressed = true
		_on_codex_show("prism", _build_buttons["prism"])
		print("[TL_CLICKTEST] 示範佈局在場，只開浮層（建造斷言略過）")
		return
	var ore: Vector2i = (s.map["ore"] as Array)[0]
	var on_path: Vector2i = s.path[10]
	var before: int = s.nodes.size()

	_click(ore)
	for _i in 3:
		await get_tree().process_frame
	var placed: bool = s.nodes.size() == before + 1

	_click(on_path)          # 路徑格禁節點 → 要被擋下且**說明原因**
	for _i in 3:
		await get_tree().process_frame
	var rejected: bool = s.nodes.size() == before + 1 and _message.begins_with("✕")

	# ★ 45° 導管（使用者回報「沒辦法 45 度放置管道」）：在礦點的正斜角放一個
	#   中繼，再從一端拖到另一端。整條路徑都走真實輸入——包含按鈕。
	_press(_build_buttons["relay"])
	var from := Vector2i(10, 10)
	var to := Vector2i(13, 13)     # 正斜角，且遠離路徑（路徑走 y=4 與 x=30）
	_click(from)
	_click(to)
	for _i in 3:
		await get_tree().process_frame
	var diag_placed: bool = s.nodes.size() == before + 3
	_drag(from, to)
	for _i in 3:
		await get_tree().process_frame
	var wired: bool = s.conduits.size() == 1

	# ★ 使用者回報：「45 度的線似乎沒辦法加粗」（B1.2.1）。一格長的 45°——
	#   兩個對角相鄰的節點之間——連一個中間格都沒有，舊的格子命中判定必然落空。
	#   ★ B3.7.1：升級模式沒有了，這條改走**選取 → 面板加粗**的新路徑。
	#     驗的仍然是同一件事：**那個像素點命不命中得到這條線**，那才是當年壞掉的地方。
	_press(_build_buttons["relay"])
	_click(Vector2i(6, 12))
	_click(Vector2i(7, 13))
	for _i in 3:
		await get_tree().process_frame
	_drag(Vector2i(6, 12), Vector2i(7, 13))
	for _i in 3:
		await get_tree().process_frame
	_click_at(_to_screen((_center(Vector2i(6, 12)) + _center(Vector2i(7, 13))) * 0.5))
	for _i in 3:
		await get_tree().process_frame
	var short_diag: int = s.conduit_near(Vector2(6.5, 12.5))
	var picked_diag: bool = short_diag >= 0 and _sel_wire == int((s.conduits[short_diag])["id"])
	if picked_diag:
		_click_button(_inspect_up)
		for _i in 3:
			await get_tree().process_frame
	short_diag = s.conduit_near(Vector2(6.5, 12.5))
	var upgraded: bool = (
		picked_diag and short_diag >= 0 and int((s.conduits[short_diag])["level"]) == 1
	)

	# ★ 局內臨時升級一座**建築**（§4.3、B3.5）。★ B3.7.1 改走面板上那顆鈕。
	#   斷言三件事：級數真的加了、礦砂**真的扣了**、而且扣的是那個價
	#   （只驗級數的話，一個免費升級的實作照樣全綠）。
	var lvl_cell := Vector2i(6, 12)
	_click(lvl_cell)
	for _i in 3:
		await get_tree().process_frame
	var ore_before: float = s.ore
	var price := Build.node_upgrade_cost(NodeDefs.cost("relay"), 0)
	_click_button(_inspect_up)
	for _i in 3:
		await get_tree().process_frame
	var node_lvl: bool = int(s.node_at(lvl_cell).get("level", 0)) == 1
	var node_paid: bool = is_equal_approx(s.ore, ore_before - float(price))
	# ★ **鈕不得在按下之後跑掉**（B3.9.1，使用者回報「點了升級之後，滑鼠會位移到
	#   一個很奇怪的位置」）。位移的不是游標是面板——見 `_place_inspect` 那段。
	var btn_at: Vector2 = _inspect_up.global_position
	var btn_drift := 0.0
	# 上限是規則：連按八次也只到 5 級（B3.9；滿級之後那顆鈕自己會關掉）。
	for _i in 8:
		_click_button(_inspect_up)
		await get_tree().process_frame
		btn_drift = maxf(btn_drift, btn_at.distance_to(_inspect_up.global_position))
	var node_cap: bool = int(s.node_at(lvl_cell).get("level", 0)) == Build.NODE_MAX_LEVEL
	# ⚠ 上面那一條只量得到「這一輪的字剛好有沒有變長」——**在舊程式碼下它照樣是
	#   綠的**（中繼那一格升五級，最長的一行沒變）。所以再直接量**規矩本身**：
	#   同一個選取餵兩份長短差很多的內容進去，x 與**底邊**必須一樣
	#   （頂邊本來就該隨內容上下長）。
	_place_inspect(["短"])
	await get_tree().process_frame
	var box_short := Rect2(_inspect_panel.position, _inspect_panel.size)
	var long_lines: Array[String] = []
	for _i in 12:
		long_lines.append("這一行刻意寫得很長很長很長很長很長很長很長很長很長很長")
	_place_inspect(long_lines)
	await get_tree().process_frame
	var box_long := Rect2(_inspect_panel.position, _inspect_panel.size)
	var pos_stable: bool = (
		absf(box_short.position.x - box_long.position.x) < 0.5
		and absf(box_short.end.y - box_long.end.y) < 0.5
	)
	# ⚠ 量完要**把尺寸也收掉**，不只是內容：面板是直接掛在畫面上的自由 Control，
	#   而 Godot 只讓這種 Control 長到最小尺寸、**不會自己縮回去**。留著那 12 行
	#   撐出來的 552px 高度，後面那條中鍵平移就拖不動了（當場紅了一次）。
	_inspect_panel.size = Vector2.ZERO
	_refresh_inspect()
	var btn_still: bool = btn_drift < 0.5 and pos_stable
	# 收起來，交給下一段從零開始驗「點一下就開」。
	_click(lvl_cell)
	for _i in 3:
		await get_tree().process_frame

	# ★ 點一下建築＝檢視它（§B3.6）。走完整輸入路徑，因為這是一個**新的點擊語意**
	#   （舊行為是「這一格已經有東西了」）。三條斷言：面板真的開了、
	#   上面寫的是那一座、再點一次會收起來（選取是**開關**不是單向）。
	# ⚠ **不要索引一個不存在的模式鈕**——B3.7.1 之後底欄只剩「藍圖」一顆。
	#   索引不存在的鍵會丟執行期錯誤，而那會**中止整支自檢**：`quit()` 跑不到，
	#   視窗就一直開著（RG-164 的同一個形狀，B3.6 當場踩過）。
	_click(lvl_cell)
	for _i in 3:
		await get_tree().process_frame
	var sel_open: bool = _selected == lvl_cell and _inspect_panel != null and _inspect_panel.visible
	var sel_says: bool = sel_open and _inspect_label.text.contains(NodeDefs.label("relay"))
	# ★ 面板要**整個在畫面內**（RG-139／RG-149／RG-170 的同一句話第四次）。
	var sel_inside: bool = sel_open and (
		_inspect_panel.position.x >= 0.0
		and _inspect_panel.position.y >= 0.0
		and _inspect_panel.position.x + _inspect_panel.size.x <= float(size.x) + 0.5
		and _inspect_panel.position.y + _inspect_panel.size.y <= float(size.y) + 0.5
	)
	# ★ 和右上的能量面板**不得相交**（RG-162 那條，套在新的浮層上）。
	#   兩個都開著才驗得到，所以先確定能量面板是開的。
	var sel_clear := true
	if _energy_panel != null and _energy_panel.visible and _inspect_panel.visible:
		sel_clear = not Rect2(_energy_panel.position, _energy_panel.size).intersects(
			Rect2(_inspect_panel.position, _inspect_panel.size)
		)
	_click(lvl_cell)
	for _i in 3:
		await get_tree().process_frame
	var sel_toggles: bool = _selected.x < 0 and not _inspect_panel.visible

	# ★ 拖曳拉線（B1.6.2）：**全程停在建造模式**。會壞的地方有兩個——按下時
	#   沒把起點記起來、放開的事件沒被路由到——而兩個都只有真的送出
	#   「按下 → 移動 → 放開」三顆事件才驗得出來。
	_press(_build_buttons["relay"])
	_click(Vector2i(3, 8))
	_click(Vector2i(3, 11))
	for _i in 3:
		await get_tree().process_frame
	var wires_before: int = s.conduits.size()
	_drag(Vector2i(3, 8), Vector2i(3, 11))
	for _i in 3:
		await get_tree().process_frame
	var dragged: bool = s.conduits.size() == wires_before + 1 and _mode == Mode.BUILD

	# ★ 點一條導管＝檢視它，動詞在面板上（B3.7，使用者提出）。
	#   剛拉出來那一條 (3,8)–(3,11) 是垂直三格，兩端點的中點正壓在線上。
	#   走完整輸入路徑：這是**建造模式下的一個新點擊語意**（舊行為是在那一格蓋東西），
	#   而「按下那一刻走哪一條分支」只有真的送事件才驗得出來（B3.6 的教訓）。
	# ⚠ **先把能量面板打開**。版面那一條要驗的正是「讓不讓得開鄰居」，而面板關著時
	#   檢視面板貼在 y=56、離能量面板和小地圖都有幾百像素——那樣的斷言是**恆真**的。
	#   （量了才知道：關著時它在 y 56–230，小地圖在 525–648。）
	_energy_button.button_pressed = true
	await get_tree().process_frame
	var wire_mid := _to_screen((_center(Vector2i(3, 8)) + _center(Vector2i(3, 11))) * 0.5)
	var wire_id: int = int((s.conduits[s.conduits.size() - 1])["id"])
	_click_at(wire_mid)
	for _i in 3:
		await get_tree().process_frame
	var wire_sel: bool = (
		_sel_wire == wire_id and _inspect_panel != null and _inspect_panel.visible
		and _inspect_label.text.contains("導管") and _selected.x < 0
	)
	# 再點一次＝取消（選取是開關；沒有這條的話面板一開就關不掉，而它蓋著右半邊）。
	_click_at(wire_mid)
	for _i in 3:
		await get_tree().process_frame
	var wire_toggle: bool = _sel_wire < 0 and not _inspect_panel.visible
	_click_at(wire_mid)
	for _i in 3:
		await get_tree().process_frame
	# ★ 版面規則對**兩種選取都要成立**（RG-139／149／162／170 的同一句話）：
	#   整個在畫面內、不疊能量面板、不疊小地圖那一角。導管面板比節點面板更高
	#   （多一行「加粗後」），所以它才是會先掉出去的那一個。
	var wire_rect := Rect2(_inspect_panel.position, _inspect_panel.size)
	var wire_fits: bool = (
		_inspect_panel.visible
		and wire_rect.position.x >= 0.0 and wire_rect.position.y >= 0.0
		and wire_rect.end.x <= float(size.x) + 0.5 and wire_rect.end.y <= float(size.y) + 0.5
		and not wire_rect.intersects(_minimap_rect())
		and not (
			_energy_panel != null and _energy_panel.visible
			and Rect2(_energy_panel.position, _energy_panel.size).intersects(wire_rect)
		)
	)
	# 加粗鈕：級數真的加了、礦砂**真的扣了**、而且扣的是那個價
	#   （只驗級數的話，一個免費加粗的實作照樣全綠——B3.5 那條的同一句話）。
	var w_ore0: float = s.ore
	var w_price := Build.upgrade_cost(0)
	_click_button(_inspect_up)
	for _i in 3:
		await get_tree().process_frame
	var wi_now := _sel_wire_index()
	var wire_up: bool = wi_now >= 0 and int((s.conduits[wi_now])["level"]) == 1 and (
		is_equal_approx(s.ore, w_ore0 - float(w_price))
	)
	# 拆除鈕：線真的少一條、退款進帳、而且**選取跟著收掉**（拆掉的東西不能繼續選著）。
	var w_ore1: float = s.ore
	var w_refund := BuildController.conduit_refund(s.conduits[maxi(wi_now, 0)])
	var wires_now: int = s.conduits.size()
	_click_button(_inspect_del)
	for _i in 3:
		await get_tree().process_frame
	var wire_del: bool = (
		s.conduits.size() == wires_now - 1 and _sel_wire < 0
		and not _inspect_panel.visible and is_equal_approx(s.ore, w_ore1 + float(w_refund.x))
	)

	# ★ 同兩顆鈕的**節點**那一半：選一座建築，升級與拆除都在面板上。
	#   上一段驗的是加粗（導管），這一段是同兩顆鈕的另一半（建築）。
	var nd_cell := Vector2i(3, 11)
	_click(nd_cell)
	for _i in 3:
		await get_tree().process_frame
	var n_ore0: float = s.ore
	var n_price := Build.node_upgrade_cost(NodeDefs.cost("relay"), 0)
	_click_button(_inspect_up)
	for _i in 3:
		await get_tree().process_frame
	var node_btn_up: bool = int(s.node_at(nd_cell).get("level", 0)) == 1 and (
		is_equal_approx(s.ore, n_ore0 - float(n_price))
	)
	var n_ore1: float = s.ore
	var n_refund := BuildController.node_refund("relay")
	_click_button(_inspect_del)
	for _i in 3:
		await get_tree().process_frame
	var node_btn_del: bool = (
		s.node_at(nd_cell).is_empty() and _selected.x < 0 and not _inspect_panel.visible
		and is_equal_approx(s.ore, n_ore1 + float(n_refund.x))
	)
	# ★ **核心兩顆鈕都不該在**：它升不得也拆不得，而一顆按下去保證失敗的鈕
	#   是在邀請玩家犯錯。規則層擋著（`upgrade_node()`／`demolish()`），
	#   這一條驗的是畫面沒有和規則講反話。
	var core_cell: Vector2i = s.nodes[0]["cell"]
	for n0: Dictionary in s.nodes:
		if String(n0["type"]) == "core":
			core_cell = n0["cell"]
			break
	_click(core_cell)
	for _i in 3:
		await get_tree().process_frame
	var core_verbs: bool = (
		_selected == core_cell and _inspect_panel.visible
		and not _inspect_up.visible and not _inspect_del.visible
	)
	_click(core_cell)
	for _i in 3:
		await get_tree().process_frame

	# ★ B3.8：**升級鈕要說出這一級買到的是什麼**（使用者：「每次升級有不同效果」）。
	#   規則本身由 `combat_test` 的階梯斷言顧；這裡驗的是**它有沒有走到鈕上**。
	#   用錨——它的三級是 出力 → 射速 → 射程，所以連按兩次鈕上的字必須換過。
	#   一個把鈕文字寫死成「升級」的實作在別處全綠，只有這一條抓得到。
	var step_cell := Vector2i(9, 9)
	for r2 in 10:
		var cand2 := Vector2i(9 + r2, 9)
		if _in_map(cand2) and String(
			BuildController.preview_place(s, "anchor", cand2)["reason"]
		) == Build.OK:
			step_cell = cand2
			break
	_press(_build_buttons["anchor"])
	s.ore += 500.0
	_click(step_cell)
	for _i in 3:
		await get_tree().process_frame
	_click(step_cell)          # 蓋完再點一下＝選取它
	for _i in 3:
		await get_tree().process_frame
	var step_lv0: String = _inspect_up.text
	_click_button(_inspect_up)
	for _i in 3:
		await get_tree().process_frame
	var step_lv1: String = _inspect_up.text
	var step_says: bool = (
		not s.node_at(step_cell).is_empty()
		and step_lv0.contains(_step_text(Build.STEP_POWER))
		and step_lv1.contains(_step_text(Build.STEP_ROF))
		and step_lv0 != step_lv1
	)

	# ★ 中鍵平移（B1.3.1）：「移動」模式鈕拿掉之後，**這是唯一的平移路徑**。
	#   先放大（fit 倍率下平移恆被夾成 0，量不到東西）。
	_on_zoom(ZOOM_STEP * ZOOM_STEP)
	var pan_before := _pan
	# 中鍵拖曳＝「移動」模式鈕拿掉之後唯一的平移路徑（B1.3.1），所以它得有自檢。
	_drag_px(Vector2(600, 400), Vector2(540, 360), MOUSE_BUTTON_MIDDLE)
	for _i in 3:
		await get_tree().process_frame
	var panned: bool = _pan != pan_before
	_on_zoom_reset()

	# ★ B1.1：建造欄從 8 顆長到 10 顆（＋熔爐＋碎浪），高度逼近底欄。
	#   **最後一顆鈕還點不點得到**是這件事唯一該問的問題——鈕被擠出畫面時
	#   `_draw()` 完全不會抱怨，就跟 B0.7.2 那個 size (0,0) 的 bug 一樣。
	#   最後那一顆要合金（帳上 0）→ 會被擋下，但**擋下的理由必須是「合金不夠」**，
	#   不能是「這顆鈕根本沒被按到」。
	#
	# ★ **不寫死型別名**（B2.4）：這裡原本斷言 `_build_type == "breaker"`，而
	#   B2.4 在表尾接了三隻新角色之後，「最後一顆」就不再是碎浪了——測試變紅，
	#   但壞掉的是斷言不是功能。改成問「表尾那一個是誰」，並**另外斷言它真的
	#   要合金**：少了後半句，表尾哪天換成不用合金的節點，這條會安靜地變成空操作。
	# ★★★★ **「按得到」不等於「看得到」**（B2.4.2，RG-139）。這一條原本只驗
	#   最後一顆**建造鈕**的 y，而 `_press()` 是往 `global_position + size*0.5` 送
	#   合成事件的——**一顆被底欄蓋住、甚至被推到畫面外的鈕，照樣按得到**。
	#   B2.4 把可建造類型加到 13 種，「加粗／拆除」和底欄疊在一起、「藍圖」整顆
	#   掉出畫面，而 `blueprint=true` 全程沒紅過。
	#
	#   所以判準改成**幾何的**，而且分兩種東西問——**捲出去的清單項目本來就在
	#   視窗外，那是合法的**，會害人的是被**釘住卻被擠出去**的那幾顆：
	#     ① 三顆模式鈕與捲動容器本身：永遠不得越過底欄（它們不會捲）。
	#     ② 最後一顆建造鈕：**捲到底之後**必須整顆在捲動視窗內（同科技樹 RG-47）。
	var last_type: String = String(_buildable()[_buildable().size() - 1])
	var last_button: Button = _build_buttons[last_type]
	var pinned_ok: bool = _build_scroll.global_position.y + _build_scroll.size.y <= BAR_Y
	for b: Variant in _mode_buttons.values():
		var btn := b as Button
		if btn.global_position.y + btn.size.y > BAR_Y:
			pinned_ok = false
	_build_scroll.scroll_vertical = int(_build_scroll.get_v_scroll_bar().max_value)
	await get_tree().process_frame
	var view := Rect2(_build_scroll.global_position, _build_scroll.size)
	var reachable: bool = (
		pinned_ok
		and last_button.size.y >= 44.0
		and view.encloses(Rect2(last_button.global_position, last_button.size))
	)
	# ★ 捲回頂端。自檢**不得留下狀態**——`TL_CLICKTEST` 與 `TL_SHOT` 可以一起下
	#   （CLAUDE.md「拍只有互動才到得了的狀態」），而捲到底的建造欄會被拍進去。
	_build_scroll.scroll_vertical = 0
	_press(last_button)
	# ★ 這一格要**沒有導管壓在格心**（B3.7）。原本寫死 (12,12)，而 B3.7 讓
	#   「點在導管上」變成檢視那條線——(12,12) 正好有一條線經過，於是這一條
	#   當場變紅，理由卻和合金無關（`_message` 是空的，不是「合金不夠」）。
	#   照這個檔案既有的紀律：**要一格就去找一格**，不要寫死一個會被別批動掉的座標。
	var alloy_cell := Vector2i(12, 12)
	for r in 12:
		var cand := Vector2i(12 - r, 12)
		if _in_map(cand) and s.node_at(cand).is_empty() and s.conduit_near(
			Vector2(cand), WIRE_PICK
		) < 0 and String(BuildController.preview_place(s, last_type, cand)["reason"]) == Build.OK:
			alloy_cell = cand
			break
	_click(alloy_cell)
	for _i in 3:
		await get_tree().process_frame
	var alloy_gated: bool = (
		NodeDefs.alloy_cost(last_type) > 0
		and _build_type == last_type and _message.contains("合金")
	)
	print("[TL_CLICKTEST/select] 合金閘找到的空格 %s（要求：空地、蓋得下、格心上沒有導管）" % alloy_cell)

	# ★ B3.7.1：建造鈕是**開關**（使用者指定「按一下選擇，再按一下取消選擇」）。
	#   `ButtonGroup` 預設不准全部放開，所以這條真正驗的是 `allow_unpress`
	#   有沒有設、以及 `toggled(false)` 那一支有沒有接。
	#   ⚠ 光驗 `_build_type == ""` 不夠：**取消之後點空地不該蓋出東西**，
	#     而那是這件事唯一會咬到玩家的地方。用第一顆鈕（採集器）——最後一顆在
	#     捲動區底部，合成點擊會打到它上面蓋著的東西。
	_press(_build_buttons["extractor"])
	for _i in 3:
		await get_tree().process_frame
	var armed: bool = _build_type == "extractor"
	var nodes_before_idle: int = s.nodes.size()
	_click_button(_build_buttons["extractor"])
	for _i in 3:
		await get_tree().process_frame
	var disarmed: bool = armed and _build_type == ""
	_click(alloy_cell)
	for _i in 3:
		await get_tree().process_frame
	# 空手點空地要**安靜地什麼都不做**——不是丟一句 ✕。「我只是想收起面板」
	# 和「我蓋錯地方了」不是同一件事。
	var idle_click: bool = disarmed and s.nodes.size() == nodes_before_idle and _message == ""
	_press(_build_buttons["extractor"])
	for _i in 3:
		await get_tree().process_frame
	var rearmed: bool = _build_type == "extractor"

	# ★ 藍圖庫（B2.3）。走完整條路徑：框選 → 存 → 拿起來 → 放下去。
	#   **不直接呼叫 `Blueprint.capture()`**——那只驗得到純函式，而這一批
	#   會壞的地方在「拖曳有沒有真的被當成框選」和「拿著藍圖時左鍵做什麼」。
	GameState.data["blueprints"] = []
	_press(_mode_buttons[Mode.BLUEPRINT])
	var built_cells: Array[Vector2i] = []
	for n: Dictionary in s.nodes:
		if String(n["type"]) != "core":
			built_cells.append(n["cell"])
	var lo := built_cells[0]
	var hi := built_cells[0]
	for c: Vector2i in built_cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	_drag(lo, hi)
	for _i in 2:
		await get_tree().process_frame
	var bp_saved: bool = (GameState.data["blueprints"] as Array).size() == 1
	# 存的是**真的框到的東西**，不是一張空藍圖。
	# ⚠ 前置條件要一起驗：只框到一個節點時「節點數對得上」是**恆真**的，
	#   而那樣既測不到導管、也測不到多格落點（截圖上只有一格預覽才發現）。
	var bp_has_nodes: bool = bp_saved and built_cells.size() >= 2 and (
		((GameState.data["blueprints"] as Array)[0]["nodes"] as Array).size() == built_cells.size()
	) and not ((GameState.data["blueprints"] as Array)[0]["conduits"] as Array).is_empty()
	# 找一個**真的放得下**的落點。寫死一格的話，日後動一次示範佈局或地圖
	# 就會變成「藍圖功能壞了」的假紅——玩家在真實遊玩裡做的也是這件事：
	# 移動滑鼠直到預覽變綠。
	var ore_keep: float = s.ore
	var alloy_keep: float = s.alloy
	s.ore = 99999.0
	s.alloy = 99999.0
	var spot := Vector2i(-1, -1)
	if bp_saved:
		var bp0: Dictionary = (GameState.data["blueprints"] as Array)[0]
		for y in range(1, s.map["size"].y - 4):
			for x in range(1, s.map["size"].x - 4):
				if bool(BuildController.blueprint_check(s, bp0, Vector2i(x, y))["ok"]):
					spot = Vector2i(x, y)
					break
			if spot.x >= 0:
				break
	# 拿起來 → 左鍵點那一格 → 節點數要真的變多。
	_on_take_blueprint(0)
	var bp_nodes_before: int = s.nodes.size()
	if spot.x >= 0:
		_click(spot)
	for _i in 2:
		await get_tree().process_frame
	var bp_expanded: bool = s.nodes.size() > bp_nodes_before and _bp_index < 0
	# ★ 錢不夠時要**說出缺口，而且一格都不放**（DoD 第二條）。
	#   位置沿用同一格 → 唯一的失敗理由只剩錢。
	_on_take_blueprint(0)
	s.ore = 0.0
	s.alloy = 0.0
	var nodes_broke: int = s.nodes.size()
	if spot.x >= 0:
		_click(spot)
	for _i in 2:
		await get_tree().process_frame
	var bp_short: bool = _message.contains("礦砂差") and s.nodes.size() == nodes_broke
	# ★ 把局面還原給後面的斷言用：**展開出來的節點要拆掉**、錢改回去、
	#   藍圖放下、模式回建造。
	#   少了這幾行，後面的視野／選單／局末三條會因為帳上是 0、或因為那幾格
	#   被藍圖佔住而一起紅——而紅的原因看起來完全和它們自己有關（實際踩到兩次）。
	#   `remove_node_at()` 會連帶清掉接在那一格上的導管，所以不會留下斷線。
	if spot.x >= 0 and bp_saved:
		for c: Vector2i in Blueprint.cells_at(
			(GameState.data["blueprints"] as Array)[0], spot
		):
			s.remove_node_at(c)
	s.ore = ore_keep
	s.alloy = alloy_keep
	_bp_index = -1
	GameState.data["blueprints"] = []
	_press(_build_buttons["extractor"])

	# 三個浮層也走同一條真實路徑：按鈕 → 面板出現且有內容。
	_energy_button.button_pressed = true
	_on_codex_show("smelter", _build_buttons["smelter"])
	_prio_panel.visible = true
	await get_tree().process_frame
	var energy_ok: bool = (
		_energy_panel.visible and (_energy_rows["net"] as Label).text != ""
		and _energy_rows.has("smelt")
	)
	# 圖鑑與能量是兩顆各自獨立的開關 → 玩家可以同時開。所以「不互相蓋掉」
	# 和優先權面板一樣是斷言，不是希望（B1.6.2 的截圖上抓到它們疊在一起）。
	var codex_ok: bool = (
		_codex_panel.visible and _codex_label.text.contains("熔爐")
		and _codex_panel.position.x + _codex_panel.size.x <= _energy_panel.position.x
	)
	# 藍圖抽屜也要守同一條：三張浮層可以同時開，就不得互相蓋掉。
	_bp_panel.visible = true
	_refresh_blueprints()
	await get_tree().process_frame
	var bp_fits: bool = (
		_bp_panel.position.x >= _prio_panel.position.x + _prio_panel.size.x
		and _bp_panel.position.x + _bp_panel.size.x <= _energy_panel.position.x
		and _bp_panel.position.y + _bp_panel.size.y <= 660.0
	)
	_bp_panel.visible = false
	# 優先權面板 9 列雙欄：整張表要留在畫面內，且不得蓋掉能量面板。
	var prio_ok: bool = (
		_prio_panel.size.y > 0.0
		and _prio_panel.position.y + _prio_panel.size.y <= BAR_Y
		and _prio_panel.position.x + _prio_panel.size.x <= _energy_panel.position.x
	)

	# ★ 視野（B1.2.2）。四件事：進場就是 fit、fit 真的填滿框架、放大/全景走得通、
	#   平移夾得住。**縮放最容易壞的不是縮放本身，是命中判定跟著縮放走**——
	#   所以最後再用合成點擊蓋一個節點，確認放大後點到的還是同一格。
	var view_ok := await _view_selftest()

	# ★ 局內選單（B1.4.1）。會壞的地方有四個，每一個都只有真的送出事件才驗得到：
	#   ESC 到不到得了、遮罩擋不擋得住地圖、設定回不回得到選單、
	#   以及**左上角那顆鈕是不是同一件事**（P3：不能只有鍵盤那條路）。
	_press(_build_buttons["relay"])
	var free_cell := Vector2i(20, 12)
	_escape()
	for _i in 3:
		await get_tree().process_frame
	var menu_open: bool = _menu_layer != null and _menu_buttons.size() == 4
	var nodes_before: int = s.nodes.size()
	_click(free_cell)
	for _i in 3:
		await get_tree().process_frame
	var menu_blocks: bool = s.nodes.size() == nodes_before

	_press(_menu_buttons[2])          # 設定
	for _i in 3:
		await get_tree().process_frame
	var settings_open: bool = _settings_layer != null
	_escape()                          # 設定的 ESC ＝ 回選單，**不是**回戰場
	for _i in 3:
		await get_tree().process_frame
	var settings_back: bool = _settings_layer == null and _menu_layer != null
	_escape()
	for _i in 3:
		await get_tree().process_frame
	var menu_closed: bool = _menu_layer == null
	# 同一格在選單關掉之後蓋得起來 → 上面那個「蓋不起來」才證明得了是遮罩擋的，
	# 而不是那一格本來就不能蓋。
	_click(free_cell)
	for _i in 3:
		await get_tree().process_frame
	var buildable_after: bool = s.nodes.size() == nodes_before + 1
	_press(_menu_button)
	for _i in 3:
		await get_tree().process_frame
	var menu_by_button: bool = _menu_layer != null
	# 選單面板整個要留在畫面內。`CenterContainer` 幾乎不會出錯，但科技樹那張
	# 掉出畫面的卡片與設定畫面溢出的最後一行都是「`_draw()` 一個字都不會說」
	# 的同一類缺陷——量一次比相信便宜。
	var panel: Control = _menu_buttons[0].get_parent().get_parent() as Control
	var menu_fits: bool = (
		panel.global_position.y >= 0.0
		and panel.global_position.y + panel.size.y <= float(size.y)
	)
	_close_menu()

	# ★ 音訊（B1.5）。四件事，全部只有真的跑起來才問得到：
	#   ① 準備期的 BGM **在播**，而且音量真的不是 0。
	#   ② ★ **一進入波次，音樂真的降到全靜**（B2.1f：戰鬥期沒有音樂）。
	#      第一版的自檢直接呼叫 `AudioBus` 的 API，結果下一幀就被 `_audio_tick()`
	#      從 `phase` 蓋回去——量到的是自己的呼叫，不是遊戲真正的那條路。改成推 `phase`。
	#   ③ ★ **開打時號令真的響了一次**（用 `plays` 的差值問，它是唯一的證據）。
	#   ④ 播一個音效之後真的有聲道在響（檔案讀得到、`play()` 有生效）。
	#      ⚠ 有鉤子時是**匯流排靜音**，不是不播，所以這些狀態問得到。
	var music_ok: bool = AudioBus.music_playing("base") and AudioBus.music_level() > 0.0
	var phase_before: String = s.phase
	var sting_plays: int = AudioBus.plays
	s.phase = "wave"
	# ⚠ **每一幀都要把 phase 釘回去。** 這個局面的 `spawn_queue` 是空的，
	#   所以 `_end_of_wave()` 下一個 tick 就把它打回 `prep`——音樂淡到一半又淡回來，
	#   `wave_hush` 恆為 false（實際踩到）。釘 phase 不是作弊：`_audio_tick()`
	#   本來就只從 `phase` 推導，走的仍是遊戲真正的那條路。
	#
	# ⚠ 而且要等**時間**，不是等幀數。淡出是 `LAYER_FADE`（1.2 秒）的實時，
	#   而這個視窗沒有垂直同步——120 幀可能只有 0.2 秒（實際踩到，`wave_hush`
	#   恆為 false）。「等 N 幀」在任何跟實時掛鉤的東西上都是壞的等待方式。
	var hush_t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - hush_t0 < 2000 and AudioBus.music_level() > 0.0:
		s.phase = "wave"
		await get_tree().process_frame
	var wave_hush: bool = AudioBus.music_level() <= 0.0
	var wave_sting: bool = AudioBus.plays > sting_plays
	s.phase = phase_before
	AudioBus.play("build_place")
	await get_tree().process_frame
	var voice_ok: bool = false
	for child: Node in AudioBus.get_children():
		var pl := child as AudioStreamPlayer
		if pl != null and pl.playing:
			voice_ok = true
	var audio_ok: bool = music_ok and wave_hush and wave_sting and voice_ok and AudioBus.muted

	# ★ **局結束之後不得有東西還在動**（使用者回報：「音效還在，他們也還在射擊」）。
	#   根因是 `step()` 在 won/lost 直接 return → 開火線的 `ttl` 不再遞減 →
	#   拿 `ttl` 當「剛剛才開火」的判定就每一幀都成立。這裡塞一條假的開火線，
	#   讓局結束，然後量兩件事：線有沒有被收掉、還會不會繼續發出聲音。
	# ⚠ 開火線的起點**必須是一座真的塔**，否則 `fire_<type>` 找不到檔案、
	#   `play()` 直接 return，這一段就變成一個永遠會過的空測試。
	_press(_build_buttons["anchor"])
	var tower_cell := Vector2i(22, 12)
	_click(tower_cell)
	for _i in 3:
		await get_tree().process_frame
	var tower_built: bool = String(s.node_at(tower_cell).get("type", "")) == "anchor"

	# ★ 潮鳴的場（B1.8）。要守的回歸是「**繪圖層真的去讀了光環**」——
	#   `Combat.auras()` 的數學已經有 `combat_test` 守著（滿電／半電／不疊加），
	#   這裡缺的那一環是 `_draw()` 有沒有把它算進 `_auras`。少了那一行，
	#   潮鳴就會安靜地退回 B1.7 之前「每秒吃 9 電、畫面上零回饋」的樣子，
	#   而 `_draw()` 對此一個字都不會說（B0.7.2 那個 size (0,0) 的同一類缺陷）。
	_press(_build_buttons["knell"])
	_click(Vector2i(20, 8))              # 離路徑 (20,4) 四格 → 在 5 格射程內
	for _i in 3:
		await get_tree().process_frame
	var knell: Dictionary = s.node_at(Vector2i(20, 8))
	s.add_enemy("drifter")
	(s.enemies[0] as Dictionary)["progress"] = 20.0   # 路徑上的 (20,4)
	for _i in 3:
		await get_tree().process_frame
	var field_ok: bool = (
		not knell.is_empty()
		and _auras.size() == s.enemies.size()         # 繪圖層每幀算了它
		and _engaged.get(int(knell["id"]), false)     # 而且潮鳴確實在交戰
	)
	s.enemies.clear()
	for _i in 2:
		await get_tree().process_frame

	s.phase = "won"
	for _i in 4:
		await get_tree().process_frame
	# ① 局末面板出現的那一刻，凍住的開火線與碎片要被收乾淨。
	var over_cleared: bool = s.shots.is_empty() and _over_panel != null
	# ② 面板已經在了（`_refresh_over` 之後不會再清一次），這時再塞一條滿 `ttl` 的
	#    開火線——**舊版會每一幀重播一次它的開火音**，新版因為 tick 沒有前進而不播。
	s.shots.append({
		"from": tower_cell, "to": Vector2i(22, 4), "ttl": BattleController.SHOT_TTL,
	})
	var plays_before: int = AudioBus.plays
	for _i in 12:
		await get_tree().process_frame
	var over_silent: bool = AudioBus.plays == plays_before
	s.shots.clear()
	s.phase = phase_before
	for _i in 3:
		await get_tree().process_frame

	# ③ ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」，所以
	#    **輸掉的那一面板上一定要有那一句**，而且整張面板要留在畫面內
	#    （多一行會換行的字，正是最容易把面板推出下緣的東西）。
	_diag["wave_ticks"] = 600
	_diag["starved"] = 300
	_diag["leak_wave"] = 3
	s.phase = "lost"
	for _i in 4:
		await get_tree().process_frame
	var why_shown := false
	if _over_panel != null:
		for n: Node in _over_panel.find_children("*", "Label", true, false):
			if (n as Label).text.begins_with("為什麼輸"):
				why_shown = true
	var why_fits: bool = (
		_over_panel != null
		and _over_panel.position.y + _over_panel.size.y <= float(size.y)
	)
	s.phase = phase_before
	for _i in 3:
		await get_tree().process_frame
	var over_ok: bool = (
		tower_built and over_cleared and over_silent and why_shown and why_fits
		and field_ok
	)

	# ★ 最後才留一個懸而未決的拖曳起點（按下不放開），讓八條方向導引與
	#   「連不成」的橙色預覽線入鏡——**這是玩家真的會看到的那一幀**（手指還沒鬆開）。
	#   一定要放在所有斷言之後：懸著的起點會讓下一次點擊被當成拖曳的終點。
	_press_at(_to_screen(_center(from)), true)
	_hover = from + Vector2i(4, 3)     # 橫 4 直 3：正好不是 45°
	_refresh_hint()

	var menu_ok: bool = (
		menu_open and menu_blocks and settings_open and settings_back and menu_closed
		and buildable_after and menu_by_button and menu_fits
	)

	# ★ **底欄與提示文字的矩形不得相交**（B2.9）。
	#
	#   §7.2 A-1 的結論一字未改地適用在這裡：「驗收條件要改成『鈕的矩形與底欄
	#   矩形不相交』，不是『按得到』」——被壓在字底下的鈕**照樣按得到**，
	#   所以既有的每一條斷言都是綠的，而畫面上「說明」那顆鈕和提示文字疊在一起。
	#
	#   這一格是 B2.9 給按鈕套美術 token 時當場撞到的：每顆鈕寬了 8px，
	#   七顆就把底欄推過那個寫死的 520。**寫死的座標記的是當時那七顆鈕有多寬。**
	var bar_rect := Rect2(Vector2.ZERO, Vector2.ZERO)
	for c: Node in get_children():
		var box := c as HBoxContainer
		if box != null and is_equal_approx(box.position.y, BAR_Y):
			bar_rect = Rect2(box.global_position, box.size)
	# ⚠ **要用提示文字真正的高度**。第一版寫成 1px 高，於是它的矩形（y 666–667）
	#   和底欄（y 668 起）永遠不相交——**斷言在它該紅的情境下是綠的**，
	#   而我是把提示推到底欄正中間去測它才發現。RG-158 的同一課：先確認尺會動。
	var hint_rect := Rect2(_hint.global_position, _hint.size)
	var bar_hint_clear: bool = bar_rect.size.x > 0.0 and not bar_rect.intersects(hint_rect)
	# 而且提示文字自己要留在視窗內（推到右邊之後才有可能掉出去）。
	var hint_inside: bool = _hint.global_position.x + _hint.size.x <= float(size.x) + 0.5
	var ok: bool = (
		placed and rejected and diag_placed and wired and upgraded and dragged and panned
		and reachable and alloy_gated and energy_ok and codex_ok and prio_ok
		and view_ok and menu_ok and audio_ok and over_ok and bar_hint_clear and hint_inside
		and node_lvl and node_paid and node_cap
		and sel_open and sel_says and sel_inside and sel_toggles and sel_clear
		and wire_sel and wire_toggle and wire_fits and wire_up and wire_del
		and node_btn_up and node_btn_del and core_verbs
		and armed and disarmed and idle_click and rearmed and step_says and btn_still
		and bp_saved and bp_has_nodes and bp_expanded and bp_short and bp_fits
	)
	print("[TL_CLICKTEST] place=%s reject_path=%s diag_node=%s diag_conduit=%s diag_upgrade=%s drag_wire=%s mid_pan=%s last_btn=%s alloy_gate=%s energy=%s codex=%s prio=%s view=%s menu=%s audio=%s over=%s bar_hint=%s(底欄右緣 %.0f／提示 x %.0f) hint_in=%s node_lv=%s(付款 %s／上限 %s) 檢視=%s(說得出是誰 %s／在畫面內 %s／再點收起 %s／不疊能量面板 %s) → %s" % [
		placed, rejected, diag_placed, wired, upgraded, dragged, panned, reachable, alloy_gated,
		energy_ok, codex_ok, prio_ok, view_ok, menu_ok, audio_ok, over_ok,
		bar_hint_clear, bar_rect.end.x, _hint.global_position.x, hint_inside,
		node_lvl, node_paid, node_cap, sel_open, sel_says, sel_inside, sel_toggles, sel_clear,
		"PASS" if ok else "FAIL"
	])
	print("[TL_CLICKTEST/select] 導管選取=%s 再點收起=%s 版面=%s 面板加粗=%s(付款一併驗) 面板拆除=%s(退款一併驗) 建築升級鈕=%s 建築拆除鈕=%s 核心兩顆鈕都收起=%s｜建造鈕開關：選=%s 取消=%s 空手點空地無事發生=%s 選回來=%s｜升級鈕說得出這一級買什麼=%s｜升級後鈕不位移=%s" % [
		wire_sel, wire_toggle, wire_fits, wire_up, wire_del, node_btn_up, node_btn_del, core_verbs,
		armed, disarmed, idle_click, rearmed, step_says, btn_still,
	])
	print("[TL_CLICKTEST/audio] prep_music=%s wave_hush=%s wave_sting=%s voice=%s muted=%s tower=%s over_cleared=%s over_silent=%s why=%s why_fits=%s knell_field=%s" % [
		music_ok, wave_hush, wave_sting, voice_ok, AudioBus.muted, tower_built, over_cleared,
		over_silent, why_shown, why_fits, field_ok
	])
	print("[TL_CLICKTEST/blueprint] saved=%s nodes=%s(%d 格) expanded=%s shortfall=%s fits=%s" % [
		bp_saved, bp_has_nodes, built_cells.size(), bp_expanded, bp_short, bp_fits
	])
	print("[TL_CLICKTEST/menu] esc_open=%s scrim_blocks=%s settings=%s settings_back=%s esc_close=%s cell_buildable=%s button=%s fits=%s" % [
		menu_open, menu_blocks, settings_open, settings_back, menu_closed, buildable_after,
		menu_by_button, menu_fits
	])
	# 同時給 `TL_SHOT` 時不退出，把畫面交給截圖鉤子——**有些狀態只有互動才到得了**
	# （浮層要按鈕才會開、簡介要 hover 才會浮），沒有這條就永遠拍不到它們。
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## ★ 視野自檢（B1.2.2）。回傳全部通過與否，並**把畫面留在放大＋推到角落的
## 狀態**——那正是「遮罩有沒有真的切住框架」唯一拍得出來的畫面。
func _view_selftest() -> bool:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	# ① 進場就是 fit，而且 fit 至少填滿一軸（另一軸留邊是長寬比不同，不是漏算）。
	var at_fit: bool = is_equal_approx(_zoom, _fit)
	var filled: bool = (
		is_equal_approx(px.x * _fit, FRAME.size.x) or is_equal_approx(px.y * _fit, FRAME.size.y)
	)
	var inside: bool = px.x * _fit <= FRAME.size.x + 0.5 and px.y * _fit <= FRAME.size.y + 0.5

	# ② 頂欄不能長到撞上縮放鈕（礦砂上萬之後那一排會變長）。
	var bar_clear: bool = _top.position.x + _top.size.x <= _zoom_button.get_parent().position.x

	# ③ 放大 → 倍率上升；「全景」→ 回到 fit 且平移歸零。
	_on_zoom(ZOOM_STEP)
	var zoomed_in: bool = _zoom > _fit
	# ★ **以框架正中放大時，畫面中心不能跑掉**（B1.3.1）。舊版按一次「＋」就把
	#   地圖甩到左上角、pan 當場撞上夾限再也拖不動，而當時的斷言全是綠的——
	#   「倍率有變大」與「pan 夾得住」都成立，錯的是「往哪邊放大」。
	var centered: bool = _pan.is_equal_approx(Vector2.ZERO)
	# ★ 以滑鼠位置放大時，游標底下那一格必須還是同一格。
	_on_zoom_reset()
	var probe := Vector2(500.0, 300.0)
	var probe_cell := _cell_at(probe)
	_zoom_by(ZOOM_STEP, probe)
	var anchored: bool = _cell_at(probe) == probe_cell
	_on_zoom_reset()
	_on_zoom(ZOOM_STEP)
	_pan = Vector2(99999.0, 99999.0)
	_clamp_pan()
	var pan_clamped: bool = _pan.x <= (px.x * _zoom - FRAME.size.x) * 0.5 + 0.5
	_on_zoom_reset()
	var reset_ok: bool = is_equal_approx(_zoom, _fit) and _pan == Vector2.ZERO
	# 下限就是 fit：再按「−」也不該縮得比框架小。
	_on_zoom(1.0 / ZOOM_STEP)
	var floor_ok: bool = is_equal_approx(_zoom, _fit)

	# ④ ★ **放大之後命中判定還對得上**：這是縮放最容易靜靜壞掉的地方。
	#    放大兩級、把目標礦點平移到框架正中（玩家放大就是為了看某個東西），
	#    再點它——蓋出來的必須就是那一格，不是隔壁那一格。
	_on_zoom(ZOOM_STEP * ZOOM_STEP)
	_press(_build_buttons["extractor"])
	var target: Vector2i = (s.map["ore"] as Array)[1]
	var px_map := Vector2(s.map["size"]) * Shapes.GRID
	_pan = (px_map * 0.5 - _center(target)) * _zoom
	_clamp_pan()
	var before: int = s.nodes.size()
	_click(target)
	for _i in 3:
		await get_tree().process_frame
	var hit_ok: bool = s.nodes.size() == before + 1 and not s.node_at(target).is_empty()

	# ★ 滾輪只在地圖框架裡縮放（B2.4.7，使用者實玩回報：「選單滑到最上面，
	#   繼續滑會導致畫面放大」）。`ScrollContainer` 捲到邊界就不再吃掉滾輪事件。
	#   **兩條一起驗**：欄外不縮放 ＋ 欄內照樣縮放——只驗前者的話，把整段滾輪
	#   邏輯刪掉也會全綠。
	_reset_view()
	await get_tree().process_frame
	var z0 := _zoom
	_wheel(_build_scroll.global_position + Vector2(20.0, 20.0), true)
	await get_tree().process_frame
	var wheel_outside_ok: bool = is_equal_approx(_zoom, z0)
	_wheel(FRAME.get_center(), true)
	await get_tree().process_frame
	var wheel_inside_ok: bool = _zoom > z0
	_reset_view()
	await get_tree().process_frame

	print("[TL_CLICKTEST/view] 滾輪：欄上不縮放=%s 圖上縮放=%s" % [
		wheel_outside_ok, wheel_inside_ok,
	])
	print("[TL_CLICKTEST/view] fit=%s fills=%s inside=%s bar_clear=%s zoom_in=%s centered=%s anchored=%s pan_clamp=%s reset=%s floor=%s hit_after_zoom=%s　（fit=%.3f，格 %.1f px）" % [
		at_fit, filled, inside, bar_clear, zoomed_in, centered, anchored, pan_clamped,
		reset_ok, floor_ok, hit_ok, _fit, Shapes.GRID * _fit
	])
	# ★ `bar_clear` 紅掉時要**知道差多少**才改得動 `TOP_CELLS` 的欄寬——
	#   「太寬了」這三個字修不了東西，「超出 63px」可以。
	var widths := PackedStringArray()
	for c: Node in _top.get_children():
		widths.append("%.0f" % (c as Control).size.x)
	print("[TL_CLICKTEST/view/bar] 頂欄 %.0f→%.0f（寬 %.0f＝%s），縮放鈕在 %.0f，餘裕 %.0f px" % [
		_top.position.x, _top.position.x + _top.size.x, _top.size.x, "+".join(widths),
		_zoom_button.get_parent().position.x,
		_zoom_button.get_parent().position.x - (_top.position.x + _top.size.x),
	])
	return (
		at_fit and filled and inside and bar_clear and zoomed_in and centered and anchored
		and pan_clamped and reset_ok and floor_ok and hit_ok
		and wheel_outside_ok and wheel_inside_ok
	)


func _press(b: Button) -> void:
	b.button_pressed = true
	b.pressed.emit()
	# ★ B3.7.1：建造鈕與藍圖鈕改接 `toggled`，而 `button_pressed = true` 在**它本來
	#   就按著**的時候一個訊號都不送。自檢裡有好幾處是「再確認一次拿的是這個」，
	#   那些呼叫會安靜地變成空操作。補送一次——處理函式對重複的 true 是冪等的。
	b.toggled.emit(true)


## ★ 用**合成滑鼠事件**按一顆鈕（B3.7），不是直接 emit。
##
## 檢視面板的容器是 `MOUSE_FILTER_IGNORE`（RG-39），而「IGNORE 的容器裡的鈕
## 收不收得到點擊」正是 B0.7.2 那一類缺陷的所在層——`_press()` 直接發訊號，
## 那一層它一條都測不到。面板上的鈕一律走這裡。
func _click_button(b: Button) -> void:
	_click_at(b.global_position + b.size * 0.5)


## 合成一次 ESC。走 `Input.parse_input_event()` 的完整輸入管線，才驗得到
## 「`ui_cancel` 這個 action 真的對得上 ESC 鍵」與「事件真的傳到 `_unhandled_key_input`」
## ——直接呼叫 `_toggle_menu()` 兩件都驗不到。
func _escape() -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)


## GUI 的滑鼠路由要先有「游標在這裡」才認得出按下的是誰，所以**先送一個移動事件**。
## 走 `Input.parse_input_event()`（完整輸入管線）而不是 `Viewport.push_input()`：
## 後者繞過了一部分 GUI 狀態的建立，測不到真實玩家會走的那條路。
## ★ `_center()` 回的是**地圖座標**，合成滑鼠事件要的是**螢幕座標**——
## 中間差的就是縮放與平移那個變換（B1.2.2）。少了 `_to_screen()`，
## 這支自檢會點到旁邊那一格去，而畫面上一切看起來都正常。
func _click(cell: Vector2i) -> void:
	_click_at(_to_screen(_center(cell)))


## 合成一次拖曳：在 `a` 按下、移動到 `b`、在 `b` 放開。
func _drag(a: Vector2i, b: Vector2i) -> void:
	_drag_px(_to_screen(_center(a)), _to_screen(_center(b)), MOUSE_BUTTON_LEFT)


## 像素座標的拖曳。按下 → 移動（鍵壓著）→ 放開。
func _drag_px(a: Vector2, b: Vector2, button: int) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	_press_at(a, true, button)
	# 移動到終點時鍵是壓著的——`button_mask` 少了這一位，平移那條分支就進不去。
	var mm := InputEventMouseMotion.new()
	mm.position = b
	mm.global_position = b
	mm.relative = b - a
	mm.button_mask = mask
	Input.parse_input_event(mm)
	_press_at(b, false, button)


## 一顆按鍵事件（前面附一次移動，GUI 的滑鼠路由要先知道游標在哪）。
## `pressed=true` 而不送對應的放開，就是「手指還沒鬆開」那一幀。
func _press_at(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	Input.use_accumulated_input = false
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask if pressed else 0
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)


## 合成一次滾輪。**位置是重點**：`ScrollContainer` 捲到邊界之後就不再吃掉
## 滾輪事件，於是它會落回 `_gui_input` ——而在建造欄上滾滾輪不該縮放地圖。
func _wheel(at: Vector2, up: bool) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


## 像素座標版。**加粗要點的是兩個節點「之間」**，那不是任何一格的中心。
func _click_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)


## 合成一次滑鼠移動（不按鍵）。驗拖曳用——`_click_at()` 按下即放開，
## 用它驗不到「按住不放的時候會怎樣」。
func _move_at(at: Vector2) -> void:
	Input.use_accumulated_input = false
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)


func _process(delta: float) -> void:
	# ★ 視野緩動（B2.1d）。指數收斂與幀率無關——`1-exp(-k*dt)` 在 30fps 與
	#   144fps 下走完同一段路，`lerp(_, k*dt)` 不會。這只動**畫面**，
	#   不碰模擬：`_pan` 不進 `state_hash()`，也不影響任何 tick。
	if not _pan.is_equal_approx(_pan_goal):
		_pan = _pan.lerp(_pan_goal, 1.0 - exp(-PAN_EASE * delta))
		if _pan.distance_to(_pan_goal) < 0.5:
			_pan = _pan_goal
		queue_redraw()
	# ★ 小地圖倒數。`TL_SHOT` 下**不倒數**——截圖落在第幾秒取決於這台機器
	#   跑了幾幀，會倒數的話同一組參數在不同機器上會拍出「有／沒有小地圖」
	#   兩種圖，截圖就不能拿來回歸比對了（和模擬凍結同一條理由）。
	if _mini_ttl > 0.0 and Hooks.shot_path == "":
		_mini_ttl = maxf(0.0, _mini_ttl - delta)
		if _mini_ttl <= 0.0:
			queue_redraw()

	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.stress:
		_stress_frame(delta)
	if Hooks.shot_path == "" and not Hooks.stress:
		_accum += delta
		# 快進＝**多跑幾個 tick**，不是把 tick 拉長。固定時間步不能動，
		# 否則同一組操作在不同倍率下會跑出不同結果（§2.4 確定性）。
		var mult: int = s.speed_mult if s.phase == "prep" else 1
		var guard := 0
		while _accum >= BattleController.TICK and guard < 8 * mult:
			for _i in mult:
				BattleController.step(s)
			_accum -= BattleController.TICK
			guard += mult
	_refresh_top()
	# 提示列每幀重算：它講的是**當前狀態**下的下一步，而狀態每 tick 都在變。
	# B0.7 之前它只在滑鼠移動時更新，於是「礦砂開始入帳了」「波次開打了」這類
	# 轉折要等玩家碰一下滑鼠才會反映——手不動的那幾秒，提示列是在說謊。
	_refresh_hint()
	_refresh_energy()
	# 檢視面板講的是**當下這個 tick** 的耗能與供電來源，所以它也要每幀重算。
	_refresh_inspect()
	_refresh_over()
	# ★ 一個 tick 邊緣偵測，兩個消費者（音訊、死因診斷）。
	#   兩邊各記一份「上一幀的 tick」的那一天，就會有一邊記錯（B1.5.1 的教訓）。
	var advanced: bool = s.tick_count != _last_tick
	_last_tick = s.tick_count
	_audio_tick(advanced)
	if advanced:
		_diag_tick()
	queue_redraw()


## ★ 死因歸因的原始資料（B1.7）。
##
## M1 的驗收句子是「**陌生人可以說得出自己為什麼輸**」。局末面板原本只給
## 「撐過幾波、產能積分多少」——那些是**成績**，不是**原因**。玩家輸掉的時候
## 要的是下一句「所以我下次該改什麼」。
##
## 全部從畫面層累計，模擬層一個欄位都不動（`scripts/sim/` 零副作用）。
func _diag_tick() -> void:
	if s.phase != "wave":
		return
	_diag["wave_ticks"] = int(_diag["wave_ticks"]) + 1
	if float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01:
		_diag["starved"] = int(_diag["starved"]) + 1
	# 核心開始掉血的那一波 ＝ 第一次有敵人走到底。
	if int(_diag["leak_wave"]) < 0 and s.core_hp() < float(_diag["core_hp"]) - 0.01:
		_diag["leak_wave"] = s.wave_index
	_diag["core_hp"] = s.core_hp()


## 一句話的死因。**只給一句**：三條並列的診斷等於沒有診斷。
func _diag_line(won: bool) -> String:
	var ticks: int = maxi(1, int(_diag["wave_ticks"]))
	var starve := float(_diag["starved"]) / float(ticks)
	var leak: int = int(_diag["leak_wave"])
	if not won:
		if leak >= 0:
			return "為什麼輸　第 %d 波開始有敵人走到核心。%s" % [
				leak,
				"缺電讓塔的射速掉了（%d%% 的戰鬥時間供不應求）——先補發電機或儲槽。" % roundi(starve * 100.0)
				if starve >= 0.25 else "那條路線上的火力不夠——把塔往敵人的必經之路挪，或多蓋一座。",
			]
		return "為什麼輸　核心被相鄰的敵人啃掉了。節點退開敵人路徑 2 格就打不到。"
	if starve >= 0.25:
		return "下一次　有 %d%% 的戰鬥時間供不應求，塔是降速在打的——補電力就能拉高產能積分。" % roundi(starve * 100.0)
	return ""


# ── 音訊（B1.5）────────────────────────────────────────────────────────


## ★ 渲染壓力量測（`TL_STRESS=1`，B1.7）。
##
## **模擬是凍結的**，所以這裡量到的是純粹的「畫 547 個節點 ＋ 2045 條導管 ＋
## 200 隻敵人要多久」。前 30 幀丟掉（著色器編譯與第一次配置都落在那裡），
## 之後取平均與最壞值——**最壞值才是玩家感覺得到的那一下卡頓**。
func _stress_frame(delta: float) -> void:
	_stress_frames += 1
	if _stress_frames <= STRESS_WARMUP:
		return
	_stress_total += delta
	_stress_worst = maxf(_stress_worst, delta)
	var n := _stress_frames - STRESS_WARMUP
	if n < STRESS_FRAMES:
		return
	var avg := _stress_total / float(n)
	print("[TL_STRESS] 節點 %d／導管 %d／敵人 %d　→　平均 %.2f ms（%.0f FPS）／最壞 %.2f ms　量了 %d 幀" % [
		s.nodes.size(), s.conduits.size(), s.enemies.size(),
		avg * 1000.0, 1.0 / maxf(avg, 0.000001), _stress_worst * 1000.0, n
	])
	# 60 FPS ＝ 16.7ms；45 FPS（§5 的最低可接受）＝ 22.2ms。
	print("[TL_STRESS] 60FPS 目標 16.67ms／45FPS 底線 22.22ms → %s" % (
		"通過（60FPS）" if avg <= 0.01667
		else ("勉強（45FPS 以上）" if avg <= 0.02222 else "不通過")
	))
	get_tree().quit(0)


func _audio_reset() -> void:
	_audio_prev = {
		"kills": s.kills, "nodes": s.nodes.size(), "core": s.core_hp(),
		"warn_at": -99.0, "core_at": -99.0, "phase": s.phase,
	}
	_last_tick = s.tick_count
	_diag = {"wave_ticks": 0, "starved": 0, "leak_wave": -1, "core_hp": s.core_hp()}


## 這一幀發生了什麼？全部從狀態的差值推出來——**不在模擬層留任何一個
## 「順便播個音」的呼叫**。代價是要自己記上一幀，換到的是 `sim/` 仍然
## 可以在 headless 重播一萬次而不出聲。
func _audio_tick(advanced: bool) -> void:
	if _audio_prev.is_empty():
		return
	var over: bool = s.phase == "won" or s.phase == "lost"
	# ★ B2.1f：戰鬥期**完全沒有音樂**（使用者拍板）。這一行淡的是準備期那首。
	AudioBus.battle_hush(s.phase == "wave")
	# ★ 開打的號令。**邊緣觸發**（上一幀不是 wave、這一幀是）——
	#   照 `phase` 每幀播的話一波會播兩百次，而且它有 1.7 秒長。
	#   放在 `advanced` 判斷**之前**：提前召喚是玩家按鈕當幀就換 phase 的，
	#   等下一個 tick 才響會慢半拍，而這個音的全部價值就是「就是現在」。
	if s.phase == "wave" and String(_audio_prev.get("phase", "")) != "wave":
		AudioBus.play("wave_start")
	_audio_prev["phase"] = s.phase
	# 局結束就停掉生產的循環音。它是「東西正在跑」的聲音，而東西已經不跑了。
	AudioBus.flow(0.0 if over else clampf(float(s.rates["ore_in"]) / 30.0, 0.0, 1.0))

	# ★★ **一次性音效只在模擬真的往前走了一格時才判定。**
	#
	# 少了這一條會出兩件事，而且兩件都出過：
	#   ① 畫面 60fps、tick 10Hz → 同一發開火線會被連續 6 幀看到「ttl 還是滿的」，
	#      於是一發子彈播六次音。
	#   ② **局結束後 `BattleController.step()` 直接 return，`ttl` 從此不再遞減**
	#      → 最後那一 tick 的開火線永遠停在「剛剛才生出來」的狀態，
	#      音效就每一幀重放一次，聽起來像卡住了（使用者回報）。
	#
	# 用「差值偵測」的東西，就要確定自己是在**變化的那一刻**被呼叫的。
	if not advanced:
		return
	var now := float(s.tick_count) * BattleController.TICK

	# 開火：`ttl` 還是滿的就是這一 tick 才生出來的那幾發。
	# **一種塔一幀只出一個音**——五座錨同時開火時要聽到「一發」，
	# 不是五個同相位的正弦疊起來爆掉。
	var fired: Dictionary = {}
	for sh: Dictionary in s.shots:
		if int(sh["ttl"]) != BattleController.SHOT_TTL:
			continue
		var n: Dictionary = s.node_at(sh["from"])
		if not n.is_empty():
			fired[String(n["type"])] = true
	for type: String in fired:
		AudioBus.play("fire_%s" % type, -4.0)

	if s.kills > int(_audio_prev["kills"]):
		AudioBus.play("enemy_hit")
	# 節點變少＝被啃掉或被玩家拆掉。兩件事共用一個音是刻意的：
	# 玩家自己拆的那一次他知道自己在做什麼，不需要另一個音來告訴他。
	if s.nodes.size() < int(_audio_prev["nodes"]):
		AudioBus.play("build_destroyed", -2.0)
	# ★ 核心受擊與能量不足都要**節流**。核心每 tick 都在掉血，照實播就是
	#   每秒十次 0.9 秒的爆炸；警報響個不停等於沒有警報。
	if s.core_hp() < float(_audio_prev["core"]) - 0.01 and now - float(_audio_prev["core_at"]) >= 0.8:
		AudioBus.play("core_hit")
		_audio_prev["core_at"] = now
	var short: bool = float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01
	if short and s.phase == "wave" and now - float(_audio_prev["warn_at"]) >= 4.0:
		AudioBus.play("warn_power", -5.0)
		_audio_prev["warn_at"] = now

	_audio_prev["kills"] = s.kills
	_audio_prev["nodes"] = s.nodes.size()
	_audio_prev["core"] = s.core_hp()


# ── 輸入 ──────────────────────────────────────────────────────────────

## ★ **必須是 `_gui_input`，不能是 `_unhandled_input`。**
##
## 本畫面是一個滿版的 `Control`，而 `Control.mouse_filter` 預設是 `STOP`：
## 它在 `_gui_input` 那一層就把滑鼠事件吃掉並標記為已處理，`_unhandled_input`
## **永遠不會被呼叫**。B0.3 到 B0.7.1 這條路徑一次都沒通過——
## 左欄的按鈕能按（它們是各自獨立的子 Control），但**地圖完全點不動**。
##
## 為什麼拖了五批才發現：所有自動化驗證走的都是 `TL_SIM`（不開視窗）與
## `TL_PANEL`＋示範佈局（用程式呼叫 `BuildController`，不經過輸入層），
## 而「絕不在沒有鉤子的情況下開視窗」這條紀律讓我也沒有手動點過。
## **整個輸入層在這之前是零覆蓋。** 對策：`TL_CLICKTEST=1`（見 `_click_selftest()`）。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# ★ 平移：**按住滑鼠中鍵拖**（B1.3.1，使用者指定）。
		#   ⚠ 手機移植預留條款 P3：觸控沒有中鍵，移植時要補一個雙指拖曳手勢
		#   （已登記在 `40_PRODUCTION_PLAN.md` 的風險表）。放大只由底欄的
		#   ＋／−／全景三顆鈕與滾輪進入，而 fit 倍率下平移恆被夾成 0，
		#   所以在桌面版之外「完全平移不了」不會發生。
		#
		#   判斷用**自己記的 `_panning`，不讀 `mm.button_mask`**：那個位元是
		#   Input 單例從實體滑鼠狀態填的，合成事件填進去的值不保證留得住——
		#   驗不到的輸入路徑就是遲早會壞掉的輸入路徑（B0.7.2 的教訓）。
		if _panning:
			_pan_to(_pan + mm.relative, true)
			queue_redraw()
			return
		# ★ 小地圖按住拖曳（B2.1d，使用者指定）：按住不放，視野持續跟著游標走。
		#   走 `_pan_goal` → 畫面是**平滑**追過去的，不是一格一格跳。
		if _mini_drag:
			_mini_seek(mm.position)
			return
		# 浮點座標每次都更新（不只格變的時候）：命中導管靠的是它，
		# 而「壓在線上」與「在同一格但離線遠」是同一格裡的兩件事。
		_hover_p = _point_at(mm.position)
		var c := _cell_at(mm.position)
		if c != _hover:
			_hover = c
			_refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mb.pressed
		return
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and _mini_drag:
			# 小地圖上放開：**不可以掉進 `_release()`**，否則等於在小地圖
			# 底下那一格結束一次拉線。
			_mini_drag = false
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_release(mb.position)
		return
	# 滾輪縮放是桌面的便利，不是唯一的路：底欄有 ＋／−／全景 三顆鈕（P3）。
	#
	# ★ **只有游標在地圖框架裡才縮放**（B2.4.7，使用者實玩回報）。
	#   `ScrollContainer` 只在**捲得動的時候**吃掉滾輪事件；捲到頂還往上滾，
	#   事件就落回這裡——於是「建造欄滑到最上面再滑一下，地圖就放大了」。
	#   這條守衛同時擋掉底欄與頂欄上的滾輪，那本來也不該縮放地圖。
	#   ⚠ 不要改成「捲動容器把事件標記為已處理」——那要它在邊界也吞掉事件，
	#     而那會讓「滑到底之後想捲外層」這個標準行為壞掉。**限制範圍才是對的層級。**
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not FRAME.has_point(mb.position):
			return
		_zoom_by(ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP,
			mb.position)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# ★ 導引要先問（B2.1b）。小地圖蓋在地圖上面，不先攔的話點它會**在它底下
	#   那一格蓋出東西來**——而且玩家看不出為什麼，因為節點生在畫面外。
	if _guide_click(mb.position):
		return
	# ★ 從節點上按下先不動作，等放開才決定（B1.6.2）：放開在同一格＝一次普通點擊，
	#   放開在另一個節點上＝拉一條導管。這樣「蓋一個 → 接一條 → 蓋一個 → 接一條」
	#   不用每一步都往返左欄切模式——第 1 關的參考解就是 6 蓋 6 接交替，
	#   舊路徑要切 10 次模式，而那 10 次沒有任何一次是決策。
	var c := _cell_at(mb.position)
	# ★ 藍圖框選（B2.3）：按下記起點，放開才成框。
	if _mode == Mode.BLUEPRINT:
		_bp_from = c
		queue_redraw()
		return
	if _mode == Mode.BUILD and not s.node_at(c).is_empty():
		_drag_from = c
		queue_redraw()
		_refresh_hint()
		return
	var p := _point_at(mb.position)
	# ★ **點在導管上＝檢視那條線**（B3.7，使用者提出）。
	#
	#   放在建造模式裡而不是另開一個模式，理由和 B3.6 選節點同一條：玩家的意圖是
	#   「這條線我要看一下、要動它」，那不該先去底欄按一顆鈕再回來。
	#
	#   ⚠ 節點優先——上面那條已經 return 了，和 `demolish()` 的判斷順序一致。
	#   ⚠ 拿著藍圖時不攔：那時左鍵是「把它放在這裡」，一個明確得多的意圖。
	#   命中帶刻意窄（`WIRE_PICK`），格的其他地方照舊蓋得下去——理由見那個常數。
	if _mode == Mode.BUILD and _bp_index < 0:
		var wi: int = s.conduit_near(p, WIRE_PICK)
		if wi >= 0:
			_select_wire(int((s.conduits[wi])["id"]))
			_refresh_hint()
			queue_redraw()
			return
	_act(c)
	_refresh_hint()


## 左鍵放開。只有「按下時停在某個節點上」的那條路徑會走到這裡。
func _release(pos: Vector2) -> void:
	if _bp_from.x >= 0:
		var from_bp := _bp_from
		_bp_from = Vector2i(-1, -1)
		_save_blueprint(from_bp, _cell_at(pos))
		_refresh_hint()
		queue_redraw()
		return
	if _drag_from.x < 0:
		return
	var from := _drag_from
	_drag_from = Vector2i(-1, -1)
	var to := _cell_at(pos)
	if to != from and not s.node_at(to).is_empty():
		var code := BuildController.lay_conduit(s, from, to)
		if code == Build.OK:
			AudioBus.play("build_wire")
		_message = _text_of(code)
	else:
		# ★ **在既有節點上點一下＝檢視它**（B3.6，使用者提出）。
		#
		#   這個手勢原本只回一句「從這個節點按住往另一個節點拖」——一句教學，
		#   而玩家蓋到第三座塔之後就不需要它了，那之後這個手勢什麼都不做。
		#   換成選取之後，「點一下那座塔」給出射程、數據、當下耗能，
		#   以及**是誰在餵它電**。拖曳那句話改掛在提示列（`_refresh_hint()`）。
		#
		#   ⚠ 這一段**必須放在這裡，不是 `_act()` 的 BUILD 分支**：
		#   點在既有節點上會先進入「準備拉導管」的按下路徑，放開時走到這裡，
		#   根本到不了 `_act()`。第一版寫在那邊，於是面板永遠不開而斷言說
		#   「檢視=false」——輸入路徑的形狀只有真的送事件才看得出來。
		#
		#   不另開「檢視模式」：模式鈕在 B2.4.2 已經因為十三種節點擠過一次；
		#   也不綁右鍵——P3「操作不得只靠 hover／右鍵／鍵盤」。
		#
		#   ★ B3.7：再點一次同一座就取消選取（使用者提出）。選取是**開關**——
		#   沒有取消的路的話，面板一開就再也關不掉，而它蓋著地圖右半邊。
		_selected = Vector2i(-1, -1) if _selected == from else from
		_sel_wire = -1
		_refresh_inspect()
		_message = "" if _selected.x >= 0 else "從這個節點按住往另一個節點拖，就能拉一條導管。"
	_refresh_hint()
	queue_redraw()


## ★ B3.7.1 起這裡只剩建造一種語意。
##
## 加粗與拆除本來在這裡各佔一支分支，並且各自需要**格為單位的浮點座標**才點得準
## （好幾條線擠在同一個節點上時，格解析度分不出玩家指的是哪一條，B1.2.1）。
## 兩個動詞搬到檢視面板之後，那個參數與它的兩支分支一起消失——**面板已經知道
## 玩家選的是哪一個東西，不必再用座標猜一次。**
func _act(cell: Vector2i) -> void:
	# 音效只在**真的做成了**的時候響（`Build.OK` ＝ 空字串）。失敗有提示列說原因，
	# 再配一個音只是把「你做錯了」講兩次。
	match _mode:
		Mode.BUILD:
			# ★ 拿著藍圖時，左鍵是「把它放在這裡」而不是蓋一個節點（B2.3）。
			if _bp_index >= 0:
				_expand_blueprint(cell)
				return
			# 蓋在空地上就取消選取：選取講的是「這一座」，而畫面已經換人了。
			_selected = Vector2i(-1, -1)
			_sel_wire = -1
			_refresh_inspect()
			# ★ B3.7.1：手上什麼都沒拿（再按一次建造鈕就會這樣）＝點空地什麼都不做。
			#   不報錯——「我只是想收起面板」和「我蓋錯地方了」不是同一件事，
			#   對前者丟一句 ✕ 是把一個正常操作講成失敗。
			if _build_type == "":
				_message = ""
				return
			var code_b := BuildController.place(s, _build_type, cell)
			if code_b == Build.OK:
				AudioBus.play("build_place")
			_message = _text_of(code_b)


func _text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)


func _label_at(cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


## 螢幕像素 → 格號。**縮放與平移的反變換就在這一行**，命中判定與繪圖
## 因此永遠對得起來（各寫一份的那一天，滑鼠就會差半格）。
func _cell_at(pos: Vector2) -> Vector2i:
	return Shapes.to_grid((pos - _map_origin()) / _zoom)


## 螢幕像素 → **格為單位的浮點座標**（整數＝格中心）。
func _point_at(pos: Vector2) -> Vector2:
	return (pos - _map_origin()) / (Shapes.GRID * _zoom) - Vector2(0.5, 0.5)


func _in_map(c: Vector2i) -> bool:
	var size: Vector2i = s.map["size"]
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# ── 繪圖 ──────────────────────────────────────────────────────────────

func _draw() -> void:
	var size: Vector2i = s.map["size"]
	var rect := Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID)

	# ★ 全部的地圖繪圖都在**格為單位的地圖座標**裡做，縮放與平移交給這一個
	#   變換（B1.2.2）。所以底下每一支 `_draw_*` 都不知道縮放存在——
	#   縮放要是滲進 9 支繪圖函式裡，每加一種圖形就要記得乘一次倍率。
	#   文字不受影響：`_draw()` 裡沒有任何 `draw_string`，HUD 全是 Control 子節點。
	draw_set_transform(_map_origin(), 0.0, Vector2(_zoom, _zoom))
	draw_rect(rect, Palette.BG_PANEL)

	# 網格只畫在地圖範圍內：畫到浮層底下會讓「哪裡可以蓋」變得曖昧。
	Shapes.draw_grid(self, rect)

	# 敵人的格算一次給三個人用（交戰、光環、被啃判定）——同一幀各算一次的那一天，
	# 就會有一個用到的是上一幀的位置。
	var cells := Combat.enemy_cells(s.enemies, s.path)
	_engaged = Combat.engaged(s.nodes, cells)
	_auras = Combat.auras(s.nodes, cells, s.rates["satisfaction"])
	_threat = _threat_cells(cells)
	_draw_path()
	_draw_ore_cells()
	_draw_fields()
	_draw_conduits()
	_draw_nodes()
	_draw_enemies()
	_draw_shots()
	_draw_bursts()
	_draw_shields()
	_draw_selection()
	_draw_hover()
	# 階段色調（`10_GDD.md` §6.2 硬性要求 4）：**不看計時器也知道自己在哪個階段**。
	# 蓋在最上層而不是墊在底下——墊底的話節點與敵人會把它整片蓋掉。
	draw_rect(rect, Palette.alpha(
		Palette.WARN_ORANGE if s.phase == "wave" else Palette.ORDER_CYAN,
		0.10 if s.phase == "wave" else 0.03
	))

	# ── 回到螢幕座標 ──────────────────────────────────────────────────
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_frame_matte()
	# 導引畫在遮罩**之後**：它們的職責就是講「框架外面有什麼」，被遮罩蓋掉
	# 等於整個功能不存在。兩者都只在 `_oversized()` 時出現。
	_draw_arrows()
	_draw_minimap()
	_draw_energy_bar()


# ── 大圖導引：小地圖與邊緣箭頭（B2.1b，`20_ART_DIRECTION.md` §1.8）────────
#
# 大圖模式的 R-3 驗收是「**瓶頸節點即使不在畫面內也能在 30 秒內被找到**」。
# 兩個通道分工明確，不是互為備援：
#   小地圖 → 「全局現在長什麼樣？我在哪？」常駐、靜態。
#   邊緣箭頭 → 「現在有東西壞了，在畫面外哪一邊？」打斷式。
# 兩者都可點，點了把視野移過去——這也是大圖平移唯一的**純左鍵**動線
# （中鍵拖曳在觸控上不存在，R-16）。


## 「問題」不新發明判定，就是既有的兩件事，依嚴重度排序：
##   ① 正在被 walk-by 啃的節點（`_threat`，和主畫面的四角括號同一份判定）
##   ② `缺料`／`滿溢`（`node_state`，和三態徽章同一份判定）
## 排序決定 `ARROW_MAX` 砍掉的是哪幾個——被啃的永遠留著。
func _problem_cells() -> Array[Vector2i]:
	var hurt: Array[Vector2i] = []
	var stuck: Array[Vector2i] = []
	var state: Dictionary = s.rates["node_state"]
	for n: Dictionary in s.nodes:
		var c: Vector2i = n["cell"]
		if _threat.has(c):
			hurt.append(c)
		elif int(state.get(int(n["id"]), SessionState.NORMAL)) != SessionState.NORMAL:
			stuck.append(c)
	hurt.append_array(stuck)
	return hurt


## 目前看得到的世界座標矩形。小地圖的視野框與「這個問題在不在畫面內」
## 都從這裡算——**只有一份**，兩者不可能各算各的而對不起來。
func _view_world_rect() -> Rect2:
	var o := _map_origin()
	return Rect2((FRAME.position - o) / _zoom, FRAME.size / _zoom)


## 把某一格移到畫面中央（小地圖與箭頭的「一鍵跳」）。
## 與 `TL_FOCUS` 走同一條算式——兩份會漂掉。
func _center_view_on(c: Vector2i, immediate: bool = false) -> void:
	var px := Vector2(s.map["size"]) * Shapes.GRID
	_pan_to((px * 0.5 - _center(c)) * _zoom, immediate)


## 小地圖的位置：框架**右下角**內側——離建造欄（左）與能量列（上）最遠的角。
## 尺寸依地圖長寬比縮進 `MINIMAP_MAX`，所以它永遠和地圖同比例（不同比例的
## 縮圖上，「我在哪」那個框會說謊）。
func _minimap_rect() -> Rect2:
	var m := Vector2(s.map["size"])
	var k := minf(MINIMAP_MAX.x / m.x, MINIMAP_MAX.y / m.y)
	var sz := m * k
	return Rect2(FRAME.end - sz - Vector2(MINIMAP_PAD, MINIMAP_PAD), sz)


func _draw_minimap() -> void:
	if not _oversized() or _mini_ttl <= 0.0:
		return
	# ★ 最後 `MINI_FADE` 秒淡出。**整體透明度乘在每一筆上**，退場時底板、
	#   路徑、視野框一起淡——只淡其中幾樣會出現「框還在、底板不見了」。
	var fade := clampf(_mini_ttl / MINI_FADE, 0.0, 1.0)
	var r := _minimap_rect()
	# ★ 底板往外長，**外框畫在 `r` 上**（B2.1d）。舊版把框也畫在 `box` 上，
	#   於是推到底時視野框離可見的邊還有 5px ——使用者回報「小地圖滑到底
	#   不會貼邊」。框就是地圖的邊界，底板只是讓它在遊戲畫面上讀得出來。
	draw_rect(r.grow(5.0), Palette.alpha(Palette.BG_PANEL, 0.96 * fade))
	draw_rect(r, Palette.alpha(Palette.BORDER_STRONG, fade), false, 1.0)
	# 世界座標 → 小地圖座標。
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	var cell := maxf(1.0, Shapes.GRID * k)

	for c: Vector2i in s.path:
		draw_rect(
			Rect2(r.position + Vector2(c) * cell, Vector2(cell, cell)),
			Palette.alpha(Palette.TIDE_DEEP, fade)
		)
	# 玩家節點：小地圖上讀的是**產線的形狀**，不是個別節點，所以一律同一個點。
	for n: Dictionary in s.nodes:
		draw_rect(
			Rect2(r.position + Vector2(n["cell"]) * cell, Vector2(cell, cell)),
			Palette.alpha(Palette.ORDER_CYAN, fade)
		)
	# 問題標記：**比節點大一倍** ＋ 脈動。要在一堆青點裡被一眼挑出來，
	# 只換顏色不夠（§4.3b）。
	var pulse := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.45)
	for c: Vector2i in _problem_cells():
		var at := r.position + Vector2(c) * cell - Vector2(cell, cell) * 0.5
		draw_rect(
			Rect2(at, Vector2(cell, cell) * 2.0),
			Palette.alpha(Palette.WARN_ORANGE, pulse * fade)
		)
	# 視野框：「我在哪」——這是小地圖與一張縮圖的唯一差別。
	var vw := _view_world_rect()
	draw_rect(
		Rect2(r.position + vw.position * k, vw.size * k).intersection(r),
		Palette.alpha(Palette.ORDER_BRIGHT, fade), false, 1.0
	)


## 邊緣箭頭：畫在框架內緣，指向畫面外的問題。
##
## 只畫**不在畫面內**的——在畫面內的問題本來就看得到，再加一個箭頭是雜訊。
func _draw_arrows() -> void:
	if not _oversized():
		return
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.5)
	for hit: Array in _arrow_hits():
		var at: Vector2 = hit[0]
		var dir: Vector2 = hit[1]
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			at + dir * ARROW_SIZE,
			at - dir * ARROW_SIZE * 0.6 + perp * ARROW_SIZE * 0.75,
			at - dir * ARROW_SIZE * 0.6 - perp * ARROW_SIZE * 0.75,
		]), Palette.alpha(Palette.WARN_ORANGE, a))


## 箭頭的位置、方向與目標格：`[[螢幕位置, 單位方向, 目標格], ...]`。
## **繪圖與命中判定共用這一支**——兩份會漂掉，而漂掉的症狀是「看得到但點不到」。
func _arrow_hits() -> Array:
	var out: Array = []
	var vw := _view_world_rect()
	var mid := FRAME.position + FRAME.size * 0.5
	# 框架內緣，留出箭頭自己的半徑，否則尖端會被邊緣切掉。
	var inner := FRAME.grow(-(ARROW_SIZE + 6.0))
	for c: Vector2i in _problem_cells():
		if out.size() >= ARROW_MAX:
			break
		var w := _center(c)
		if vw.has_point(w):
			continue
		var dir := (_to_screen(w) - mid)
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		# 從框架中心往那個方向射到內緣：兩軸各算一次，取先撞到的那一個。
		var tx := INF if is_zero_approx(dir.x) else (inner.size.x * 0.5) / absf(dir.x)
		var ty := INF if is_zero_approx(dir.y) else (inner.size.y * 0.5) / absf(dir.y)
		out.append([mid + dir * minf(tx, ty), dir, c])
	return out


## 導引的點擊。回傳「有沒有吃掉這一次點擊」——吃掉了就不可以再當成蓋節點，
## 否則點小地圖會在它底下的那一格蓋出東西來。
func _guide_click(pos: Vector2) -> bool:
	if not _oversized():
		return false
	for hit: Array in _arrow_hits():
		if pos.distance_to(hit[0] as Vector2) <= ARROW_HIT:
			_center_view_on(hit[2] as Vector2i)
			return true
	# ★ **看不見就不攔截**（B2.1d.1）。小地圖蓋在地圖右下角，常駐攔截等於
	#   那一塊永遠蓋不了東西——使用者回報「有些地方會點不到」。
	if _mini_ttl <= 0.0 or not _minimap_rect().grow(5.0).has_point(pos):
		return false
	# 按下就開始拖曳；放開才結束（見 `_gui_input`）。單擊仍然等於「跳一次」，
	# 因為按下的當下就已經 seek 過一次了。
	_mini_drag = true
	_mini_seek(pos)
	return true


## 把小地圖上的一點換算成地圖格，並把視野**平滑**移過去。
func _mini_seek(pos: Vector2) -> void:
	var r := _minimap_rect()
	var k := r.size.x / (float(s.map["size"].x) * Shapes.GRID)
	_center_view_on(Shapes.to_grid((pos - r.position) / k))


## ★ 大圖導引自檢（`TL_CLICKTEST=1 TL_PANEL=endless`，B2.1b）。
##
## 這一支驗的就是 B2.1b 的 DoD：**瓶頸節點即使不在畫面內也能在 30 秒內被找到**。
## 「30 秒」對自檢沒有意義，能驗的是它的前提——**問題在畫面外時，畫面上真的
## 有一個指得到它、而且點得到的東西**。
##
## 造問題的方式：在畫面外的礦點上蓋一座採集器、不接任何導管。它的產出推不
## 出去 → `stuck` → `滿溢`（和三態徽章同一份判定），一個節點就成立，不必
## 佈一整條產線。
func _guide_selftest() -> void:
	var big: bool = _oversized()

	# 找一個**開場看不到**的礦點——大圖的重點就是「畫面外」。
	var vw := _view_world_rect()
	var target := Vector2i(-1, -1)
	for c: Vector2i in (s.map["ore"] as Array):
		if not vw.has_point(_center(c)):
			target = c
			break
	var found_offscreen: bool = target.x >= 0

	if found_offscreen:
		# ★ **先把視野移過去才蓋得到**：那一格在畫面外，合成點擊落在框架外
		#   會被輸入層擋掉（第一版就是這樣紅的——而那個行為是對的，玩家也
		#   點不到看不見的格子）。蓋完再 `_reset_view()` 把它送回畫面外。
		_center_view_on(target, true)
		for _i in 2:
			await get_tree().process_frame
		_press(_build_buttons["extractor"])
		_click(target)
		for _i in 3:
			await get_tree().process_frame
		# 推幾個 tick，`node_state` 才算得出 `滿溢`。
		for _i in 6:
			BattleController.step(s)
		_reset_view()
		for _i in 2:
			await get_tree().process_frame
	var placed: bool = not s.node_at(target).is_empty()
	var back_offscreen: bool = placed and not _view_world_rect().has_point(_center(target))
	var flagged: bool = _problem_cells().has(target)

	# 箭頭：它在畫面外，所以應該有一個指著它的箭頭。
	var arrows := _arrow_hits()
	var arrow_at := Vector2(-1, -1)
	for hit: Array in arrows:
		if (hit[2] as Vector2i) == target:
			arrow_at = hit[0]
	var arrowed: bool = arrow_at.x >= 0
	# 箭頭要**在框架內**，不然它自己就在畫面外（第一版就是這樣：內縮沒算箭頭
	# 自己的半徑，尖端被邊緣切掉一半）。
	var arrow_inside: bool = arrowed and FRAME.has_point(arrow_at)

	# 一鍵跳：點那個箭頭，目標要進到畫面內。
	var jumped := false
	if arrowed:
		_click_at(arrow_at)
		for _i in 2:
			await get_tree().process_frame
		# ★ 補間中途的 `_pan` 還沒到位——`_settle_view()` 把「動畫沒跑完」
		#   和「位置算錯」分開，否則這條斷言會變成在驗補間速度。
		_settle_view()
		jumped = _view_world_rect().has_point(_center(target))

	# ★ 推到底要真的貼到地圖的邊（RG-121）。使用者回報「小地圖滑到底不會貼邊」
	#   ——那是視野框與小地圖外框之間的內縮，肉眼在縮放過的截圖上判不準，
	#   所以這裡用數字驗：夾到底之後視野的世界矩形要對齊地圖的角。
	var msz := Vector2(s.map["size"]) * Shapes.GRID
	_pan_to(Vector2(99999.0, 99999.0), true)
	var tl := _view_world_rect().position
	_pan_to(Vector2(-99999.0, -99999.0), true)
	var br := _view_world_rect().end
	var flush: bool = (
		absf(tl.x) < 0.5 and absf(tl.y) < 0.5
		and absf(br.x - msz.x) < 0.5 and absf(br.y - msz.y) < 0.5
	)
	_reset_view()

	# 小地圖：點左上角，視野要往左上走（而且**不可以在那裡蓋出東西**）。
	#
	# ★ 先切成「中繼」再點：中繼哪裡都蓋得起來，所以 `mini_safe` 才是真斷言。
	#   用採集器的那一版是**假通過**——點到非礦點本來就會被擋，攔不攔截都一樣綠。
	_press(_build_buttons["relay"])
	var r := _minimap_rect()
	var pan_before := _pan
	# ★ 哨兵字串，不是「節點數沒變」。節點數那一版**紅不起來**：那一格剛好
	#   不能蓋，攔不攔截都是綠的（第一版的假斷言）。`_act()` 在 BUILD 模式下
	#   **一定**會覆寫 `_message`（成功是空字串、失敗是原因），所以哨兵還在
	#   ＝ 這次點擊根本沒走到建造層。
	_message = "＿哨兵＿"
	# ★ 點「離目前視野最遠的那個角」，不是固定點左上角。固定左上是**看種子
	#   臉色**的斷言：前一步的箭頭跳轉若剛好把視野帶到左上，`_pan` 已經夾在
	#   (0,0)，再點左上當然不會動——測試紅掉而產品沒問題（`TL_SEED=42` 實際
	#   踩到）。確定性的閘門不可以有「某些種子才過」這種行為。
	var msize := Vector2(s.map["size"]) * Shapes.GRID
	var vcen := _view_world_rect().get_center() / msize
	_click_at(r.position + Vector2(
		6.0 if vcen.x > 0.5 else r.size.x - 6.0,
		6.0 if vcen.y > 0.5 else r.size.y - 6.0
	))
	for _i in 2:
		await get_tree().process_frame
	var mini_moved: bool = _pan_goal != pan_before
	var mini_safe: bool = _message == "＿哨兵＿"

	# ★ 按住拖曳（B2.1d，使用者指定）：**按住不放時視野要持續跟著游標**。
	#   ⚠ `_click_at()` 是按下**即放開**，所以要自己按住——第一版直接接在
	#   上一次點擊後面送移動事件，`drag=false`，因為那時早就放開了。
	var opp := r.position + Vector2(
		r.size.x - 6.0 if vcen.x > 0.5 else 6.0,
		r.size.y - 6.0 if vcen.y > 0.5 else 6.0
	)
	_press_at(r.position + r.size * 0.5, true)
	for _i in 2:
		await get_tree().process_frame
	var drag_from := _pan_goal
	_move_at(opp)
	for _i in 2:
		await get_tree().process_frame
	var dragged: bool = _pan_goal != drag_from
	# 放開之後再移動就**不可以**再跟著跑，否則等於滑鼠一直黏著小地圖。
	_press_at(opp, false)
	var after_release := _pan_goal
	_move_at(r.position + r.size * 0.5)
	for _i in 2:
		await get_tree().process_frame
	var drag_stops: bool = _pan_goal == after_release
	# 平滑：目標已經到了，但 `_pan` 還在路上（補間真的存在，不是瞬移）。
	var smooth: bool = not _pan.is_equal_approx(_pan_goal)
	_settle_view()

	# ★ 小地圖不常駐（B2.1d.1）：視野一動就在，靜止 `MINI_HOLD` 秒後退場，
	#   **退場後不得再攔截點擊**——常駐攔截等於右下角那一塊永遠蓋不了東西。
	var mini_on: bool = _mini_ttl > 0.0
	_mini_ttl = 0.0
	# 哨兵同前：`_act()` 在 BUILD 模式下一定會覆寫 `_message`，
	# 哨兵被蓋掉 ＝ 這一次點擊真的走到了建造層（＝小地圖沒有擋）。
	_press(_build_buttons["relay"])
	_message = "＿哨兵＿"
	_click_at(r.position + r.size * 0.5)
	for _i in 2:
		await get_tree().process_frame
	var mini_gone: bool = _message != "＿哨兵＿"
	# 再動一下視野，它要自己回來。
	_center_view_on(target)
	for _i in 2:
		await get_tree().process_frame
	var mini_back: bool = _mini_ttl > 0.0
	_settle_view()

	# 可讀性地板：大圖的縮放下限是 24px／格，不是 fit（RG-59）。
	var floor_ok: bool = Shapes.GRID * _fit >= Shapes.MIN_READABLE_CELL - 0.001

	# ★ 視野框佔小地圖的比例 ＝ 看得到的比例。**這一條用肉眼判不準**
	#   （小地圖只有 232px 寬，視野框和外框差幾個像素），所以用數字。
	#   兩軸都必須 < 1（真的有看不到的部分）也都必須 > 0.3（不然是算錯了，
	#   而算錯的症狀正是「小地圖上那個框說謊」）。
	var frac := _view_world_rect().size / msize
	var frac_ok: bool = (
		frac.x > 0.3 and frac.x < 1.0 and frac.y > 0.3 and frac.y < 1.0
	)

	var ok: bool = (
		big and found_offscreen and placed and back_offscreen and flagged and arrowed
		and arrow_inside and jumped and mini_moved and mini_safe and floor_ok and frac_ok
		and flush and dragged and drag_stops and smooth
		and mini_on and mini_gone and mini_back
	)
	print(
		"[TL_CLICKTEST/endless] big=%s offscreen=%s placed=%s back_off=%s flagged=%s arrow=%s"
		% [big, found_offscreen, placed, back_offscreen, flagged, arrowed]
		+ " inside=%s jump=%s mini_pan=%s mini_safe=%s floor=%s（%.1f px/格）"
		% [arrow_inside, jumped, mini_moved, mini_safe, floor_ok, Shapes.GRID * _fit]
		+ " flush=%s drag=%s drag_stop=%s smooth=%s"
		% [flush, dragged, drag_stops, smooth]
		+ " mini_on=%s mini_gone=%s mini_back=%s view=%.0f%%×%.0f%% → %s"
		% [mini_on, mini_gone, mini_back, frac.x * 100.0, frac.y * 100.0, "PASS" if ok else "FAIL"]
	)
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## 放大之後地圖比框架大，多出來的部分要被切掉，否則會爬到頂欄與建造欄底下。
## 直接畫四塊不透明的邊條當遮罩——`Control.clip_contents` 夾的是**整個滿版
## 節點**（＝整個畫面），對「只夾住框架」這件事沒有用，而為此把 1500 行的
## 繪圖搬進一個子節點，換到的只是同一個結果。
func _draw_frame_matte() -> void:
	var f := FRAME
	var w := size.x
	var h := size.y
	for r: Rect2 in [
		Rect2(0.0, 0.0, w, f.position.y),                                  # 上
		Rect2(0.0, f.end.y, w, maxf(0.0, h - f.end.y)),                    # 下
		Rect2(0.0, f.position.y, f.position.x, f.size.y),                  # 左
		Rect2(f.end.x, f.position.y, maxf(0.0, w - f.end.x), f.size.y),    # 右
	]:
		if r.size.x > 0.0 and r.size.y > 0.0:
			draw_rect(r, Palette.BG_DEEP)


## 敵人路徑（`20_ART_DIRECTION.md` §1.6、§7.1 A-2／C-1）。
##
## **兩層，由外而內**：
##   ① **侵蝕暈**（C-1）＝ 路徑外一格。它同時是**敵人 walk-by 的傷害半徑**
##      （`10_GDD.md` §3.5：每 tick 傷害相鄰 1 格內的建築）。氣氛與規則同一個
##      元素——一個元素答兩題，和來襲箭羽是同一條理由（§1.6）。
##   ② **路徑帶本身**。
##
## ★ **只有路徑帶抖動，侵蝕暈是直的**（使用者 2026-08-06 拍板）。
##   第一版兩層都抖，讀起來是「兩條扭來扭去的東西」——而這兩層**要答的問題不同**：
##     · 路徑帶講**氣氛**（潮＝混沌，§0 的視覺論題）→ 抖動。
##     · 侵蝕暈講**規則**（我的建築要退開幾格）→ 一條抖動的線量不出格數。
##   規則層走格線是對的：它讓玩家用格子數邊界，而格子正是他放建築的單位。
func _draw_path() -> void:
	var pathset: Dictionary = s.sets["path"]
	# 暈這一層的實心區 ＝ 暈 ∪ 路徑。
	var solid: Dictionary = _danger_cells(pathset)
	solid.merge(pathset)
	# ① 侵蝕暈：路徑外一格。**淡到不搶戲**（0.13）——它是底噪不是訊息，
	#    玩家要讀的是「我的建築壓在這一圈裡就會被啃」，不是「這裡有東西」。
	#
	# ★ **整片畫（暈 ∪ 路徑），不是只畫外圈那一環**（B2.4.2 code review 抓到）。
	#   只畫環的話，路徑帶抖出去的那 4px 會蓋不到暈，交界露出背景。整片畫則
	#   路徑帶直接疊在暈上面，不管抖多少都不可能有縫。
	var halo := Palette.alpha(Palette.TIDE_DEEP, 0.13)
	# ★ 外緣描一條線（使用者拍板：「要能讀出傷害半徑」）。
	#   **只有填色是不夠的**——一塊淡淡的顏色說得出「這附近危險」，說不出
	#   「危險到哪裡為止」，而後者才是玩家要下的那個決定（建築要退開幾格）。
	#   線只描**最外圈**，所以它是一條輪廓不是第二條帶子。
	var edge := Palette.alpha(Palette.TIDE_DEEP, 0.5)
	for c: Vector2i in solid:
		var quad := _cell_quad(c)
		draw_colored_polygon(quad, halo)
		# 這一邊的鄰居不在實心區 ＝ 它是最外圈。
		for i in 4:
			if not solid.has(c + SIDES[i]):
				draw_line(quad[i], quad[(i + 1) % 4], edge, 1.0)
	# ② 路徑帶本身，疊在暈上面。0.45 疊在 0.13 上 ≈ 0.52。
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in s.path:
		draw_colored_polygon(_band_quad(c, pathset), band)
	_draw_incoming()
	for c: Vector2i in s.map.get("crossings", []):
		_draw_crossing(c)


## 路徑外一格（Chebyshev 距離 1），**不含路徑本身**。回傳的是**集合**不是陣列。
##
## ＝ `10_GDD.md` §3.5 的 walk-by 傷害範圍，不是另外發明的一個半徑。對得上的是
## `BattleController.BLAST_CELLS`（Chebyshev ≤ 1 的九格）與 `Tide.BLAST = 1`。
##
## ⚠ **它講的是「建築（節點）」，不是導管**（B2.4.2 code review 抓到的一條真的
##   矛盾，結論是修措辭不是修畫面）。兩條規則在同一片像素上都成立：
##     · **節點沒有任何免疫** → 蓋在這一圈裡就是會被啃，暈說的是實話。
##     · **導管在橋與引道上免疫**（`Tide.immune_indices()`，`RAMP = 1`），
##       而那幾格正好落在這一圈裡。
##   所以**不要**在橋兩側把暈挖一個缺口去「修正」它——那會讓一個蓋在缺口裡的
##   中繼看起來安全，而它會被啃。導管的那半邊由**橋的圖形**負責講（§1.6：
##   「架高」是「橋上導管不受攻擊」的唯一解釋），兩個元素各講各的那一半。
##
## ★ **回傳集合是這支函式的重點**（B2.4.2 code review 抓到）：第一版回傳陣列，
##   於是「這一格是不是暈」在別處只能用一支 `_is_danger()` 重跑一次 3×3 掃描——
##   同一個 3×3 迴圈寫了兩遍（重複程式碼），而且它落在 `_draw()` 的內圈裡。
##   實際成本是每幀約 45,000 次查表，**而我在這裡寫的註解說「760 次」**——
##   那個數字只算了這支函式自己，沒算下游。回傳集合之後查表變 O(1)，
##   整條路徑層降到每幀約 6,500 次，`_is_danger()` 整支刪掉。
##
##   教訓與 `benchmarks-need-their-own-assertions` 同一條：**註解裡的效能宣稱
##   如果沒有量過，它就只是一個願望。** 這裡的數字是照實際呼叫次數推的。
##
## 每幀重算而不快取：快取要跟著地圖切換失效，而那是一個會忘記的鉤子。
func _danger_cells(pathset: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var size: Vector2i = s.map["size"]
	for c: Vector2i in s.path:
		for d: Vector2i in NEIGHBOURS:
			var n := c + d
			if pathset.has(n) or out.has(n):
				continue
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				continue
			out[n] = true
	return out


## 一格的四角多邊形，**貼齊格線**。角的順序與 `SIDES` 對得上（第 i 邊 ＝ i→i+1）。
func _cell_quad(c: Vector2i) -> PackedVector2Array:
	var quad := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		quad.append(_world(c + corner))
	return quad


## 一格的四角多邊形，外緣帶抖動（`Shapes.band_jitter`）。**只有路徑帶用它**
## （侵蝕暈走 `_cell_quad`，理由見 `_draw_path`）。
##
## **抖動掛在格點上**：相鄰兩格共用的角落算出同一個偏移，所以帶子不會裂開。
## 內部格點（四周四格都在 `solid` 裡）不偏移，否則帶子中間會出現縫。
##
## ★ **外凸的轉角磨掉尖角**（B2.9，§7.2 A-2 沒做完的那一半）。
##   §1.6 的原文是「抖動 ＋ **轉角改圓弧或磨掉尖角**」，而 B2.4.3 只做了抖動：
##   帶子的邊緣不再筆直，但**每一個轉彎仍然是硬 90°**，而轉角正是「這是機器畫的」
##   最強的訊號——直邊可以說成是水流的方向，直角不行。
##
##   做法是**倒角**：一個只有這一格碰得到的格點（四周只有自己是路）是外凸角，
##   在那裡吐兩個點而不是一個，沿兩條邊各退 `BAND_CHAMFER`。
##   凹角（四周三格是路）不動——凹角是兩條帶子交會的內側，磨它只會開一個洞。
## 倒角吃掉一格的多少（比例，不是像素）。**比例才會隨縮放一起長**——
## 寫死 7px 的第一版在 fit 倍率下只改了 30 個像素，在 300% 下更是看不見，
## 而「看不見的東西等於沒做」是 §7.3 C-2 自己的判準。
const BAND_CHAMFER := 0.3

func _band_quad(c: Vector2i, solid: Dictionary) -> PackedVector2Array:
	# ① 先把四個（抖動過的）角算出來。
	var base := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		var g := c + corner
		var w := _world(g)
		if not _interior_vertex(g, solid):
			w += Shapes.band_jitter(g.x, g.y)
		base.append(w)
	# ② 再倒角。**沿著實際的邊 `lerp`**，不是沿著「名目上的格子方向」推一段固定長度。
	#
	#   ⚠ B2.9 的第一版是後者，而那會產生**自我相交的多邊形**：偏移量由
	#   `GRID × zoom` 算，起點卻是抖動過的角，兩者對不起來時兩個倒角點會交叉，
	#   Godot 的三角化當場失敗（`Invalid polygon data`）。放大鏡頭時每一幀噴
	#   一百多條——**而 fit 倍率下一條都不噴，所以 B2.9 的驗收完全沒看到**。
	#   走 `lerp` 之後兩個點必定落在自己那條邊上，`0.3 + 0.3 < 1` 就結構上不可能相交。
	var quad := PackedVector2Array()
	for i in CORNERS.size():
		var g := c + CORNERS[i]
		if not _outer_corner(g, solid):
			quad.append(base[i])
			continue
		var prev: Vector2 = base[(i + CORNERS.size() - 1) % CORNERS.size()]
		var next: Vector2 = base[(i + 1) % CORNERS.size()]
		quad.append(base[i].lerp(prev, BAND_CHAMFER))
		quad.append(base[i].lerp(next, BAND_CHAMFER))
	return quad


## 這個格點是不是**外凸角**（四周四格裡只有一格是路）。
## 凹角（三格是路）回 false——那是兩段帶子交會的內側，磨它會開一個洞。
func _outer_corner(g: Vector2i, solid: Dictionary) -> bool:
	var n := 0
	for d: Vector2i in AROUND:
		if solid.has(g + d):
			n += 1
	return n == 1


## 這個格點是不是內部格點（四周四格都在 `solid` 裡）。
func _interior_vertex(g: Vector2i, solid: Dictionary) -> bool:
	for d: Vector2i in AROUND:
		if not solid.has(g + d):
			return false
	return true


## ★ 來襲方向（`20_ART_DIRECTION.md` §1.6）。一條帶子只說「這裡是路」，
## **沒說潮從哪邊來**——而那是新玩家的第一個問題，也決定所有擺位。
## 順著箭羽走就找得到核心，一個元素答兩題（`50_QA_PLAN.md` §4.4）。
func _draw_incoming() -> void:
	var col := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var i := 2
	while i < s.path.size() - 1:
		var here: Vector2i = s.path[i]
		var dir := Vector2(s.path[i + 1] - here).normalized()
		var back := -dir * 5.0
		var wing := dir.orthogonal() * 5.0
		var tip := _center(here) + dir * 4.0
		draw_line(tip, tip + back + wing, col, 2.0)
		draw_line(tip, tip + back - wing, col, 2.0)
		i += 4


## 跨越點（橋）：**「架高」必須用畫的說清楚**——它是「橋上導管不受攻擊」
## 這條規則的唯一解釋（`20_ART_DIRECTION.md` §1.6）。硬性要求：一眼可辨。
##
## ★ B2.4.2（§7.1 B-1）：三個元素**本來就都在**，問題是強度與語彙——
##   ① 落影內縮 3px、alpha 0.55 → fit 倍率下幾乎看不到。改成**滿格 ＋ 往下偏移**，
##      投影偏移才是「這東西浮在上面」的視覺線索（一圈等距的暗邊只是描邊）。
##   ② 引道是**直線延長 6px**，不是 §1.6 寫的 45°。而 45° 是秩序側的既有語彙
##      （導管只走 90°/45°，§7.2）——用它，橋才接得回玩家自己的線。
func _draw_crossing(cell: Vector2i) -> void:
	var p := _world(cell)
	var g := Shapes.GRID
	var path: Dictionary = s.sets["path"]
	var horizontal := path.has(cell + Vector2i(1, 0)) or path.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	# 落影：滿格、往行進方向的**側邊**偏 4px。有偏移才讀得出高度。
	var drop := Vector2(0, 4) if horizontal else Vector2(4, 0)
	# alpha 0.55 而不是 0.7：§1.6 要的是「橋下留**可見的**路徑帶陰影」——
	# 陰影要看得見，但帶子也要還在。真正讓它讀成「架高」的是**偏移**不是深度。
	draw_rect(
		Rect2(p + drop, Vector2(g, g)), Palette.alpha(Palette.BG_DEEP, 0.55)
	)
	if horizontal:
		# 橋面沿垂直方向（導管要南北橫越）。
		for dx: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		for dy: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
		# ★ 45° 引道：橋頭往外張開，把橋面接回地面高度。
		for dy: float in [-6.0, g + 6.0]:
			var away := signf(dy)
			for dx: float in [7.0, g - 7.0]:
				var out_x := -6.0 if dx < g * 0.5 else 6.0
				draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + out_x, dy + away * 6.0), c, 2.0
				)
	else:
		for dy: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)
		for dx: float in [-6.0, g + 6.0]:
			var away := signf(dx)
			for dy: float in [7.0, g - 7.0]:
				var out_y := -6.0 if dy < g * 0.5 else 6.0
				draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + away * 6.0, dy + out_y), c, 2.0
				)


func _draw_ore_cells() -> void:
	var occupied: Dictionary = s.occupied()
	for c: Vector2i in s.map.get("ore", []):
		if occupied.has(c):
			continue  # 蓋上採集器後由節點填實
		draw_arc(_center(c), 10.0, 0.0, TAU, 24, Palette.ORDER_DIM, 2.0)


## ★ 潮鳴的場（B1.8，`20_ART_DIRECTION.md` §1.6）。
##
## **它是全案唯一 `rof = 0` 的塔**：不產生開火線、不播開火音，而每秒吃 9 能量。
## B1.7 之前它在畫面上一個回饋都沒有——玩家無從確認自己花 90 礦砂買的東西
## 有沒有在工作，而「塔在交戰時每秒吃電」正是本作的核心取捨（`10_GDD.md` §7.4）。
##
## 三個刻意的決定：
##   ① **只在交戰時畫**。光環本來就只在射程內有敵人時啟動；恆亮的圈會讓
##      「現在到底有沒有在吃電」這件事反而讀不出來。
##   ② **透明度跟著能量滿足率走**。電不夠時控場真的比較弱（§7.4），
##      圈跟著淡下去，因果就在同一個畫面上。
##   ③ 半徑是**實際射程**（5 格＝160px），和交戰環的 15px 差一個數量級——
##      「同一個位置上的兩個訊息，換顏色不夠，要換形狀」（§4.3b）。
func _draw_fields() -> void:
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		if not def.has("slow") or not _engaged.get(int(n["id"]), false):
			continue
		var k := clampf(
			float((s.rates["satisfaction"] as Dictionary).get(n["id"], 1.0)), 0.0, 1.0
		)
		# ★ 權重是實看調出來的（B1.8）。第一版是 `pulse01(...) * 0.5`，alpha 落在
		#   0.23–0.50——在 `bg.panel` 上那條線**讀起來是灰的不是青的**，整張全景圖
		#   上幾乎看不見（第一張驗收截圖當場抓到）。青色要到 0.6 以上才讀得出色相。
		#
		#   ★ 調的是**下限**不是振幅：`TL_SHOT` 凍結在單一 tick，而脈動的相位由
		#     tick 決定——驗收截圖剛好落在波谷（tick 1556 → alpha 0.48）。
		#     谷底讀得出來，整條曲線就都讀得出來；只拉振幅會讓它一半時間是隱形的。
		var a := Motion.pulse01(s.tick_count, Motion.AMBIENT, 0.72) * 0.92 * k
		draw_arc(
			_center(n["cell"]), float(def.get("range", 0.0)) * Shapes.GRID, 0.0, TAU, 64,
			Palette.alpha(Palette.ORDER_CYAN, a), 2.0
		)


func _draw_conduits() -> void:
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	for c: Dictionary in s.conduits:
		var bonus := float(s.mods["cap_bonus"])
		var cap := Build.conduit_cap(int(c["level"]), bonus)
		var flow := float(flows.get(c["id"], 0.0))
		var to_node: Dictionary = s.node_at(c["b"])
		var starving := (
			not to_node.is_empty() and float(sat.get(to_node["id"], 1.0)) < 0.95 and flow > 0.0
		)
		# 線寬的分母是**全遊戲的最大 cap**，不是這條線自己的——粗細因此在
		# 全圖上可以互相比較，而且加粗一條線之後它會真的變粗（B1.1 使用者回報）。
		var w := Shapes.conduit_width(flow, Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus))
		# 受損：先鋪一圈 warn.orange 光暈。**線被打斷之前要先看得出它在挨打**，
		# 否則產能中斷對玩家來說會是憑空發生的。
		if float(c["hp"]) < 40.0:
			var hurt := 1.0 - float(c["hp"]) / 40.0
			draw_line(
				_center(c["a"]), _center(c["b"]),
				Palette.alpha(Palette.WARN_ORANGE, 0.25 + 0.55 * hurt), w + 6.0
			)
		draw_line(_center(c["a"]), _center(c["b"]), Palette.conduit(flow, cap, starving), w)
		# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
		# **垂直短刻線，不是圓點**：圓點會和流動珠混成同一個東西，而兩者語意相反
		# （固定的線材等級 vs 變動的流量）——`20_ART_DIRECTION.md` §1.4a。
		var pa := _center(c["a"])
		var pb := _center(c["b"])
		var perp := (pb - pa).normalized().orthogonal()
		# ★ B1.6.1：刻度必須**明確伸出管緣**。原本固定 ±5px，而滿載的管子
		#   本身就有 8px 寬——刻度只比它寬一點點，畫成近白青之後讀起來是
		#   「管子這裡破了一個洞」（使用者回報「有破圖」）。
		#   現在長度跟著線寬走並固定外露 3px，而且貼在起點端而不是線長 12%
		#   那個沒有意義的位置：等級是這條線的屬性，標在接頭上才讀得出來。
		var reach := w * 0.5 + 3.0
		var tick_w := maxf(1.5, 2.0 / maxf(0.2, _zoom))
		var step := maxf(3.0, 4.0 / maxf(0.2, _zoom))
		# 起點要**閃過節點自己的圖形**：節點最大到半徑 13（碎浪的外框），
		# 貼太近就被畫在它底下看不見（第一版貼 6px，截圖當場抓到）。
		# 短線上再夾一次，免得刻度跑過中點看起來像掛在另一端。
		var span := pa.distance_to(pb)
		var head := minf(17.0, span * 0.32)
		for i in range(int(c["level"])):
			var at := pa + (pb - pa).normalized() * (head + step * float(i))
			draw_line(at - perp * reach, at + perp * reach, Palette.ORDER_BRIGHT, tick_w)
		# ★ 流動珠：礦砂／能量／合金各一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		# 只有一種資源在跑時**走線的正中央**：多數導管都是這種，
		# 硬要分排會讓珠子懸在細線外面，看起來像掉出來的東西。
		# 三種同時跑的線（熔爐那條）中間讓給合金，礦砂與能量各退一邊。
		# ★ B1.6.1：珠子**一律走中線**，多種資源沿長度錯開相位，不再各佔一排。
		#
		# 原本是垂直偏移 `w * 0.45 + 1.0`，而它沒有夾在管子裡：8px 寬的線上
		# 偏移 4.6 ＋ 珠半徑 2.6 ＋ 光暈 1.2 ＝ 8.4，遠超過半寬 4——**珠子兩側
		# 都掛在管子外面**，看起來像從管子裡漏出來的（使用者回報「有破圖」）。
		#
		# 夾住偏移不是辦法：真的夾進去之後三排珠子會擠成一團更難讀。
		# 改成共用中線、**相位錯開**：白、琥珀、紫依序前進，位置不再承載資訊
		# （那本來也不是它該講的事），顏色照樣分得出是哪一種資源。
		var lanes: Array = []
		for pair: Array in [
			[net.x, Palette.TEXT_PRIMARY], [net.y, Palette.ENERGY_AMBER],
			[net.z, Palette.ALLOY_VIOLET],
		]:
			if absf(float(pair[0])) >= BEAD_MIN_RATE:
				lanes.append(pair)
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀、合金珠的紫本來就與線色分屬不同色相，維持配色紀律 2。
		for i in lanes.size():
			_draw_beads(
				pa, pb, float(lanes[i][0]), lanes[i][1], w,
				float(i) / float(lanes.size())
			)


## ★ 流動珠（`20_ART_DIRECTION.md` §1.4a）。線寬與顏色說的是「這條線有多滿」，
## 沒有任何元素在說「東西正在動」——一張靜態的粗線看起來是接線圖，不是產線。
##
## **這不是實體物品搬運。** 珠子的位置由已解出的流率 ＋ 經過的模擬秒數推算，
## 模擬層一無所知，珠子不參與任何判定（`10_GDD.md` §3.1 鎖定：流量網路）。
## 一旦它變成有位置有狀態的實體，`O(物品數)` 的效能與確定性負債就回來了。
##
## `amount` 帶號：正＝沿 a→b、負＝反向。速度 ∝ 流率，間距固定。
##
## ponytail: 每顆珠子兩個 `draw_circle` ＝ 每幀約 `導管數 × 線長/20 × 2` 次繪製。
## M0 一屏（13 條導管）約 500 次，無感；`30_TECH_DESIGN.md` §5 的壓力情境
## （2000 條導管）會爆到六位數。到那時改成單一 `draw_multiline` 批繪或
## 用 shader 把相位推進 GPU——**在量到之前不要先做**。
## `lane_phase` 是 0..1 的相位偏移：多種資源在同一條線上時用它錯開，
## 於是白、琥珀、紫依序前進而不是疊在一起（B1.6.1）。
func _draw_beads(
	a: Vector2, b: Vector2, amount: float, col: Color, width: float,
	lane_phase: float = 0.0
) -> void:
	if absf(amount) < BEAD_MIN_RATE:
		return  # 沒在流動的線必須是靜止的——這是「哪裡斷了」最快的讀法
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var u := (b - a) / span
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t := (float(s.tick_count) + _accum / BattleController.TICK) * BattleController.TICK
	# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
	# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
	# ★ 上限收到半寬：珠子不得比管子胖，否則它就是「管子上的腫塊」。
	var r := clampf(width * 0.30, 1.4, width * 0.5)
	# ★ 描邊是**螢幕固定粗細**（B1.6.1）。原本是固定 +1.2 地圖 px：在 r=1.4 的
	#   細線上，光暈佔了直徑的 46%，讀起來是「管子上的洞」而不是「在跑的東西」；
	#   而放大到 300% 時它又變成一圈很粗的黑框。1px 螢幕在任何倍率下都只是描邊。
	var edge := 1.0 / maxf(0.2, _zoom)
	var x := fposmod(t * amount * BEAD_SPEED + lane_phase * BEAD_GAP, BEAD_GAP)
	while x < span:
		var p := a + u * x
		# **深色描邊是這個元素能被看見的唯一原因**：導管本身就是亮青，
		# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
		draw_circle(p, r + edge, Palette.BG_DEEP)
		draw_circle(p, r, col)
		x += BEAD_GAP


func _draw_nodes() -> void:
	for n: Dictionary in s.nodes:
		var p := _center(n["cell"])
		var full := NodeDefs.hp(String(n["type"]))
		var lv := int(n.get("level", 0))
		var sc := Shapes.level_scale(lv)
		if float(n["hp"]) < full:
			# **血條不是圓環**：儲槽的充能也是琥珀色圓弧，兩個圓弧疊在同一顆
			# 12px 的節點上肉眼分不出來（本批截圖當場抓到）。形狀不同才分得開。
			# ★ B3.9：`15 × sc` 而不是 15——塔身跟著級數長，血條不跟就會被壓在底下。
			var frac := clampf(float(n["hp"]) / full, 0.0, 1.0)
			var bar := Vector2(24.0, 3.0)
			var at := p + Vector2(-bar.x * 0.5, 15.0 * sc)
			draw_rect(Rect2(at, bar), Palette.alpha(Palette.BG_DEEP, 0.8))
			draw_rect(Rect2(at, Vector2(bar.x * frac, bar.y)), Palette.WARN_ORANGE)
		_draw_node_body(n, p)
		_draw_level_marks(lv, String(n["type"]), p)
		_draw_threat(n["cell"], p)
		_draw_engaged(n, p)
		# ★ 級章佔了上緣，徽章再往上退 6px（升過的塔才退）。兩個都畫在同一條
		#   帶子上的話，缺料徽章——**地圖上唯一指出瓶頸的元素**——會被級章遮掉。
		_draw_badge(n, p - Vector2(0.0, 6.0) if lv > 0 else p)


## ★ 級章：一級一枚，**形狀說出那一級買到什麼**（`10_GDD.md` §4.3，B3.9）。
##
## 使用者指定「共 5 級，且每一級都要有外觀上的改變」。體積那個通道
## （`Shapes.level_scale()`）答的是「這座升過幾級」，這個通道答的是
## 「升到的是什麼」——只有數量的話，五級的錨和五級的長哨長得一樣，
## 而它們買到的東西完全不同（一個是機槍，一個是狙擊）。
##
## 四種形狀而不是四種顏色：§4.3b「同一個位置上的兩個訊息，換顏色不夠，
## 要換位置或形狀」。顏色全走 `alloy.steel`——青與琥珀各自專屬秩序與能量
## （§1.1 配色紀律），而「這座被我升過」不屬於任何一邊。
func _draw_level_marks(lv: int, type: String, p: Vector2) -> void:
	for k in lv:
		# 置中排開：五枚 6px 間距 ＝ 總寬 28px，剛好在一格內。
		var x := p.x + float(k) * 6.0 - float(lv - 1) * 3.0
		var y := p.y - 19.0
		match Build.next_step(type, k):
			Build.STEP_RANGE:
				# 朝外（上）的尖角＝伸出去。
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, y - 2.0), Vector2(x + 2.5, y + 2.5), Vector2(x - 2.5, y + 2.5),
				]), Palette.ALLOY_STEEL)
			Build.STEP_ROF:
				# 兩根細直條＝連發。
				draw_rect(Rect2(x - 2.5, y - 2.0, 1.5, 5.0), Palette.ALLOY_STEEL)
				draw_rect(Rect2(x + 1.0, y - 2.0, 1.5, 5.0), Palette.ALLOY_STEEL)
			Build.STEP_SPLASH:
				# 菱形＝往四面炸開（和碎浪的爆散星同一族）。
				draw_colored_polygon(PackedVector2Array([
					Vector2(x, y - 3.0), Vector2(x + 3.0, y),
					Vector2(x, y + 3.0), Vector2(x - 3.0, y),
				]), Palette.ALLOY_STEEL)
			_:
				# 出力（以及沒有 `steps` 的節點）＝實心方，B3.5 起就是這個。
				draw_rect(Rect2(x - 2.5, y - 2.0, 5.0, 4.0), Palette.ALLOY_STEEL)


## ★ 一座節點**畫成什麼樣子**——只看型別，不看它蓋起來沒有（B3.4）。
##
## 抽出來的理由是**擺放預覽要畫同一個東西**。原本預覽只有一個綠框，
## 而使用者的話是「預覽這個角色的模型，而不是純粹是正方形」——
## §1.6 花了整節在講「形狀要說得出這隻角色是什麼」，而玩家做擺位決定的
## 那一刻**看不到那個形狀**，等於那一整節的工作在最需要它的時候缺席。
##
## 抽成函式而不是在預覽那邊再畫一次：十四種節點各有自己的幾何，
## 抄一份的下場是日後加第十五種時只有一邊記得加——而漏掉的那一邊
## **症狀是隱形而不是報錯**（`match` 沒對到就靜靜地什麼都不做，B2.4 中過三次）。
##
## `n` 只需要 `type`；`hp`／`charge` 缺了就當作滿血、空槽（預覽正是這個狀態）。
func _draw_node_body(n: Dictionary, p: Vector2) -> void:
	var full := NodeDefs.hp(String(n["type"]))
	# ★ B3.9：**升過的塔整體變大**（`10_GDD.md` §4.3，使用者指定「每一級都要有
	#   外觀上的改變」）。掛在 `draw_set_transform` 上而不是改十三種形狀的每一個
	#   座標——那是 65 個要維護的數字，而漏掉一種的症狀是隱形。
	#
	#   `p * (1 - sc)` 這個偏移是「以 p 為中心縮放」的展開式：
	#   q ↦ p(1-sc) + sc·q，代入 q = p + off 得 p + sc·off。**不能只寫
	#   `draw_set_transform(p, 0, sc)`**——下面每一筆都畫在絕對座標 `p + off`，
	#   那樣會把整座塔甩到 p + sc·p 去。
	#   預覽傳進來的字典沒有 `level` → sc = 1.0 → 這兩行是空操作。
	var sc := Shapes.level_scale(int(n.get("level", 0)))
	if sc != 1.0:
		draw_set_transform(p * (1.0 - sc), 0.0, Vector2(sc, sc))
	match String(n["type"]):
		"core":
			# ★ **最大的幾何體**，order.bright 描邊（§1.6）。
			#
			# B2.4.2（§7.1 A-4）：原本是 30px，和採集器的 22px 圓沒有量級差，
			# 而**這是全遊戲唯一一個「歸零就結束」的物件**。42px（1.3 格）＋
			# 3px 描邊（`stroke.emphasis`）讓它在 fit 倍率下就是畫面上最大的一塊。
			#
			# 形狀仍是**正方**，和儲槽的同心圓、交戰環、受擊環都分得開
			# （§4.3b「同一個位置上的兩個訊息，換顏色不夠，要換形狀」）。
			# 48 ＝ **1.5 格**（§7.1 A-4 自己訂的數字；第一版寫 42 ＝ 1.3 格，
			# code review 抓到它低於自己的規格）。
			var half := Vector2(24, 24)
			# ★ §1.6 還有一句「**受擊時整體閃 `warn.orange`**」——B2.4.2 之前
			#   核心只有那條和所有節點共用的 24×3 血條，而**核心掉血是這一局
			#   唯一不可逆的事**，它不該和一個中繼被啃長得一樣。
			#   受傷時整顆換成橙色並脈動（`dur.base` ＝ 比心跳急一個量級）。
			# `.get()` 而不是 `n["hp"]`：預覽傳進來的是一個只有 `type` 的字典。
			# 直接索引缺鍵會丟執行期錯誤，而 GDScript 的執行期錯誤**中止這一支函式**
			# ——預覽會變成「什麼都沒畫」，而不是「報錯」（RG-164 的同一個形狀）。
			var hurt: bool = float(n.get("hp", full)) < full
			var body: Color = Palette.WARN_ORANGE if hurt else Palette.ORDER_BRIGHT
			var alarm := Motion.pulse01(s.tick_count, Motion.BASE * 4.0, 0.5) if hurt else 1.0
			draw_rect(Rect2(p - half, half * 2.0), Palette.BG_RAISED)
			draw_rect(Rect2(p - half, half * 2.0), Palette.alpha(body, alarm), false, 3.0)
			# 極慢的呼吸＝這張圖的心跳。**不是警示**（警示是橙色、而且更急），
			# 所以週期取 `dur.ambient` 的兩倍、振幅只在透明度上。
			var beat := Motion.pulse01(s.tick_count, Motion.AMBIENT * 2.0, 0.55)
			draw_rect(
				Rect2(p - Vector2(8, 8), Vector2(16, 16)),
				Palette.alpha(body, beat if not hurt else alarm)
			)
		"extractor":
			draw_circle(p, 11.0, Palette.ORDER_CYAN)
			draw_arc(p, 11.0, 0.0, TAU, 24, Palette.ORDER_BRIGHT, 1.5)
		"generator":
			# 琥珀專屬於能量（§1.1 配色紀律 2）。
			draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), Palette.ENERGY_AMBER)
		"smelter":
			# 六邊形＝加工。合金銀是它的產物色，內圈琥珀講「它一直在吃電」
			# ——熔爐是全圖唯一待機也耗能的建築，那件事要看得出來。
			var hex := PackedVector2Array()
			for k in 6:
				hex.append(p + Vector2(12, 0).rotated(TAU * float(k) / 6.0))
			draw_colored_polygon(hex, Palette.ALLOY_STEEL)
			draw_circle(p, 5.0, Palette.ENERGY_AMBER)
		"relay":
			var d := PackedVector2Array([
				p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)
			])
			draw_colored_polygon(d, Palette.ORDER_DIM)
		"silo":
			var frac := float(n.get("charge", 0.0)) / maxf(1.0, float(NodeDefs.of("silo")["capacity"]))
			draw_arc(p, 12.0, 0.0, TAU, 32, Palette.ORDER_DIM, 2.0)
			if frac > 0.0:
				draw_arc(p, 12.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Palette.ENERGY_AMBER, 4.0)
			# 四隻塔各給一個一眼可辨的幾何體（`20_ART_DIRECTION.md` §1.6）。
			# 全部嚴格對齊格中心——與敵潮的不規則凸包形成對比，那個對比就是主題。
		"anchor":
			# ★ **上寬下窄的梯形＝打進地裡的樁**（B2.4.8，遊玩測試 P3-1）。
			#   舊版是 16px 的青色實心方，而發電機是 22px 的琥珀實心方——
			#   **同一個形狀，只差 6px 與顏色**，違反 §1.6「不靠顏色分辨」。
			#   而這兩個分屬生產側與防線側，正是「這 40 礦砂餵產線還是餵防線」
			#   那個核心決定的兩端，也是最不該混淆的一對。
			#   改錨不改發電機：琥珀實心方和「能量」的關係更強，波及也更大。
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-11, -9), p + Vector2(11, -9),
				p + Vector2(6, 10), p + Vector2(-6, 10),
			]), Palette.ORDER_CYAN)
		"prism":
			# 三角形＝稜鏡。合金銀把「它是最貴的那一座」講出來。
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -12), p + Vector2(11, 7), p + Vector2(-11, 7)
			]), Palette.ALLOY_STEEL)
		"knell":
			# 同心圓＝場。它不開火，畫成「發散」比畫成砲塔誠實。
			draw_arc(p, 11.0, 0.0, TAU, 28, Palette.ORDER_CYAN, 2.0)
			draw_arc(p, 5.0, 0.0, TAU, 20, Palette.ORDER_CYAN, 2.0)
		"reclaimer":
			draw_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), Palette.ORDER_CYAN, false, 2.0)
			draw_circle(p, 6.0, Palette.ORDER_BRIGHT)
		"breaker":
			# ★ **四角爆散星＝濺射**（B2.4.8，遊玩測試 P3-2）。舊版是「實心方
			#   ＋外框」，和回收者的「空心方＋內圓」在 fit 倍率下都讀成
			#   「方框裡包了東西」，內部差異要盯著看。
			#   換成向外炸開的形狀之後，它同時**把自己的機制講出來**——
			#   碎浪是全遊戲唯一一隻範圍傷害的塔（§1.6：形狀要說得出角色是什麼）。
			var burst := PackedVector2Array()
			for k in 8:
				var rad: float = 13.0 if k % 2 == 0 else 5.0
				burst.append(p + Vector2(rad, 0).rotated(TAU * float(k) / 8.0))
			draw_colored_polygon(burst, Palette.ALLOY_STEEL)
			# ── 招募專屬的三隻（B2.4.6）───────────────────────────────
			# 形狀規則同上：**不靠顏色分辨**（§1.6）。方（錨／碎浪）、圓（採集器
			# ／潮鳴）、三角（稜鏡）、菱（中繼）、六邊（熔爐）都已經被佔走了，
			# 所以這三隻各取一個沒人用過的輪廓。
		"longcall":
			# 細長的桅杆，橫桿在**頂端**＝一座瞭望塔。射程 12 是它唯一的賣點，
			# 而「又高又細」是最短的講法。不用合金 → 秩序青。
			# ★ 第一版橫桿在中間，截圖上讀起來是一個**十字**不是一座塔
			#   （分辨得出來，但講錯了話）。移到頂端才成立。
			draw_rect(Rect2(p - Vector2(3, 13), Vector2(6, 26)), Palette.ORDER_CYAN)
			draw_rect(Rect2(p - Vector2(8, 13), Vector2(16, 4)), Palette.ORDER_CYAN)
		"frostreef":
			# 六芒星（三條穿心線）＝發散，和潮鳴的同心圓同一族但認得出是兩隻。
			# 要 40 合金 → 合金銀（與稜鏡／碎浪同一條規則）。
			for k in 3:
				var spoke := Vector2(12, 0).rotated(PI * float(k) / 3.0)
				draw_line(p - spoke, p + spoke, Palette.ALLOY_STEEL, 2.5)
		"ballast":
			# 倒三角 ＋ 頂桿＝一塊吊著的配重。與稜鏡的正三角互為鏡像，
			# 在同一張圖上一眼分得開。要 100 合金 → 合金銀。
			draw_rect(Rect2(p - Vector2(13, 12), Vector2(26, 4)), Palette.ALLOY_STEEL)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-11, -5), p + Vector2(11, -5), p + Vector2(0, 12)
			]), Palette.ALLOY_STEEL)
		_:
			# ★ **沒有這條 default 的時候，漏掉一種的症狀是「隱形」而不是「報錯」**
			#   ——GDScript 的 `match` 沒對到就靜靜地什麼都不做。B2.4 加三隻招募塔
			#   時三隻全中，而使用者是**用眼睛**發現的（「長哨沒有模型顯示」）。
			_no_glyph[String(n["type"])] = true
	# ⚠ 一定要還原：變換是 canvas item 的狀態，不還原的話**這一幀後面畫的每一個
	#   東西**（敵人、彈道、徽章）都會跟著縮放並位移。
	if sc != 1.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ★ 交戰指示：**琥珀＝能量**（配色紀律 2）。有環＝這座塔本 tick 正在吃電。
## 它只講「在不在吃電」；「吃不吃得飽」由三態徽章講（B0.6 前這裡還多畫一段
## 橙色缺口弧，那和 `缺料` 徽章編碼的是同一件事，留一個就好）。
func _draw_engaged(n: Dictionary, p: Vector2) -> void:
	if _engaged.get(int(n["id"]), false):
		# ★ B3.9：半徑跟著級數長，否則滿級的塔會把環頂穿。
		draw_arc(p, 15.0 * Shapes.level_scale(int(n.get("level", 0))), 0.0, TAU, 32,
			Palette.ENERGY_AMBER, 2.0)


## ★ 節點三態徽章（`10_GDD.md` §3.1）。**`正常` 不畫任何東西**——徽章是例外
## 標記，一屏 14 個節點全掛上「我很好」等於把要找的那兩個埋進雜訊裡。
## 靠**形狀**分辨而不只是顏色：倒三角＝空的（缺料）、正三角＝滿的（滿溢）。
##
## ★ **缺料再分兩種**（B2.4.8，遊玩測試 P2-1）：倒三角＝缺礦砂、閃電＝缺電。
##   舊版兩種共用一個橙色倒三角，於是這個「地圖上唯一指出瓶頸的元素」
##   說得出誰在餓、說不出餓的是什麼——而那正是全案核心命題的那一刀。
##   形狀與顏色**同時**不同（§1.6 說換顏色不夠、要換形狀，這裡兩個都換）：
##   閃電走 `energy.amber`，因為 §1.1 配色紀律 2 說琥珀專屬於能量——
##   這一次那條紀律是在幫忙，不是在擋路。
func _draw_badge(n: Dictionary, p: Vector2) -> void:
	match int((s.rates["node_state"] as Dictionary).get(int(n["id"]), SessionState.NORMAL)):
		SessionState.STARVED:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-7, -25), p + Vector2(7, -25), p + Vector2(0, -16)
			]), Palette.WARN_ORANGE)
		SessionState.STARVED_POWER:
			# 五點折線的閃電。**不用描邊**：14px 高的東西加外框只會糊掉。
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(2, -27), p + Vector2(-6, -19), p + Vector2(-1, -19),
				p + Vector2(-3, -13), p + Vector2(6, -22), p + Vector2(1, -22),
			]), Palette.ENERGY_AMBER)
		SessionState.OVERFLOW:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -25), p + Vector2(7, -16), p + Vector2(-7, -16)
			]), Palette.ORDER_BRIGHT)


## ★ 能量列（`10_GDD.md` §6.2 硬性要求 1）：**全畫面最醒目的元件，而且是一條
## 圖形不是一串數字**——長度即資訊，所以它在 `TL_NAKED` 下要留著。
## 琥珀＝供給、右側橙色＝短少的部分（脈動）、細刻度＝需求落在哪裡。
func _draw_energy_bar() -> void:
	var r: Dictionary = s.rates
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var span := maxf(1.0, maxf(supply, demand))
	# ★ 跨滿**框架**而不是跨滿地圖（B1.2.2）：框架恆定，所以這條「全畫面最醒目
	#   的元件」在每一關都是同一個長度，長度即資訊那句話才跨關成立。
	var w := FRAME.size.x
	var at := Vector2(FRAME.position.x, FRAME.position.y - 12.0)
	draw_rect(Rect2(at, Vector2(w, 8.0)), Palette.BG_RAISED)
	draw_rect(Rect2(at, Vector2(w * supply / span, 8.0)), Palette.ENERGY_AMBER)
	if demand > supply:
		# 脈動走 `Motion`（§4.1 時長階、§4.4 可跳過）。B1.6 之前這裡是
		# `sin(tick * 0.4)`、敵人是 `sin(tick * 0.25)`——兩個係數沒有任何理由
		# 不同，看起來卻像兩件不同的事，而且都繞過了 `reduce_motion`。
		var pulse := Motion.pulse01(s.tick_count, Motion.AMBIENT * 0.5, 0.55)
		var x := w * supply / span
		draw_rect(
			Rect2(at + Vector2(x, 0.0), Vector2(w * demand / span - x, 8.0)),
			Palette.alpha(Palette.WARN_ORANGE, pulse)
		)
	draw_rect(Rect2(at + Vector2(w * demand / span - 1.0, -3.0), Vector2(2.0, 14.0)),
		Palette.TEXT_PRIMARY)


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
## ★ 四種開火形態（B1.6.3，`20_ART_DIRECTION.md` §1.7）。
##
## 起因是使用者實玩回報「塔的攻擊可以有更多不同的特效嗎」——查證屬實：
## 五座塔畫的是**同一條 `order.bright` 直線**，濺射半徑玩家完全看不到。
##
## **形態由 `NodeDefs` 既有的機制欄位推導，不新增美術欄位**：所以做不出一座
## 「會濺射但看起來不濺射」的塔，M3 擴到 24 隻角色時也自動正確。
##
## **物理 vs 能量用形狀分，不用顏色分**：琥珀專屬於能量這個**資源**（§1.1
## 配色紀律），拿它去畫「能量傷害」會污染全案最重要的資訊通道——玩家看到
## 琥珀必須永遠是「跟耗能有關」。所以彈丸＝物理、光束＝能量。回收者那顆
## 琥珀珠是唯一的例外，而它是對的：那顆珠真的是能量，正在流回電網。
func _draw_shots() -> void:
	var frac := _accum / BattleController.TICK
	for sh: Dictionary in s.shots:
		# 沒有 `by` 的一律當錨（`TL_CLICKTEST` 手塞的那一發）。
		var def := NodeDefs.of(String(sh.get("by", "anchor")))
		var a := _center(sh["from"])
		var b := _center(sh["to"])
		var t := Motion.progress(BattleController.SHOT_TTL, int(sh["ttl"]), frac)
		var fade := 1.0 - t
		if bool(def.get("pierce", false)):
			_shot_beam(a, b, fade)
			continue
		_shot_bolt(a, b, t, fade)
		# 濺射環只掛在這一發濺射的**第一筆**記錄上（`BattleController`），
		# 所以這裡畫幾次就是幾發，不會被打中的隻數放大。
		if sh.has("splash_at"):
			_shot_splash(_center(sh["splash_at"]), t, fade, float(def.get("splash", 0.0)))
		if float(def.get("reclaim", 0.0)) > 0.0:
			_shot_reclaim(a, b, t)


## 能量貫穿（稜鏡）：**整條線一次亮到底**，寬度 3→1 衰減。
## 貫穿本來就是「這條軸線上的都被打到」，光束是它唯一誠實的畫法。
## 同一 tick 會有多發（每個目標一發）疊在同一條軸線上——那不是缺陷，
## 疊出來的亮度差正好說明「近的那幾隻被打得比較集中」。
func _shot_beam(a: Vector2, b: Vector2, fade: float) -> void:
	draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.10 + 0.18 * fade), 6.0)
	draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 + 0.65 * fade), 1.0 + 2.0 * fade)


## 物理彈丸（錨／回收者／碎浪）：**短促實心的一段沿線飛行**，不是整條線亮起。
## 「有質量的東西飛過去」和「一束光」的差別全在這裡——整條線亮起讀起來
## 永遠是能量，不管畫成什麼顏色。
func _shot_bolt(a: Vector2, b: Vector2, t: float, fade: float) -> void:
	var dir := (b - a)
	var len := dir.length()
	if len < 0.001:
		return
	dir /= len
	# 彈丸長度上限 14px：短程時不可以比整條彈道還長，否則它就變回一條線了。
	var bolt := minf(14.0, len * 0.45)
	var head := a + dir * (bolt + (len - bolt) * Motion.ease_out_cubic(t))
	draw_line(head - dir * bolt, head, Palette.alpha(Palette.ORDER_CYAN, 0.45 + 0.55 * fade), 3.0)


## 濺射（碎浪）：命中點一圈**擴張環**，半徑就是資料裡的 `splash` 格。
## ★ 這個範圍原本玩家**完全看不到**——碎浪比錨貴、吃三座錨的電，
## 而它唯一的賣點（打到一整段隊列）在畫面上沒有任何證據。
func _shot_splash(at: Vector2, t: float, fade: float, splash: float) -> void:
	var r := splash * Shapes.GRID * Motion.ease_out_cubic(t)
	draw_arc(at, r, 0.0, TAU, 28, Palette.alpha(Palette.ORDER_CYAN, 0.15 + 0.45 * fade), 2.0)


## 回收（回收者）：命中後一顆 `energy.amber` 珠**回流到塔**。
## 方向是反的——它送回來的東西才是這座塔存在的理由（§7.4「打破峰值約束
## 的鑰匙」）。走 `t` 的後半段：先看到打中，才看到收回來，因果順序不能反。
func _shot_reclaim(a: Vector2, b: Vector2, t: float) -> void:
	if t < 0.4:
		return
	var k := (t - 0.4) / 0.6
	draw_circle(b.lerp(a, Motion.ease_out_cubic(k)), 3.0, Palette.alpha(Palette.ENERGY_AMBER, 1.0 - k))


## 敵潮屬於**混沌**側（`20_ART_DIRECTION.md` §0）：不規則凸包、不對齊網格、
## 呼吸式脈動。玩家的一切則是正圓正方、嚴格對齊——這個對比就是主題本身。
func _draw_enemies() -> void:
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e)
		var r := float(def.get("radius", 9.0))
		# 敵潮的動態是「有機的呼吸」（§4.2 ease-in-out-sine 循環）；
		# 相位用 id 錯開，一群敵人才不會像節拍器一起脹縮。
		var pulse := Motion.pulse(s.tick_count, Motion.AMBIENT, 0.12, float(e["id"]))
		var armored: bool = float(def.get("armor", 0.0)) > 0.0
		# ⚠ 這個 `fast` 是**看起來快**（速度過門檻），和資料上的 `swift` 旗標
		#   （免疫減速，B3.2）是兩件事。第一版兩個都叫 swift，於是
		#   `elif swift:` 裡面又套一個 `def.get("swift")`——讀的人得先猜哪個是哪個。
		var fast: bool = float(def.get("speed", 1.0)) > SWIFT_SPEED
		# ★ 這裡曾經有兩個殘影當拖尾（B1.6.3 第一版），**實看 A/B 之後砍掉**：
		#   第 5 波的間距是 0.6 格，任何畫在身後的東西都會壓到後面那一隻——
		#   一列 11 隻分得開的敵人變成一條連續的香腸，把「看不出差異」修成了
		#   「看不出有幾隻」。速度線索因此全部收進**本體輪廓**（流線拉長），
		#   不佔用敵人之間的空隙。
		var pts := _enemy_shape(e, p, r, pulse, armored, fast)
		draw_colored_polygon(pts, Palette.TIDE_MAGENTA)
		# ★ 甲板（B1.6.3）：**同形描邊，不是外圈弧**。血量弧已經是 `tide.deep`
		#   的圓弧、畫在 `r+4`，再加一圈外弧就是同一個位置上的兩個訊息——
		#   而 §4.3b 那條規則說「換顏色不夠，要換形狀」。這個專案在這裡踩過
		#   兩次（B0.6 儲槽充能弧撞血條、B1.6 受擊環撞交戰環）。描邊在輪廓
		#   **內側**，和任何弧都不會疊。
		if armored:
			var plate := pts.duplicate()
			plate.append(pts[0])
			draw_polyline(plate, Palette.TIDE_DEEP, 3.0)
		# ★ 亮核心（B1.6.3）：**快**在 16px 上唯一活得下來的線索。
		#   輪廓的壓扁在 fit 倍率幾乎讀不到（實看 A/B 抓到），明度差讀得到。
		#   畫在**中心**而不是外圈：外圈已經有甲板描邊與血量弧兩個訊息了。
		elif fast:
			# ★ **免疫減速的那一隻畫菱形，只是跑得快的畫圓**（B3.2）。
			#   熾泳與潛涌都過得了 `SWIFT_SPEED` 門檻，共用一個亮核心的話，
			#   一條真的規則（抓不抓得住）在畫面上是看不見的。
			#   形狀與大小同時不同（§7.5 的半徑 6 vs 8）——RG-145 的同一條。
			# 下限 1px：`pulse` 在減少動態效果時可能壓到 0，而四個點疊在一起的
			# 多邊形會讓 Godot 的三角化失敗（實跑當場噴 `Invalid polygon data`）。
			var core := maxf(1.0, r * pulse * 0.45)
			if bool(def.get("swift", false)):
				# ★ 用 `draw_polyline` 不是 `draw_colored_polygon`：後者要三角化，
				#   而一個被 `pulse` 壓扁到近乎退化的四邊形會讓它噴
				#   `Invalid polygon data`（合照鉤子當場抓到，一幀好幾條）。
				#   閉合折線沒有這個問題，而在 16px 上「空心菱形 vs 實心圓」
				#   的差別比實心與實心大。
				draw_polyline(PackedVector2Array([
					p + Vector2(0, -core * 1.3), p + Vector2(core, 0),
					p + Vector2(0, core * 1.3), p + Vector2(-core, 0),
					p + Vector2(0, -core * 1.3),
				]), Palette.TIDE_BRIGHT, 2.0)
			else:
				draw_circle(p, core, Palette.TIDE_BRIGHT)
		# ★ 被潮鳴抓住的敵人：輪廓描一圈 `order.cyan`（B1.8）。
		#   **標在敵人身上而不是塔上**——減速 −40%／破甲 −25% 作用在它身上，
		#   標在這裡因果才讀得出來；標在塔上只說得出「它開著」。
		#   閉合折線，和血量弧（`tide.deep` 圓弧）一個是線一個是弧，分得開（§4.3b）。
		# ★ 再生（B3.2）：**輪廓內一圈會呼吸的亮線**。§1.7 的規則是「輪廓由既有的
		#   機制欄位推導」，而再生是這一批唯一沒有現成視覺的規則——迅捷靠速度
		#   （亮核心）、群體靠半徑（小一號），只有它得自己長一個。
		#   用 `tide.bright` 不是新顏色（§1.7 的混沌亮階），和青色的減速圈分得開。
		if float(def.get("regen", 0.0)) > 0.0:
			var knit := pts.duplicate()
			knit.append(pts[0])
			var beat := Motion.pulse(s.tick_count, Motion.AMBIENT, 0.5, float(e["id"]))
			draw_polyline(knit, Palette.alpha(Palette.TIDE_BRIGHT, 0.25 + 0.45 * beat), 2.0)
		var slow := 0.0 if i >= _auras.size() else (_auras[i] as Vector2).x
		if slow > 0.01:
			var ring := pts.duplicate()
			ring.append(pts[0])
			draw_polyline(ring, Palette.alpha(Palette.ORDER_CYAN, 0.35 + 1.4 * slow), 2.0)
		var frac := float(e["hp"]) / maxf(1.0, float(def.get("hp", 1.0)))
		if frac < 1.0:
			draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


## ★ 「正在被啃」的格（B1.6，§4.3「一定要動」清單）。
##
## 敵人 walk-by 每 tick 傷害相鄰 1 格（`Tide.BLAST`），但在畫面上**那一刻完全
## 沒有表現**——節點的血條會慢慢變短，而玩家不知道「現在」有東西在被吃。
## 這裡把模擬層每 tick 都在做的同一份判定畫出來，不新增任何狀態。
func _threat_cells(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in cells:
		for dx in range(-Tide.BLAST, Tide.BLAST + 1):
			for dy in range(-Tide.BLAST, Tide.BLAST + 1):
				out[c + Vector2i(dx, dy)] = true
	return out


## 正在被啃的節點：脈動的**四角括號**。
##
## ★ **形狀必須和「交戰中」的圓環分得開**（第一版就是圓環，截圖當場抓到——
## 交戰環是琥珀圓環、受擊環是橙色圓環，兩個疊在同一顆 12px 的節點上肉眼
## 分不出來）。這是這個專案第二次踩同一個坑：B0.6 的「血條不是圓環」也是
## 因為儲槽充能弧與血條弧撞在一起。**同一個位置上的兩個訊息，換顏色不夠，
## 要換形狀。**
func _draw_threat(cell: Vector2i, p: Vector2) -> void:
	if not _threat.has(cell):
		return
	var a := Motion.pulse01(s.tick_count, Motion.BASE * 2.0, 0.3)
	var col := Palette.alpha(Palette.WARN_ORANGE, a)
	var h := Shapes.GRID * 0.5 - 1.0   # 半格：括號貼著這一格的邊界
	var arm := 6.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * h, sy * h)
			draw_line(corner, corner - Vector2(sx * arm, 0.0), col, 2.0)
			draw_line(corner, corner - Vector2(0.0, sy * arm), col, 2.0)


## ★ 碎片爆（B1.6）。規格直接來自 `20_ART_DIRECTION.md` §161 的反模式清單：
## **「爆炸不用 200 顆粒子。用 3–5 個幾何碎片＋一次縮放閃光」**。
##
## 碎片的形狀服從核心視覺命題（§0 秩序 vs 混沌）——這不是裝飾選擇：
##   `chaos`（敵人消散）＝**不規則三角碎片**、品紅、往外飛並旋轉
##   `order`（建築破裂）＝**正方碎片**、青、往外飛但**不旋轉**（秩序連壞掉都是方的）
## 兩種都配一次縮放閃光環：混沌用實心淡去、秩序用線框擴張。
##
## 零 RNG（`Motion.fragment_dir` 由來源 id 決定方向），所以重播與每日挑戰
## 看到的是同一場爆炸。
## ★ 屏障擋格（B2.1d，使用者指定「類似盾牌隔檔」）。
##
## 畫成**面向來向的一段弧**＋一次白閃：盾牌的語彙是「擋住」，不是「爆開」，
## 所以用弧線而不是圓（圓已經是碎片爆的語彙，兩者不能混）。
## 弧的張角隨減傷比例變大——擋掉四成和擋掉九成看得出差別。
##
## **只在能量傷害被吃掉時出現**，所以它同時回答了「為什麼我打不動」：
## 玩家看到盾就知道換物理傷害的塔（§3.5 的剋制表）。
func _draw_shields() -> void:
	var frac := _accum / BattleController.TICK
	for sh: Dictionary in s.shields:
		var t := Motion.progress(int(sh["life"]), int(sh["ttl"]), frac)
		var at: Vector2 = (
			Vector2(sh["at"] as Vector2i) * Shapes.GRID
			+ Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		)
		var e := Motion.ease_out_cubic(t)
		# ★ **六邊形的護盾泡**，不是一段弧。
		#   第一版畫成朝 +X 的弧：在 32px 的格子上和敵人自己的輪廓分不開，
		#   而且「朝右」對一隻正在往下走的敵人沒有意義（我手上只有格子，
		#   沒有傷害來向）。改成封閉的六邊形之後**與方向無關**，
		#   而且六邊形是本作既有的「硬」語彙（甲殼就是六邊形，§1.7）。
		var r := Shapes.GRID * (0.62 + 0.22 * e)
		var poly := PackedVector2Array()
		for i in 7:
			var a := TAU * float(i) / 6.0 - PI / 2.0
			poly.append(at + Vector2(cos(a), sin(a)) * r)
		draw_polyline(poly, Palette.alpha(Palette.ORDER_BRIGHT, (1.0 - t) * 0.95), 3.0)
		# 擋掉越多，泡越實：40% 與 90% 看得出差別。
		var fill := clampf(float(sh["frac"]), 0.0, 1.0)
		draw_polyline(poly, Palette.alpha(Palette.ORDER_CYAN, (1.0 - t) * 0.45 * fill), 7.0)
		# 起手一瞬的白閃，讓「就是現在被擋了一下」讀得出來。
		if t < 0.35:
			draw_circle(at, Shapes.GRID * 0.30, Palette.alpha(Palette.ORDER_BRIGHT, (0.35 - t) * 1.6))


func _draw_bursts() -> void:
	var frac := _accum / BattleController.TICK
	for b: Dictionary in s.bursts:
		var life := int(b["life"])
		var t := Motion.progress(life, int(b["ttl"]), frac)
		# 玩家操作之外的系統事件，用 ease-out：一開始炸得快，尾巴慢慢淡（§4.2）。
		var e := Motion.ease_out_cubic(t)
		var at: Vector2 = (b["at"] as Vector2) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		var chaos: bool = String(b["kind"]) == "chaos"
		var col := Palette.TIDE_MAGENTA if chaos else Palette.ORDER_CYAN
		var seed_id := int(b["seed"])

		# ── 一次縮放閃光 ──────────────────────────────────────────────
		var flash := Palette.alpha(col, (1.0 - t) * (0.55 if chaos else 0.75))
		if chaos:
			draw_circle(at, 6.0 + 14.0 * e, flash)
		else:
			draw_arc(at, 4.0 + 18.0 * e, 0.0, TAU, 24, flash, 2.0)

		# ── 3–5 個幾何碎片 ────────────────────────────────────────────
		# 數量也由 id 決定（3/4/5 輪替），免得每一次爆炸的顆數都一樣。
		# ★ **數量不動**（§2 反模式清單擋著「200 顆粒子」），動的是**單片的尺寸、
		#   初速與明度**——§7.3 C-2：「3–5 個看不見的碎片等於沒做」。
		#   fit 倍率下一格只有 32px，原本 4–5px 的碎片是三個像素的事。
		var count := 3 + (absi(seed_id) % 3)
		for i in count:
			var dir := Motion.fragment_dir(seed_id, i, count)
			var p := at + dir * (10.0 + 34.0 * e)
			var r := (8.0 if chaos else 6.5) * (1.0 - 0.6 * t)
			# 生命前 30% 用亮階起亮再落回本色。**明度差在小尺寸下活得下來**——
			# 這正是 `tide.bright` 當初被建立的理由（§1.7），同一條經驗直接套用。
			var bright: Color = Palette.TIDE_BRIGHT if chaos else Palette.ORDER_BRIGHT
			var c := Palette.alpha(bright.lerp(col, minf(1.0, t / 0.3)), 1.0 - t)
			if chaos:
				# 不規則三角＋自轉：混沌連碎片都不對齊。
				var spin := float(seed_id) * 0.7 + t * 3.0
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(r * 1.4, 0).rotated(spin),
					p + Vector2(r, 0).rotated(spin + 2.3),
					p + Vector2(r * 0.8, 0).rotated(spin + 4.1),
				]), c)
			else:
				# 正方、不自轉：秩序的碎片仍然是軸對齊的方塊。
				draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), c)


## ★ 敵人的輪廓（B1.6.3，`20_ART_DIRECTION.md` §1.7）。
##
## 三種輪廓**全部由既有的機制欄位推導**，不新增美術資料：
##   預設        9 邊柔性水滴、wobble ±15%          ← 漂蟲
##   `armor > 0` 6 邊硬稜角、wobble ±7%             ← 甲殼（物理打不動它）
##   `speed 快`  沿行進方向拉長的尖銳水滴 ＋ 拖尾   ← 熾泳
##
## 這樣做的第一個理由不是省事，是**設計上不可能說謊**：沒有辦法做出一隻
## 「有護甲但看起來不硬」的敵人。M3 擴到 18 種敵人時也自動正確（§5 內容矩陣）。
##
## 三者仍然全部屬於**混沌**側（§0）：不規則、脈動、不對齊網格。硬稜角指的是
## 頂點少、抖動小，不是變成正六邊形——正多邊形是秩序側的語彙。
func _enemy_shape(
	e: Dictionary, p: Vector2, r: float, pulse: float, armored: bool, fast: bool
) -> PackedVector2Array:
	var sides := 6 if armored else 9
	var amp := 0.07 if armored else 0.15
	var pts := PackedVector2Array()
	# `k` 而不是 `i`：呼叫端已經用掉 `i`（敵人索引），而 GDScript 的 for
	# 迭代變數共享同一個作用域——同名會是 parse error，不是遮蔽。
	for k in sides:
		var a := TAU * float(k) / float(sides)
		# 每隻各自的不規則度，由 id 決定（同一隻永遠長同一個樣子）。
		# 值域收在 ±amp：再寬就會有頂點塌進去，變成尖角旗子而不是水滴。
		var wobble := 1.0 + amp * sin(float(e["id"]) * 3.7 + a * 2.0)
		var v := Vector2(cos(a), sin(a)) * r * pulse * wobble
		if fast:
			# ★ 流線＝**垂直於行進方向壓扁**，不是沿行進方向拉長（B1.6.3 實看修正）。
			#
			#   前兩版都往「拉長」的方向做（先加拖尾、再加長本體），A/B 對照
			#   當場否決：第 5 波的間距是 0.6 格，**任何沿行進軸變長的東西都會
			#   碰到鄰居**——一列 11 隻分得開的敵人糊成一條連續的香腸，把
			#   「看不出差異」修成了「看不出有幾隻」。
			#
			#   壓扁則相反：footprint 只會變小，結構上不可能製造新的重疊，
			#   而「薄」在一排圓團與六邊形之間仍然是一眼分得出來的輪廓。
			var d := _enemy_dir(e)
			var perp := Vector2(-d.y, d.x)
			v -= perp * v.dot(perp) * 0.45
		pts.append(p + v)
	return pts


## 行進方向（單位向量）。路徑是正交的，所以這就是「下一格 − 這一格」。
func _enemy_dir(e: Dictionary) -> Vector2:
	var prog := float(e["progress"])
	var i := clampi(int(floor(prog)), 0, s.path.size() - 1)
	var j := mini(i + 1, s.path.size() - 1)
	if i == j:
		return Vector2.RIGHT
	return (Vector2(s.path[j] - s.path[i]) as Vector2).normalized()


func _enemy_pos(e: Dictionary) -> Vector2:
	var prog := float(e["progress"])
	var i := clampi(int(floor(prog)), 0, s.path.size() - 1)
	var j := mini(i + 1, s.path.size() - 1)
	# 格與格之間插值：模擬是離散的，呈現不必是（60Hz 插值，§2.4）。
	return _center(s.path[i]).lerp(_center(s.path[j]), prog - float(i))


## ★ 被選取那一座：射程圈 ＋ **正在餵它電的那幾台**（B3.6）。
##
## 三個記號各答一個問題，而且**形狀各不相同**（§4.3b：同一張圖上的兩個訊息，
## 換顏色不夠）：
##   · 選取本身 ＝ 那一格的**方框**（和擺放預覽的框同一個語彙）
##   · 射程 ＝ 一個**圓弧**
##   · 供電來源 ＝ 來源那一格的**菱形**，加上沿途導管的高亮
##
## 供電鏈逆著本 tick 的**實際流向**走（`FlowNetwork.upstream_power()`），
## 不是「有沒有連著」——一座塔可能連著五條線而這一刻只有兩條在餵它。
func _draw_selection() -> void:
	# ★ 選著一條導管（B3.7）：把它整條描出來。用**外框而不是換色**——導管自己的
	#   顏色正在講流量與滿載（§1.4a），塗掉它等於為了指出一條線而讓它不能讀。
	var wi := _sel_wire_index()
	if wi >= 0:
		var sc: Dictionary = s.conduits[wi]
		var a := _center(sc["a"])
		var b := _center(sc["b"])
		# ⚠ **外框要明確伸出管緣**，而管緣的位置隨流量走（2–8px）。
		#   第一版寫死 ±7px，於是選一條滿載的幹線時外框正好壓在它自己的邊上——
		#   截圖當場看不出哪一條被選中。`_draw_conduits()` 的刻度在 B1.6.1 踩過
		#   一模一樣的坑，那裡的解法是 `w * 0.5 + 3`，這裡照抄。
		var bonus := float(s.mods["cap_bonus"])
		var w := Shapes.conduit_width(
			float((s.rates["conduit_flow"] as Dictionary).get(sc["id"], 0.0)),
			Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus)
		)
		var n := (b - a).normalized().orthogonal() * (w * 0.5 + 4.0)
		var t := (b - a).normalized() * (w * 0.5 + 4.0)
		draw_polyline(PackedVector2Array([
			a + n - t, b + n + t, b - n + t, a - n - t, a + n - t,
		]), Palette.ORDER_BRIGHT, 2.0)
		return
	if _selected.x < 0:
		return
	var n: Dictionary = s.node_at(_selected)
	if n.is_empty():
		return
	var c := _center(_selected)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	draw_rect(Rect2(_world(_selected), g), Palette.ORDER_BRIGHT, false, 2.0)

	# ★ B3.8：圈要畫**升過的射程**。讀表上的原值會讓玩家看到一個和實際打得到
	#   的範圍不一樣的圈——而擺位正是他用這個圈在做的決定。
	var rng := Build.node_range(String(n["type"]), int(n.get("level", 0)))
	if rng > 0.0:
		# 半透明填色 ＋ 實線邊：只有邊的話，兩座塔的射程圈交疊時看不出誰罩到哪。
		draw_circle(c, rng * Shapes.GRID, Palette.alpha(Palette.ORDER_CYAN, 0.07))
		draw_arc(c, rng * Shapes.GRID, 0.0, TAU, 64, Palette.alpha(Palette.ORDER_BRIGHT, 0.7), 2.0)

	var chain := FlowNetwork.upstream_power(s.conduits, _energy_net(), _selected, _power_sources())
	var lit: Dictionary = chain["conduits"]
	for ci in s.conduits.size():
		var cd: Dictionary = s.conduits[ci]
		if not lit.has(cd["id"]):
			continue
		draw_line(_center(cd["a"]), _center(cd["b"]),
			Palette.alpha(Palette.ENERGY_AMBER, 0.55), 6.0)
	# 來源畫琥珀菱形（琥珀專屬能量，§1.1 配色紀律 2）——它答的是「電從哪來」。
	for cell: Variant in (chain["sources"] as Dictionary):
		var sc := _center(cell)
		draw_polyline(PackedVector2Array([
			sc + Vector2(0, -20), sc + Vector2(20, 0), sc + Vector2(0, 20),
			sc + Vector2(-20, 0), sc + Vector2(0, -20),
		]), Palette.ENERGY_AMBER, 2.5)


func _draw_hover() -> void:
	if not _in_map(_hover):
		return
	var p := _world(_hover)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	# ★ 游標壓在導管上時，**不畫落點預覽，改把那條線點亮**（B3.7）。
	#   一次點擊只能做一件事，而畫面得先說出它會做哪一件——B3.4 才剛把落點預覽
	#   做成「畫那隻角色本人」，若它在會被導管攔下的地方照樣現身，那是畫面在說謊。
	var hover_wire: int = -1
	if _mode == Mode.BUILD and _bp_index < 0 and _drag_from.x < 0:
		hover_wire = s.conduit_near(_hover_p, WIRE_PICK)
	if hover_wire >= 0:
		var hc: Dictionary = s.conduits[hover_wire]
		draw_line(_center(hc["a"]), _center(hc["b"]),
			Palette.alpha(Palette.ORDER_BRIGHT, 0.45), 8.0)
	elif _mode == Mode.BUILD and _build_type == "" and _bp_index < 0:
		# ★ B3.7.1：手上什麼都沒拿——**不畫落點預覽**。畫了就是承諾點下去會蓋東西，
		#   而這一刻不會。淡框仍然畫，游標在哪一格還是要看得見。
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	elif _mode == Mode.BUILD:
		var pv := BuildController.preview_place(s, _build_type, _hover)
		var col: Color = Palette.OK_GREEN if pv["ok"] else Palette.WARN_ORANGE
		draw_rect(Rect2(p, g), Palette.alpha(col, 0.18))
		draw_rect(Rect2(p, g), col, false, 2.0)
		# ★ **手上那一隻長什麼樣子，就畫什麼樣子**（B3.4）。
		#
		# 原本這裡只有上面那個框，於是玩家在做全遊戲最主要的那個決定
		# （這一格擺誰）的當下，看到的是一個和別種節點一模一樣的方框。
		# §1.6 花了整節在講「形狀要說得出這隻角色是什麼」——梯形是打進地裡的樁、
		# 三角是稜鏡、四角爆散星是濺射——而那些形狀在**最需要它們的那一刻**缺席。
		#
		# 走 `_draw_node_body()`（和真的節點同一支函式），不另外畫一份：
		# 抄一份的下場是加第十五種節點時只有一邊記得加，而漏掉的那一邊
		# 症狀是隱形不是報錯（B2.4 中過三次，`_no_glyph` 就是為此而生）。
		_draw_node_body({"type": _build_type}, _center(_hover))
		# 塔的射程要**在花錢之前**看得到——擺位是本作的主要決策，
		# 讓玩家蓋完才發現打不到路徑等於逼他拆（§3.5 塔的擺位）。
		var r := float(NodeDefs.of(_build_type).get("range", 0.0))
		if r > 0.0:
			draw_arc(
				_center(_hover), r * Shapes.GRID, 0.0, TAU, 64,
				Palette.alpha(col, 0.45), 1.5
			)
	else:
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	# ★ 藍圖（B2.3）。框選中畫橡皮筋框；手上有藍圖時畫它的落點。
	if _bp_from.x >= 0:
		var lo := Vector2i(mini(_bp_from.x, _hover.x), mini(_bp_from.y, _hover.y))
		var hi := Vector2i(maxi(_bp_from.x, _hover.x), maxi(_bp_from.y, _hover.y))
		var rect := Rect2(_world(lo), Vector2(hi - lo + Vector2i.ONE) * Shapes.GRID)
		draw_rect(rect, Palette.alpha(Palette.ORDER_CYAN, 0.12))
		draw_rect(rect, Palette.ORDER_CYAN, false, 2.0)
	elif _bp_index >= 0:
		var list := _blueprints()
		if _bp_index < list.size():
			# **每一格各自上色**：綠＝放得下、橘＝這一格擋住了。整份一個顏色
			# 只能說「不行」，指不出是哪一格——而那正是玩家的下一步要知道的事。
			var chk := BuildController.blueprint_check(s, list[_bp_index], _hover)
			var bad: Dictionary = {}
			for c: Vector2i in (chk["blocked"] as Array):
				bad[c] = true
			for c: Vector2i in Blueprint.cells_at(list[_bp_index], _hover):
				var col: Color = Palette.WARN_ORANGE if bad.has(c) else Palette.OK_GREEN
				draw_rect(Rect2(_world(c), g), Palette.alpha(col, 0.22))
				draw_rect(Rect2(_world(c), g), col, false, 2.0)
	var cf := _drag_from
	if cf.x >= 0:
		draw_rect(Rect2(_world(cf), g), Palette.ORDER_BRIGHT, false, 2.0)
		_draw_connect_guides(cf)
		# ★ 預覽線依**合法性**上色。B0.7.2 之前不管連不連得成都畫一條亮線，
		#   那是在畫一條不可能存在的導管——玩家只能點下去才知道不行。
		var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, _hover, s.conduit_cells()
	)
		var legal: bool = code == Build.OK and not s.node_at(_hover).is_empty()
		draw_line(
			_center(cf), _center(_hover),
			Palette.alpha(Palette.OK_GREEN if legal else Palette.WARN_ORANGE, 0.7), 2.0
		)


## ★ 連線的八條方向導引（`10_GDD.md` §3.2「導管只能走水平／垂直／45°」）。
##
## 使用者回報「沒有辦法 45 度放置管道」——規則其實是通的，**難的是用肉眼在
## 網格上找出正斜角**（要 |dx| 恰好等於 |dy|）。一條規則如果只能靠試錯才知道
## 自己有沒有踩中，那它在體感上就等於壞掉。把八條合法方向直接畫出來，
## 「45°」從一句文字變成畫面上看得到的四條斜線。
func _draw_connect_guides(anchor: Vector2i) -> void:
	var from := _center(anchor)
	var col := Palette.alpha(Palette.ORDER_DIM, 0.5)
	var size: Vector2i = s.map["size"]
	for d: Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]:
		var end := anchor
		while _in_map(end + d):
			end += d
		if end != anchor:
			draw_line(from, _center(end), col, 1.0)


## ★ 地圖座標（格 × 32px），**不是螢幕座標**——縮放與平移由 `_draw()` 開頭
## 那一個 `draw_set_transform` 統一處理（B1.2.2）。
func _world(c: Vector2i) -> Vector2:
	return Shapes.to_world(c)


func _center(c: Vector2i) -> Vector2:
	return _world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 地圖座標 → 螢幕座標。只有需要拿螢幕位置的地方才用（例：把浮層對到節點上）。
func _to_screen(p: Vector2) -> Vector2:
	return _map_origin() + p * _zoom


# ── 浮層 ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ★ 頂欄三階 ＋ 固定寬度（B2.4.4）。舊版是七個 15px（**階外**）的 Label 直接
	#   丟進 HBox——11 個數字同一階，而且寬度隨數值變。規格見 `TOP_CELLS`。
	_top = UiKit.hbox(8)
	_top.position = Vector2(120, 12)
	add_child(_top)
	_top_values.clear()
	_top_notes.clear()
	for spec: Dictionary in TOP_CELLS:
		var cell := UiKit.hbox(4)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		if String(spec["tag"]) != "":
			cell.add_child(UiKit.label(String(spec["tag"]), 13, Palette.TEXT_SECONDARY, false))
		var v := UiKit.label("", int(spec["vs"]), Palette.TEXT_PRIMARY, false)
		v.custom_minimum_size.x = float(spec["vw"])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		_top_values.append(v)
		var n := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		n.custom_minimum_size.x = float(spec["nw"])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(n)
		_top_notes.append(n)
		_top.add_child(cell)

	# ★ 選單（B1.4.1）。ESC 是快捷，**不是唯一的路**（P3：操作不得只靠鍵盤）。
	#   放左上角 x<120、y<56 那塊角落——頂欄從 x=120 起、建造欄從 y=56 起，
	#   全畫面只剩這裡是空的，而它也正好是選單的慣例位置。
	var menu_bar := UiKit.hbox(0)
	menu_bar.position = Vector2(8, 6)
	add_child(menu_bar)
	_menu_button = Button.new()
	_menu_button.text = "選單"
	_menu_button.custom_minimum_size.x = 104
	_menu_button.pressed.connect(_toggle_menu)
	menu_bar.add_child(UiKit.touchable(_menu_button))

	# ★ 縮放（B1.2.2）。放在頂欄右端那片空白——建造欄與底欄都已經滿了，
	#   而地圖右上角是縮放控制的慣例位置。**三顆鈕都是可點的**：滾輪只是
	#   桌面的便利，手機移植預留條款 P3 不許任何操作只有滾輪／右鍵一條路。
	var zoom_bar := UiKit.hbox(6)
	zoom_bar.position = Vector2(1072, 6)
	add_child(zoom_bar)
	for pair: Array in [["−", 1.0 / ZOOM_STEP], ["＋", ZOOM_STEP]]:
		var zb := Button.new()
		zb.text = String(pair[0])
		zb.pressed.connect(_on_zoom.bind(float(pair[1])))
		zoom_bar.add_child(UiKit.touchable(zb))
	_zoom_button = Button.new()
	# 倍率印在「全景」鈕上，不另給一個標籤——底欄與建造欄都沒有空位了，
	# 而「現在幾倍」與「回到全景」本來就是同一件事的兩面。
	_zoom_button.pressed.connect(_on_zoom_reset)
	zoom_bar.add_child(UiKit.touchable(_zoom_button))
	_refresh_zoom()

	# 間距 2 而不是 4：B1.1 起建造欄有 10 種節點＋3 個模式鈕，44px 的觸控高度
	# （手機移植前提，不能縮）乘 13 已經吃掉 572px，只剩間距可以讓。
	#
	# ★ B2.4.2：那句話在 B2.4 加了三隻角色之後**就不夠了**——13 種把「加粗／拆除」
	#   推到和底欄疊在一起，「藍圖」整顆掉出畫面（RG-139），而**全收集的玩家打無盡
	#   就是 13 種**。所以建造清單改裝進捲動容器，模式鈕釘在它下面。
	#
	#   為什麼是捲動而不是「壓矮一點」或「排兩欄」：44px 是手機移植的硬底線
	#   （P2，不能縮），兩欄在 112px 欄寬裡塞不下「回收者」三個字。而真正的理由是
	#   **這條清單還要再長一倍**——`10_GDD.md` §5 的 M3 內容矩陣是 24 隻角色，
	#   加 5 種生產節點就是 29 顆鈕。任何「剛好排得下」的方案都只是把同一個 bug
	#   往後推一批。
	var col := UiKit.vbox(2)
	col.position = Vector2(8, 56)
	# 112 ＝ 剛好貼到地圖原點 x=120（`ORIGIN`）而不蓋住它。
	# 最長的一顆是「碎浪 140+60合」。
	col.custom_minimum_size = Vector2(112, 0)
	add_child(col)

	# ★ 全部 11 個鈕共用一個 `ButtonGroup`：任一時刻**恰好一個**是按下狀態，
	#   而那正好就是這個 UI 的真相（選了建造類型就是離開連線模式）。
	#   用 Godot 內建的 toggle 群組，不自己維護一套「哪個被選中」的高亮。
	#   B0.6 之前完全沒有選中指示——玩家只能從提示列的文字推自己在哪個模式。
	var group := ButtonGroup.new()
	# ★ B3.7.1：允許「按一下選、再按一下取消」（使用者指定）。`ButtonGroup` 預設
	#   永遠有一顆是按下的——那對模式是對的（總得在某個模式裡），對「手上拿著誰」
	#   不對：玩家常常只是想看一下地圖，而不是隨時都握著一種節點。
	group.allow_unpress = true
	# ★ 只列**這一關解鎖的**（`10_GDD.md` §7.9）。第 1 關給四顆鈕不是十顆——
	#   十顆對一個還不知道「電是流率」的人來說不是自由，是雜訊。
	#   一局之內這份清單不會變，所以鈕的位置仍然是固定的（R-15 的同一條理由）。
	_build_scroll = ScrollContainer.new()
	_build_scroll.custom_minimum_size = Vector2(112, BUILD_LIST_H)
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_build_scroll)
	var list := UiKit.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_scroll.add_child(list)

	# ★ 生產／防線分段（B2.4.2）。**兩段不是排版，是這一欄的整句話**——
	#   優先權面板為了同一件事特地做了雙欄（`NodeDefs.PRIORITY_SPLIT`），
	#   而建造欄是玩家做**同一個決定**的地方（這 40 礦砂餵產線還是餵防線）。
	#   分段同時讓捲動清單找得到東西：29 顆一模一樣的鈕捲起來是找不到路的。
	# ★ **自己排序，不假設 `_buildable()` 已經是生產在前**（B2.4.2 code review 抓到）。
	#   那份清單是各關在 `data/Campaign.gd` 手寫的，目前碰巧都是生產在前——
	#   而「碰巧」不是不變量。有一關把塔寫在採集器前面時，那顆採集器會安靜地
	#   歸到「防線」那一段，畫面看起來完全正常。
	var ordered: Array[String] = []
	for pass_towers: bool in [false, true]:
		for type: String in _buildable():
			if bool(NodeDefs.of(type).get("tower", false)) == pass_towers:
				ordered.append(type)
	var seen_tower := false
	for type: String in ordered:
		var is_tower: bool = bool(NodeDefs.of(type).get("tower", false))
		if not seen_tower and is_tower:
			seen_tower = true
			list.add_child(_section_label("防線"))
		elif not seen_tower and list.get_child_count() == 0:
			list.add_child(_section_label("生產"))
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		# 鈕上**只有名字**（使用者指定，B1.3.1）：價牌在提示列的第一行，
		# 而滑鼠移到鈕上時圖鑑浮層也會寫一次。同一個數字印三遍只是把鈕撐長。
		var b := _tool_button(group, NodeDefs.label(type))
		# ★ B3.7.1：接 `toggled` 不是 `pressed`（使用者指定「再按一下就是取消選擇」）。
		#   `pressed` 收不到「這一顆剛被放開」——那正是取消選擇要聽的事件。
		b.toggled.connect(_on_build_type.bind(type))
		# ★ 角色簡介：滑鼠停在鈕上就浮出來，移開就消失（可用底欄「圖鑑」關掉）。
		b.mouse_entered.connect(_on_codex_show.bind(type, b))
		b.mouse_exited.connect(_on_codex_hide)
		_build_buttons[type] = b
		list.add_child(UiKit.touchable(b))
	# ★ B3.7.1：`_build_type` 可以是空字串（手上什麼都沒拿），而空字串沒有對應的鈕。
	#   索引不到會丟執行期錯誤 → **中止整支 `_build_ui()`**，症狀是「半個畫面沒建出來」
	#   而不是報錯（RG-164 的形狀）。
	if _build_buttons.has(_build_type):
		(_build_buttons[_build_type] as Button).button_pressed = true

	col.add_child(_spacer(4))
	# ★ 動作鈕只剩一顆（B3.7.1，使用者指定）。歷次拿掉的理由是同一條：
	#   **一個模式鈕如果只是「同一件事的比較慢的做法」，它就該消失。**
	#   「連線」B1.6.2 被拖曳取代；「移動」B1.3.1 改中鍵拖；
	#   「升級」「拆除」B3.7 被檢視面板上的鈕取代——切模式 → 點目標 → 切回建造，
	#   三步裡有兩步不是決定。
	#   藍圖留著：它不是動詞，是**手上拿著的東西**，沒有別的地方表達得了。
	var bp_btn_mode := _tool_button(group, "藍圖")
	bp_btn_mode.toggled.connect(_on_mode.bind(Mode.BLUEPRINT))
	_mode_buttons[Mode.BLUEPRINT] = bp_btn_mode
	col.add_child(UiKit.touchable(bp_btn_mode))

	# 建造欄放不下八種節點再加動作鈕（8×44 已經吃掉 380px），
	# 所以時間流與面板開關搬到地圖下緣那條 56px 的空帶——那裡本來就空著。
	# ★ 三群（B2.4.4，§7.2 B-5）：**時間流｜浮層開關｜說明**。
	#   群間 24、群內 8（§1.3 間距階），**不加分隔線**——七顆同權重的鈕裡有一顆
	#   是不可逆的，而視覺重量要對應後果的重量。
	var bar := UiKit.hbox(24)
	bar.position = Vector2(8, BAR_Y)
	add_child(bar)
	var g_time := UiKit.hbox(8)
	var g_panels := UiKit.hbox(8)
	var g_help := UiKit.hbox(8)
	bar.add_child(g_time)
	bar.add_child(g_panels)
	bar.add_child(g_help)
	_ff_button = Button.new()
	_ff_button.text = "快進 4×"
	_ff_button.pressed.connect(_on_fast_forward)
	g_time.add_child(UiKit.touchable(_ff_button))
	_summon_button = Button.new()
	_summon_button.pressed.connect(_on_summon_now)
	# ★ **全底欄唯一一顆不可逆的鈕**：按下去這一波就提早來，獎勵倍率也定了。
	#   §7.2 B-5 原本開的處方是 `energy.amber` 描邊——**那違反 §1.1 配色紀律 2**
	#   （琥珀專屬於能量，而提前召喚跟耗能無關）。改用 `warn.orange`：紀律 1 說
	#   橙／品紅專屬於「敵人與危險狀態」，而這顆鈕做的事**就是把敵潮叫過來**，
	#   它是玩家自己選的危險。同一條紀律，剛好也是更強的編碼。
	_summon_button.add_theme_color_override("font_color", Palette.WARN_ORANGE)
	_summon_button.add_theme_color_override("font_hover_color", Palette.WARN_ORANGE)
	g_time.add_child(UiKit.touchable(_summon_button))
	# 抽屜開關本來就是一個開關：做成 toggle，按下狀態才**真的**等於「抽屜開著」。
	# 之前是普通按鈕，它拿到焦點時的外框看起來就像被選中，玩家會以為抽屜開了。
	var prio := Button.new()
	prio.text = "優先權"  # 底欄六個鈕，字都壓到最短——提示列要留得下兩行字

	prio.toggle_mode = true
	prio.toggled.connect(_on_toggle_priority)
	g_panels.add_child(UiKit.touchable(prio))
	# ★ 藍圖庫（B2.3）。放底欄抽屜而不是左欄：左欄的八種節點加動作鈕已經
	#   吃掉 380px，而藍圖是**每局用一兩次**的東西，不該和每秒都在點的建造欄搶位置。
	var bp_btn := Button.new()
	bp_btn.text = "藍圖"
	bp_btn.toggle_mode = true
	bp_btn.toggled.connect(_on_toggle_blueprint)
	g_panels.add_child(UiKit.touchable(bp_btn))
	_help_button = Button.new()
	_help_button.text = "說明"
	_help_button.toggle_mode = true
	_help_button.toggled.connect(_on_toggle_help)

	_energy_button = Button.new()
	_energy_button.text = "能量"
	_energy_button.toggle_mode = true
	_energy_button.toggled.connect(_on_toggle_energy)
	g_panels.add_child(UiKit.touchable(_energy_button))
	_codex_button = Button.new()
	_codex_button.text = "圖鑑"
	_codex_button.toggle_mode = true
	_codex_button.button_pressed = true   # 預設開：它只在滑鼠停在建造鈕上時才出現
	_codex_button.toggled.connect(func(on: bool) -> void: _codex_on = on)
	g_panels.add_child(UiKit.touchable(_codex_button))
	# 說明自己一群：它是唯一一顆**跟局面無關**的鈕（不改狀態、不開資料浮層）。
	g_help.add_child(UiKit.touchable(_help_button))

	_build_priority_panel()
	_build_blueprint_panel()
	_build_energy_panel()
	_build_codex_panel()
	_build_inspect_panel()
	_build_help_panel()

	# 兩行：上行「下一步」、下行當下動作的細節。
	#
	# ★ x **跟著底欄實際的右緣走**，不是一個寫死的 520（B2.9）。原本是寫死的，
	#   而 B2.9 給按鈕套上美術 token（`content_margin` 12/8）之後每一顆鈕都變寬了
	#   ——七顆鈕加起來超過 520，提示文字當場被壓在「說明」那顆鈕上面。
	#   寫死的座標就是這樣壞的：它記的是**當時**那七顆鈕有多寬。
	#   （這也是手機預留條款 P1「不硬編碼像素位置」在這一行的兌現。）
	_hint = UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
	_hint.position = Vector2(520, 666)
	_hint.size = Vector2(755, 50)
	add_child(_hint)
	bar.resized.connect(_place_hint.bind(bar))
	_place_hint.call_deferred(bar)
	_refresh_hint()


## 提示文字擺在底欄右邊 24px（§1.3 間距階的群間距，同底欄自己的三群）。
## 底欄是容器，它的寬度要到版面跑完才知道——所以走 `resized` 而不是算一次。
func _place_hint(bar: Control) -> void:
	if _hint == null or not is_instance_valid(bar):
		return
	_hint.position.x = bar.position.x + bar.size.x + 24.0
	_hint.size.x = maxf(120.0, float(size.x) - _hint.position.x - 8.0)


## ★ 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作
##      必須是一個手勢；滑桿會跑位就不是手勢了。
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）。
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2 全畫面地圖 ＋ 可收合浮層）。
## ★ 藍圖抽屜（B2.3）。位置在畫面左中——優先權面板在 (128, 380)、
## 能量面板在右上、提示列在底邊，這一塊是剩下唯一放得下一張清單的地方。
func _build_blueprint_panel() -> void:
	var box := UiKit.panel()
	# 位置是**擠出來的**，不是挑出來的：優先權面板佔 128..510、能量面板佔
	# 872..1264、圖鑑浮層下緣到 320、提示列從 660 起——中間這一塊是唯一
	# 能讓三張浮層同時開又互不相疊的地方。
	# 第一版放 (128, 150)，於是被圖鑑整個蓋住（截圖抓到，文字從圖鑑後面透出來）。
	box.position = Vector2(560, 400)
	box.visible = false
	box.add_child(UiKit.vbox(4))
	add_child(box)
	_bp_panel = box
	_refresh_blueprints()


func _build_priority_panel() -> void:
	var box := UiKit.panel()
	# B1.1 起 9 列：單欄 × 44px 觸控高度（手機移植前提，不能縮）放不進一屏，
	# 改**雙欄**——左生產、右防線（`NodeDefs.PRIORITY_SPLIT`），而那個分界
	# 正好就是這個面板在問的問題。
	#
	# 位置搬到畫面左下：能量面板佔右上（872..1264 × 96..416）、提示列佔
	# x ≥ 520 的底邊、底欄鈕佔 y ≥ 668——這一塊是唯一能讓兩張表同時開又
	# 互不相疊的地方。舊的 (1000, 330) 其實早就和能量面板疊了 66px。
	box.position = Vector2(128, 380)
	box.visible = false
	var outer := UiKit.vbox(4)
	box.add_child(outer)
	outer.add_child(UiKit.label("能量／礦砂不足時，誰先餓死", 13, Palette.TEXT_SECONDARY, false))
	var cols := UiKit.hbox(10)
	outer.add_child(cols)
	var lanes := [UiKit.vbox(4), UiKit.vbox(4)]
	cols.add_child(lanes[0])
	cols.add_child(lanes[1])
	# ★ 只列這一關蓋得出來的（核心永遠在，它不是玩家蓋的）。B1.2 起前幾關
	#   只解鎖四到六種節點，把另外五條永遠用不到的滑桿也列出來，就是把
	#   「這一格是我的戰術決定」稀釋成「這一排我看不懂」。**一局之內清單不變**，
	#   所以滑桿仍然恆在同一位置（R-1／R-15 要保的是那一件事）。
	# ★ 一列＝一個**角色的角色**，不是一個資料表的鍵（`NodeDefs.PRIORITY_GROUP`，
	#   B2.4）。長哨與定潮併進「錨」那一列、霜礁併進「潮鳴」那一列，所以滑桿數
	#   永遠是這九條的子集——M3 的 24 隻角色也不會讓這個面板長成一份表單（R-1）。
	var rows: Array = []
	for type: String in NodeDefs.PRIORITY_ROWS:
		if type == "core":
			rows.append(type)
			continue
		for member: String in NodeDefs.priority_members(type):
			if _buildable().has(member):
				rows.append(type)
				break
	var split := 0
	for type: String in rows:
		if NodeDefs.PRIORITY_ROWS.find(type) < NodeDefs.PRIORITY_SPLIT:
			split += 1
	for i in rows.size():
		var type := String(rows[i])
		var row := UiKit.hbox(4)
		var name_label := UiKit.label(NodeDefs.label(type), 13, Palette.TEXT_PRIMARY, false)
		name_label.custom_minimum_size = Vector2(52, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var down := Button.new()
		down.text = "◀"
		down.pressed.connect(_on_priority.bind(type, -1))
		row.add_child(UiKit.touchable(down))
		var value := UiKit.label("", 16, Palette.ENERGY_AMBER)
		value.custom_minimum_size = Vector2(24, 0)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		_prio_labels[type] = value
		var up := Button.new()
		up.text = "▶"
		up.pressed.connect(_on_priority.bind(type, 1))
		row.add_child(UiKit.touchable(up))
		(lanes[0] if i < split else lanes[1]).add_child(row)
	add_child(box)
	_prio_panel = box
	_refresh_priority()


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
	var n: int = (s.sets["crossings"] as Dictionary).size()
	if n <= 0:
		return "　導管不能跨過敵人路徑（紫帶）。這張圖沒有橋，所有東西都在同一側"
	return "　導管要過敵人路徑（紫帶）只能走「橋」，也就是路徑上那 %d 段架高結構" % n


func _build_help_panel() -> void:
	var box := UiKit.panel(0.94)
	box.position = Vector2(150, 250)
	var col := UiKit.vbox(3)
	box.add_child(col)
	for line: String in [
		"操作　左鍵做事、中鍵移動視野、滾輪縮放、ESC 開選單。沒有右鍵",
		"　蓋節點：左欄選一種 → 左鍵點地圖上的一格",
		"　拉導管：從一個節點按住左鍵，拖到另一個節點放開（隨時都能拖，不用切模式）",
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
		"　塔只有交戰時吃電，待機 0：約束是「峰值電力」，不是平均",
		"",
		"底欄　快進 4×（只有準備期）｜提前召喚（提早開波換掉落倍率）｜優先權（缺料時誰先餓死）",
	]:
		if line == "":
			col.add_child(_spacer(6))
			continue
		var head := not line.begins_with("　")
		col.add_child(UiKit.label(
			line, 15 if head else 14,
			Palette.ORDER_BRIGHT if head else Palette.TEXT_PRIMARY, false
		))
	# （不吃滑鼠由 `UiKit.panel()` 保證——這一張曾經預設開在玩家要放第一個
	#   節點的位置上並把那片點擊整片吞掉，等於教學把遊戲擋住了。RG-39）
	add_child(box)
	_help_panel = box
	# ★ **預設不開**（B2.4.7，使用者指定）。原本空地圖時自動彈出，理由是
	#   「這局還沒開始，正是需要它的時刻」——但它整片是文字，蓋在地圖上，
	#   而每一局開頭都會再來一次。提示列（`_hint`）本來就在講下一步，
	#   說明鈕也一直在底欄。**要看的人按得到，不要看的人不必關掉它。**
	box.visible = false
	_help_button.set_pressed_no_signal(false)


func _on_toggle_help(open: bool) -> void:
	_help_panel.visible = open


## ★ 能量收支面板（使用者要求：「不太清楚怎樣的操作可以讓能量增加、哪些會減少」）。
##
## 頂欄的能量條說的是**結果**（供給 30／需求 37），它不說「這 37 是誰吃的」。
## 這張表把每一項逐條攤開並**即時跟著跑**，所以它同時是答案與教材：
## 玩家蓋一台發電機，`+` 那一欄當場多 20——因果在同一個畫面上發生。
##
## 只列**這一局真的存在**的項目：一張永遠有八行的表沒有資訊量，
## 有幾行會動、什麼時候動，本身就是資訊。
func _build_energy_panel() -> void:
	var box := UiKit.panel()
	box.position = Vector2(872, 96)
	box.visible = false
	# ★ **固定尺寸、固定列數**（B0.7.4）。使用者回報「面板會因為一些小改動
	#   一直跳動，很難看清楚」——原因是沒有數值的列會自己隱藏，`PanelContainer`
	#   跟著縮放，於是每過一個 tick 版面就位移一次。
	#   **一張一直在動的表，讀不了**。現在列數恆定、寬度恆定，
	#   不存在的項目留在原位變暗——**位置固定本身就是可讀性**。
	# 320 ＝ 標題 ＋ 14 列 ×（17 ＋ 3）＋ 邊距。B1.1 多了「熔爐」一列。
	box.custom_minimum_size = Vector2(392, 320)
	var col := UiKit.vbox(3)
	box.add_child(col)
	col.add_child(UiKit.label("能量收支（每秒）", 16, Palette.ENERGY_AMBER, false))
	for key: String in ENERGY_ROWS:
		var l := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		l.custom_minimum_size = Vector2(380, 17)
		col.add_child(l)
		_energy_rows[key] = l
	add_child(box)
	_energy_panel = box


func _on_toggle_energy(open: bool) -> void:
	_energy_panel.visible = open


func _refresh_energy() -> void:
	if _energy_panel == null or not _energy_panel.visible:
		return
	var r: Dictionary = s.rates
	var gen := 0.0
	var reclaim := 0.0
	var tower := 0.0
	# 熔爐的耗能**不能併進任何一列既有的**：它既不是交戰耗能（待機也吃），
	# 也不是儲槽充能。B1.1 之前 `silo_in = demand − tower` 會把熔爐那 10/秒
	# 記到儲槽頭上——面板從此開始說謊。
	var smelt := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		gen += float(def.get("power_out", 0.0)) * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		if def.has("reclaim"):
			reclaim += float(n["buffer"])
		smelt += float(def.get("power_in", 0.0))
		if _engaged.get(int(n["id"]), false):
			tower += float(def.get("engage_power", 0.0))
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var silo_out := maxf(0.0, supply - gen)
	var silo_in := maxf(0.0, demand - tower - smelt)
	var net := supply - demand

	_set_row("gen", "＋ 發電機 ×%d　%+.0f" % [s.count_of("generator"), gen],
		gen > 0.05, Palette.ENERGY_AMBER)
	_set_row("silo_out", "＋ 儲槽放電　%+.0f" % silo_out, silo_out > 0.05, Palette.ENERGY_AMBER)
	_set_row("reclaim", "＋ 回收者存量　%.0f（擊殺換來的，限速注入）" % reclaim,
		reclaim > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep1", "─────────────────", false)
	_set_row("tower", "− 塔（交戰 %d 座）　%.0f" % [int(r["engaged"]), tower], tower > 0.05)
	_set_row("smelt", "− 熔爐 ×%d　%.0f（待機也吃）" % [s.count_of("smelter"), smelt],
		smelt > 0.05)
	_set_row("silo_in", "− 儲槽充能　%.0f（受自己那條線限速）" % silo_in, silo_in > 0.05)
	# ★ 儲槽**存量**（B2.4.4）。它原本掛在頂欄，而頂欄的三階層次容不下 11 個
	#   數字（§2 反模式：每畫面最多 4 個主要數字）。搬到這裡而不是刪掉：
	#   這一格是「充放電」那兩列的分母，放在它們旁邊比放在頂欄更講得通。
	#   ★ **每一顆儲槽自己身上還有一圈琥珀弧**，所以「哪一顆滿了」在地圖上讀得到，
	#     頂欄少的只是那個總和數字。
	_set_row("silo_store", "　　儲槽存量　%.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]],
		float(r["silo_capacity"]) > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep2", "─────────────────", false)

	# ★ 「誰餵不飽」（使用者要求）。淨值只說「差多少」，不說「誰在挨餓」——
	#   而玩家能採取的動作（拉優先權、加粗那條線、多蓋一台發電機）取決於後者。
	#   名單直接取三態徽章的 `STARVED`，與地圖上的橙色倒三角是同一份判定。
	var short_list: Array[String] = []
	var states: Dictionary = r["node_state"]
	for n: Dictionary in s.nodes:
		# ★ `is_starved()` 而不是 `== STARVED`（B2.4.8）：缺料分成礦／電兩態之後，
		#   寫死等號的地方會安靜地漏掉一半的節點——而「安靜地漏掉」正是這一整批
		#   在修的東西。
		if not SessionState.is_starved(int(states.get(int(n["id"]), 0))):
			continue
		short_list.append("%s%s %.0f%%" % [
			NodeDefs.label(String(n["type"])), n["cell"],
			100.0 * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		])

	var ok_all := short_list.is_empty()
	_set_row("net", "淨值　%+.0f/秒　%s" % [net, "餵得飽" if ok_all else "有東西在挨餓"], true,
		Palette.OK_GREEN if ok_all else Palette.WARN_ORANGE)
	for i in SHORT_ROWS:
		var key := "short%d" % i
		if ok_all:
			_set_row(key, "　全部餵得飽" if i == 0 else "", false)
		elif i == SHORT_ROWS - 1 and short_list.size() > SHORT_ROWS:
			_set_row(key, "　…還有 %d 座" % (short_list.size() - SHORT_ROWS + 1), true,
				Palette.WARN_ORANGE)
		elif i < short_list.size():
			_set_row(key, "　餵不飽：" + short_list[i] if i == 0 else "　　　　　" + short_list[i],
				true, Palette.WARN_ORANGE)
		else:
			_set_row(key, "", false)

	_set_row("tip", "加電：多蓋發電機（每台吃 4 礦砂/秒）", false)
	_set_row("tip2", "省電：塔少一點，或用「優先權」決定誰先餓", false)


## `live` ＝ 這一項現在有沒有在作用。**沒作用的列不隱藏、只變暗**——
## 隱藏會讓下面每一列往上跳，而一張一直在動的表讀不了（B0.7.4）。
func _set_row(key: String, text: String, live: bool, col: Color = Palette.TEXT_SECONDARY) -> void:
	var l: Label = _energy_rows[key]
	l.text = text
	l.add_theme_color_override("font_color", col if live else Palette.TEXT_DISABLED)


## ★ 角色簡介浮層（使用者要求）。滑鼠停在左欄的建造鈕上就浮出來、移開就收，
## 底欄「圖鑑」可整個關掉。**半透明**：它蓋在地圖上，要讓人看得見底下是什麼。
##
## 內容一律**從 `data/NodeDefs.gd` 現算**，不另外寫一份文案表——
## 兩份會漂移，而漂移的那一份剛好就是玩家讀到的那一份。
func _build_codex_panel() -> void:
	# 角色簡介刻意半透明：它浮在地圖上，要讓人看得見底下是什麼（使用者指定）。
	var box := UiKit.panel(0.88)
	box.visible = false
	_codex_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 不設寬度的話它會長到最長那一行那麼寬（熔爐那一行 850px），
	#   從 x=124 一路蓋掉 x=870 的能量面板——兩個浮層同時開就疊在一起。
	_codex_label.custom_minimum_size.x = 640.0
	_codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_codex_label)
	add_child(box)
	_codex_panel = box


## 自檢逾時就以失敗收場，不要把視窗留在使用者桌面上（見 `_click_selftest()`）。
## 60 秒遠寬於任何一支自檢的實際長度（最慢的約 3 秒）。
func _watchdog() -> void:
	var timer := get_tree().create_timer(60.0)
	timer.timeout.connect(func() -> void:
		push_error("[TL_CLICKTEST] 自檢逾時。多半是某一步丟了執行期錯誤而中止")
		get_tree().quit(1)
	)


## ★ B3.7：面板底下多兩顆鈕（升級／加粗、拆除）。
##
## 動詞跟著**被選中的那個東西**走，不再跟著模式走。原本要動一座塔得先去底欄按
## 「升級」、點它、再按回來——三步裡有兩步不是決定。現在點它就看得到它，
## 而它能做的兩件事就寫在旁邊。
##
## ⚠ `UiKit.panel()` 是 `MOUSE_FILTER_IGNORE`（RG-39：浮層是資訊不是障礙物），
##   但那只管容器自己——Godot 的命中測試照樣會走進子節點，所以鈕收得到點擊，
##   而鈕以外的地方仍然穿透到底下的地圖。
## 檢視面板的固定寬高（B3.9.1）。**位置只能是離散狀態的函式**——見 `_place_inspect`。
## `INSPECT_MAX_H` 是它最高的樣子（導管面板量到 342），只拿來判避讓。
const INSPECT_W := 383.0
const INSPECT_MAX_H := 360.0


func _build_inspect_panel() -> void:
	# ★ B3.7 起用標準不透明度（0.96），不再是角色簡介那種半透明。
	# 半透明的理由是「讓玩家看見底下是什麼」，而這個面板底下不是它要講的東西
	# ——被選取的那一格與供電來源都在畫面另一邊。加了兩顆鈕之後代價更明顯：
	# 節點圖形從字和鈕後面透出來，而**可以按的東西要讀起來是實心的**。
	var box := UiKit.panel()
	box.visible = false
	var col := UiKit.vbox(8)
	# ⚠ **內層容器要一起穿透**。`UiKit.panel()` 自己是 `MOUSE_FILTER_IGNORE`
	#   （RG-39：浮層是資訊不是障礙物），但 `Container` 預設是 `STOP`——面板底下
	#   那一塊地圖於是點不到也拖不動。B3.9.1 把面板挪到畫面中段之後這件事才要緊。
	#   兩顆鈕仍是 `STOP`（它們就是要點的東西）。
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 356 ＝ 量到的最長一行。**不開 autowrap**：這些行是設計成單行的，折行會讓
	#   面板從 258 長到 552，一個蓋住半張地圖的浮層比它要修的位移更糟。
	_inspect_label.custom_minimum_size.x = 356.0
	col.add_child(_inspect_label)
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_up = Button.new()
	_inspect_up.pressed.connect(_on_inspect_upgrade)
	_inspect_del = Button.new()
	_inspect_del.pressed.connect(_on_inspect_demolish)
	for b: Button in [_inspect_up, _inspect_del]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UiKit.touchable(b))
	col.add_child(row)
	box.add_child(col)
	add_child(box)
	_inspect_panel = box


## 被選取那條導管在 `s.conduits` 裡的索引。找不到（被拆了、被敵人啃斷了）回 −1。
##
## 每次都重找而不是記索引——理由寫在 `_sel_wire` 的宣告上。線性掃：一局的導管
## 是幾十條，而這只在玩家選著一條線的那些幀跑。
func _sel_wire_index() -> int:
	if _sel_wire < 0:
		return -1
	for i in s.conduits.size():
		if int((s.conduits[i])["id"]) == _sel_wire:
			return i
	return -1


## 選一條導管。再點同一條＝取消（和選節點同一個開關語意）。
func _select_wire(id: int) -> void:
	_selected = Vector2i(-1, -1)
	_sel_wire = -1 if _sel_wire == id else id
	_message = ""
	_refresh_inspect()


func _on_inspect_upgrade() -> void:
	var wi := _sel_wire_index()
	if wi >= 0:
		var code := BuildController.upgrade(s, wi)
		if code == Build.OK:
			AudioBus.play("build_wire")
		_message = _text_of(code)
	elif _selected.x >= 0:
		var code := BuildController.upgrade_node(s, _selected)
		if code == Build.OK:
			AudioBus.play("build_place")
		_message = _text_of(code)
	_refresh_inspect()
	_refresh_hint()
	queue_redraw()


func _on_inspect_demolish() -> void:
	var wi := _sel_wire_index()
	var code := ""
	if wi >= 0:
		code = BuildController.demolish_conduit(s, wi)
	elif _selected.x >= 0:
		code = BuildController.demolish(s, _selected)
	else:
		return
	if code == Build.OK:
		AudioBus.play("build_destroyed", -4.0)
		# 拆掉的東西不能繼續選著：面板下一幀就沒有東西可講了。
		_selected = Vector2i(-1, -1)
		_sel_wire = -1
	_message = _text_of(code)
	_refresh_inspect()
	_refresh_hint()
	queue_redraw()


## ★ 被選取那一座的**當下數據**（B3.6）。每幀重算——它講的是這個 tick。
##
## 三件事，照玩家問的順序：**這是什麼 → 它現在吃多少電 → 電從哪來。**
## 前兩件是它自己的欄位，第三件要逆著本 tick 的實際流向走（`FlowNetwork.upstream_power()`）。
func _refresh_inspect() -> void:
	if _inspect_panel == null:
		return
	if Hooks.naked:
		_inspect_panel.visible = false
		return
	# 選著的那條線可能已經不在了（自己拆的、或敵人啃斷的）。**在這裡收掉**，
	# 而不是等某個讀 `s.conduits[i]` 的地方越界——那個症狀是整支函式中止（RG-164）。
	var wi := _sel_wire_index()
	if _sel_wire >= 0 and wi < 0:
		_sel_wire = -1
	if wi >= 0:
		_refresh_inspect_wire(wi)
		return
	var n: Dictionary = s.node_at(_selected) if _selected.x >= 0 else {}
	if n.is_empty():
		_inspect_panel.visible = false
		return
	var type := String(n["type"])
	var def := NodeDefs.of(type)
	var lvl := int(n.get("level", 0))
	var scale := Build.node_scale(lvl)
	var lines: Array[String] = []
	lines.append("%s%s" % [NodeDefs.label(type), "　%d 級" % lvl if lvl > 0 else ""])
	lines.append("生命　%d / %d" % [int(n["hp"]), int(NodeDefs.hp(type))])

	# ── 它自己的數據（升級之後要顯示**升過的值**，不是表上的原值）──
	# ★ B3.8：升的是哪一項各問各的（`10_GDD.md` §4.3）。這裡**不能用 `scale`**
	#   ——那是耗能倍率；一座第 2 級加射速的錨，傷害還停在 1 級的值。
	var eff := Build.effect_scale(type, lvl)
	var rng := Build.node_range(type, lvl)
	if rng > 0.0:
		lines.append("射程　%.0f 格" % rng)
	if float(def.get("dmg", 0.0)) > 0.0:
		lines.append("傷害　%.0f × %.1f 發/秒" % [
			float(def["dmg"]) * eff * float(s.mods["damage_mult"]),
			float(def.get("rof", 0.0)) * Build.rof_scale(type, lvl),
		])
	if float(def.get("slow", 0.0)) > 0.0:
		# 光環塔的**全部效果**都在這一行。B3.5 起它一直沒有被級數乘過，而面板
		# 也從來沒有印出來——使用者實玩才發現「潮鳴跟霜礁升級都沒用」（B3.8）。
		lines.append("減速　%d%%%s" % [
			int(round(minf(float(def["slow"]) * eff, Combat.SLOW_MAX) * 100.0)),
			"　破甲 %d%%" % int(round(float(def["armor_break"]) * eff * 100.0))
				if float(def.get("armor_break", 0.0)) > 0.0 else "",
		])
	if Build.splash_radius(type, lvl) > 0.0:
		lines.append("濺射　%.1f 格" % Build.splash_radius(type, lvl))
	if float(def.get("reclaim", 0.0)) > 0.0:
		lines.append("回收　射程內任何死亡的 %d%% 換能量" % int(round(
			float(def["reclaim"]) * eff * 100.0
		)))
	if float(def.get("ore_out", 0.0)) > 0.0:
		lines.append("產出　%.1f 礦砂/秒" % (float(def["ore_out"]) * eff
			* float(s.mods["produce_mult"])))
	if float(def.get("power_out", 0.0)) > 0.0:
		lines.append("發電　%.0f 能量/秒" % (float(def["power_out"]) * eff
			* float(s.mods["produce_mult"])))

	# ── 耗能：**帳面**與**當下**分開講 ──
	# 帳面是「它交戰時會吃多少」，當下是「這個 tick 它真的拿到多少」。
	# 只講一個的話，玩家看不出「它在挨餓」——而那正是他點開這座塔的原因。
	var engage := float(def.get("engage_power", 0.0)) * scale * float(s.mods["engage_mult"])
	var idle := float(def.get("power_in", 0.0)) * scale
	if engage > 0.0 or idle > 0.0:
		# ⚠ **預設值不能是 1.0**。沒接進電網的節點根本不在解算器的表上，
		#   `.get(id, 1.0)` 會把「查無此人」讀成「餵得飽飽的」——
		#   截圖當場抓到面板自相矛盾：上一行寫「餵得 100%」，下一行寫「供電 沒有」。
		#   用 −1 當哨兵，把「沒在表上」和「在表上而且滿足率是 1」分開。
		var sat_raw := float((s.rates["satisfaction"] as Dictionary).get(int(n["id"]), -1.0))
		var wired: bool = sat_raw >= 0.0
		var sat: float = sat_raw if wired else 0.0
		# `.get()` 不是 `.has()`：`_engaged` 是 {id: bool}，沒交戰的塔**鍵也在**，
		# 值才是 false（第 1008 行那條既有斷言用的就是 get）。
		var busy: bool = engage > 0.0 and bool(_engaged.get(int(n["id"]), false))
		var draw := (engage if busy else 0.0) + idle
		if engage > 0.0:
			lines.append("交戰耗能　%.1f 能量/秒%s" % [engage, "" if busy else "（待機 0）"])
		if idle > 0.0:
			lines.append("待機耗能　%.1f 能量/秒" % idle)
		if not wired:
			# 和提示列講同一句話——同一件事在兩個地方要有同一個說法。
			lines.append("此刻　沒接進電網，交戰時一發都打不出來")
		else:
			lines.append("此刻　%.1f 能量/秒　餵得 %d%%" % [draw * sat, int(round(sat * 100.0))])

	# ── ★ 電從哪來 ──
	var sources: Dictionary = _power_sources()
	var chain := FlowNetwork.upstream_power(s.conduits, _energy_net(), _selected, sources)
	var feeders: Dictionary = chain["sources"]
	if engage > 0.0 or idle > 0.0:
		# ⚠ 「沒有外部來源」和「在挨餓」**不是同一件事**。回收者靠自己的回收緩衝、
		#   儲槽靠自己的存量，兩者都會出現「一條線都沒有在餵它，而它餵得飽飽的」。
		#   第一版一律寫「沒有——這一刻沒有任何電流進來」，於是面板上一行寫
		#   「餵得 100%」、下一行寫「沒有供電」，讀起來像壞掉了（截圖當場看到）。
		var self_fed: bool = String(n["type"]) in ["reclaimer", "silo"]
		var supply_text := "%d 座（已在地圖上標出）" % feeders.size()
		if feeders.is_empty():
			supply_text = "沒有外部來源，這一刻靠自己的存量" if self_fed 				else "這一刻沒有電流進來"
		lines.append("供電　%s" % supply_text)

	# ── ★ 兩顆動詞鈕（B3.7）──
	# **核心兩顆都關**：它升不得也拆不得（`upgrade_node()`／`demolish()` 都擋著）。
	# 鈕在那裡而按不動，等於邀請玩家去按一個保證失敗的東西。
	if type == "core":
		_show_verbs("", "")
	else:
		# ★ B3.8：鈕上寫**這一級買到的是什麼**。三級各不相同，而玩家在按下去
		#   之前必須知道自己買的是射程還是射速——否則「多元化」對他等於隨機。
		var up := "已滿級" if lvl >= Build.NODE_MAX_LEVEL else "升級　%s　%d 礦砂" % [
			_step_text(Build.next_step(type, lvl)),
			Build.node_upgrade_cost(NodeDefs.cost(type), lvl),
		]
		var refund := BuildController.node_refund(type)
		_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.NODE_MAX_LEVEL)
	_place_inspect(lines)


## ★ 被選取那條導管的當下數據（B3.7）。
##
## 玩家點一條線要問的是同一組問題，只是主詞換了：**它多粗 → 這一刻擠不擠 →
## 加粗要多少錢**。「擠不擠」是這一批真正要答的——導管滿載在圖上是變色與線寬，
## 那是給掃視用的；點下去要拿得到數字。
func _refresh_inspect_wire(wi: int) -> void:
	var c: Dictionary = s.conduits[wi]
	var lvl := int(c["level"])
	var cap := Build.conduit_cap(lvl, float(s.mods["cap_bonus"]))
	var flow := float((s.rates["conduit_flow"] as Dictionary).get(c["id"], 0.0))
	var lines: Array[String] = []
	lines.append("導管%s" % ("　%d 級" % lvl if lvl > 0 else ""))
	lines.append("生命　%d / 40" % int(c["hp"]))
	lines.append("長度　%d 格" % (Build.conduit_cost(c["a"], c["b"]) / Build.CONDUIT_COST_PER_CELL))
	# 「這一刻擠不擠」：滿載是這條線正在**卡住**它下游的每一個節點。
	lines.append("流量　%.1f / %.0f 每秒%s" % [
		flow, cap, "　已滿載" if flow >= cap - 0.05 else ""
	])
	if lvl < Build.CAP_MAX_LEVEL:
		lines.append("加粗後　%.0f 每秒" % Build.conduit_cap(lvl + 1, float(s.mods["cap_bonus"])))

	var up := "已滿級"
	if lvl < Build.CAP_MAX_LEVEL:
		var alloy := Build.upgrade_alloy(lvl)
		up = "加粗　%d 礦砂%s" % [
			Build.upgrade_cost(lvl), "" if alloy == 0 else " ＋ %d 合金" % alloy
		]
	var refund := BuildController.conduit_refund(c)
	_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.CAP_MAX_LEVEL)
	_place_inspect(lines)


## 兩顆鈕的文字與可按性。空字串＝那顆鈕整個收起來。
func _show_verbs(up: String, del: String, up_on: bool = true) -> void:
	_inspect_up.visible = up != ""
	_inspect_up.text = up
	_inspect_up.disabled = not up_on
	_inspect_del.visible = del != ""
	_inspect_del.text = del


## 面板的內容與座標。**兩種選取共用**——版面規則只有一份，不然加第三種選取時
## 會有一種悄悄跑到畫面外（RG-139／149／162／170 都是同一個錯法）。
func _place_inspect(lines: Array[String]) -> void:
	_inspect_label.text = "
".join(lines)
	_inspect_panel.visible = true
	# ── ★ 座標只能是**離散狀態**的函式（B3.9.1，使用者回報「點了升級之後，滑鼠會
	#      位移到一個很奇怪的位置」）───────────────────────────────────────
	#
	#   位移的不是游標，是面板。它的位置本來同時是**內容**的函式：靠右對齊用的是
	#   實際寬度（字一長就往左滑，量到 277 → 383），避讓鄰居判的是實際高度
	#   （多一行就從右緣彈到 x=477）。於是升一級＝兩顆鈕跑掉，而停在原地的游標
	#   落到地圖上，或落到「拆除」上。
	#
	#   兩條規矩：
	#   ① **寬高一律用常數**（`INSPECT_W`／`INSPECT_MAX_H`）算位置與避讓，實際尺寸
	#      只拿來對齊底邊。位置因此只由「鄰居開著沒」決定——那是玩家自己按的開關，
	#      不是每 tick 都在變的數字。
	#   ② **底邊釘住**。兩顆動詞鈕在面板底列，底邊不動＝鈕不動；內容變多時往上長。
	#      頂邊釘住的話，多一行字就把鈕往下推。
	var bottom := FRAME.end.y - 12.0
	var pos := Vector2(float(size.x) - INSPECT_W - 24.0, bottom - _inspect_panel.size.y)
	var probe := Rect2(Vector2(pos.x, bottom - INSPECT_MAX_H), Vector2(INSPECT_W, INSPECT_MAX_H))
	# ⚠ **右下角住著三個東西**：能量收支面板（右上）、小地圖（右下）、和它自己。
	#   讓位一律**往左挪，不能往上擠**：能量面板自己就有 358 高，右緣從 y 96 排到
	#   454，小地圖從 525 起——中間只剩 71px，塞不下一個 174px 高的面板。
	#   B3.7 把上限夾在小地圖上緣，結果是面板被推回去壓在能量面板身上
	#   （量到 392–650 對 96–454）——**那只是把一個重疊換成另一個重疊**
	#   （`版面=false` 從 B3.8 就紅著）。
	if _energy_panel != null and _energy_panel.visible:
		var energy := Rect2(_energy_panel.position, _energy_panel.size)
		if probe.intersects(energy):
			pos.x = maxf(FRAME.position.x + 12.0, energy.position.x - INSPECT_W - 12.0)
			probe.position.x = pos.x
	var mini := _minimap_rect()
	if probe.intersects(mini):
		pos.x = maxf(FRAME.position.x + 12.0, mini.position.x - INSPECT_W - 12.0)
	_inspect_panel.position = pos


## 本 tick 每條導管的**能量**淨流（沿 a→b 為正）。
func _energy_net() -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		out[c["id"]] = v.y
	return out


## 會發電的那些格（發電機、放電中的儲槽、回收者的緩衝）。
func _power_sources() -> Dictionary:
	var out: Dictionary = {}
	for n: Dictionary in s.nodes:
		var d := NodeDefs.of(String(n["type"]))
		if float(d.get("power_out", 0.0)) > 0.0 or String(n["type"]) in ["silo", "reclaimer"]:
			out[n["cell"]] = true
	return out


func _on_codex_show(type: String, from: Button) -> void:
	if not _codex_on or Hooks.naked:
		return
	_codex_label.text = "\n".join(_codex_lines(type))
	_codex_panel.visible = true
	# 貼著那顆鈕的右側浮出來，垂直對齊它——視線不必離開來源。
	_codex_panel.position = Vector2(124.0, clampf(from.global_position.y - 8.0, 56.0, 470.0))


func _on_codex_hide() -> void:
	_codex_panel.visible = false


## 一種節點的簡介。**先講它在取捨裡的位置，再列數字**——
## 一串沒有脈絡的數值幫不了正在決定「這一分鐘要蓋什麼」的人。
## 升級階梯的一個台階講成人話（B3.8）。**四個詞的唯一翻譯處**——
## 圖鑑與檢視面板讀同一支，兩邊各寫一份的話遲早有一邊沒跟上資料表。
func _step_text(step: String) -> String:
	return {
		Build.STEP_POWER: "出力 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_RANGE: "射程 +1 格",
		Build.STEP_ROF: "射速 +%d%%" % int(Build.NODE_STEP * 100.0),
		Build.STEP_SPLASH: "濺射 +1 格",
	}.get(step, step)


func _codex_lines(type: String) -> Array[String]:
	var def := NodeDefs.of(type)
	var out: Array[String] = [BuildController.price_text(type)]
	out.append({
		"extractor": "礦砂的源頭。只能蓋在礦點上，而且要接到核心才入帳。",
		"generator": "把礦砂燒成能量。全遊戲唯一的電力來源，每台吃 4 礦砂/秒。",
		"smelter": "合金的唯一來源。吃礦砂也吃電，而且待機也吃 10 能量/秒。合金要接到核心才入帳。",
		"breaker": "濺射：打中最前那一隻，順便打它周圍 2.5 格內的每一隻。單打比錨弱，敵人擠成一團時才划算。",
		"relay": "轉彎與分岔用。導管只能走直線與 45°，所有拐角都靠它。",
		"silo": "準備期存電、波次期放電。充放電速率受它自己那條導管的 cap 限制，擺太遠或線太細就趕不上。",
		"anchor": "最便宜的塔，物理傷害。護甲是減法，打甲殼很吃虧。",
		"prism": "最貴的塔，能量傷害穿透一直線。與路徑同一列時可一次貫穿整段。",
		"knell": "不開火。減速 40% ＋ 破甲 25%，多座不疊加，取最強的一座。",
		# `Label` 不解析 Markdown——`**任何**` 會原樣印出兩排星號（B0.7.1／B0.7.3
		# 各犯過一次，這裡是第三處，B1.1 一併掃掉）。強調一律用「」。
		"reclaimer": "射程內「任何」敵人死亡就回收能量（不限自己擊殺）。蓋在敵人常死的那一段路上。",
		"longcall": "射程 12，一座蓋掉大圖的一個象限。每瓦傷害中等，用來補防線的空隙。",
		"frostreef": "不開火。減速 65%（潮鳴 40%）但「沒有」破甲，射程只有 3，電費是潮鳴的 1.8 倍。減速與破甲各自取最大，所以和潮鳴疊得起來，但兩座都要吃電。",
		"ballast": "血量 90（其餘塔 60），每瓦傷害全場最高。造價 240 礦砂＋100 合金，而合金要一座待機吃 10 電的熔爐。",
	}.get(type, ""))
	if def.has("ore_out"):
		out.append("產出　＋%.0f 礦砂/秒" % float(def["ore_out"]))
	if def.has("ore_in"):
		out.append("燃料　−%.0f 礦砂/秒" % float(def["ore_in"]))
	if def.has("power_out"):
		out.append("產出　＋%.0f 能量/秒" % float(def["power_out"]))
	if def.has("alloy_out"):
		out.append("產出　＋%.0f 合金/秒" % float(def["alloy_out"]))
	if def.has("power_in"):
		out.append("耗能　−%.0f 能量/秒（一直吃）" % float(def["power_in"]))
	if def.has("capacity"):
		out.append("容量　%.0f 能量" % float(def["capacity"]))
	if def.has("engage_power"):
		out.append("耗能　交戰時 −%.0f 能量/秒（待機 0）" % float(def["engage_power"]))
	if def.has("range"):
		out.append("射程　%.0f 格　射速 %.1f 發/秒　傷害 %.0f（%s）%s" % [
			float(def["range"]), float(def.get("rof", 0.0)), float(def.get("dmg", 0.0)),
			"能量" if String(def.get("dmg_type", "physical")) == "energy" else "物理",
			"　濺射 %.1f 格" % float(def["splash"]) if def.has("splash") else ""
		])
	out.append("生命　%.0f　※ 退開敵人路徑 2 格就打不到" % NodeDefs.hp(type))
	# ★ B3.8：把三級的階梯寫在**花錢之前**看得到的地方（§4.3）。
	#   「每一級加的不是同一樣東西」如果只有升級當下才看得到，玩家在擺位時
	#   就沒有辦法把它算進去——而擺位是本作的主要決策。
	var ladder := PackedStringArray()
	for lv in Build.NODE_MAX_LEVEL:
		ladder.append("%d 級 %s" % [lv + 1, _step_text(Build.next_step(type, lv))])
	out.append("升級　" + "　→　".join(ladder))
	return out


func _on_toggle_priority(open: bool) -> void:
	_prio_panel.visible = open


## 一條滑桿推的是**整列**（`NodeDefs.priority_members`，B2.4）。`FlowNetwork`
## 仍然逐 type 讀 `priorities[type]`——合併只發生在這裡，模擬層不知道有這回事。
func _on_priority(row: String, delta: int) -> void:
	for type: String in NodeDefs.priority_members(row):
		s.priorities[type] = clampi(
			int(s.priorities.get(type, 1)) + delta, NodeDefs.PRIORITY_MIN, NodeDefs.PRIORITY_MAX
		)
	_refresh_priority()


## TL_NAKED 明文包含「優先權面板刻度」（`30_TECH_DESIGN.md` §4.1）：
## 刻度是數值標籤，改用琥珀小方塊表示同一個 1–5，形狀仍讀得出高低。
func _refresh_priority() -> void:
	for type: String in _prio_labels:
		var v := int(s.priorities.get(type, 1))
		(_prio_labels[type] as Label).text = "▪".repeat(v) if Hooks.naked else str(v)


## 左欄的工具鈕。`toggle_mode` ＋ 共用群組 ＝ 內建的「選中」外觀，
## 不必自己塗顏色（`20_ART_DIRECTION.md`：能用主題就別硬編碼色值）。
func _tool_button(group: ButtonGroup, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 建造欄的段標題（B2.4.2）。`text.xs` ＋ `text.secondary`——它是分界不是內容，
## 不該和鈕搶注意力。**不畫線**：兩段之間本來就有 2px 間距 ＋ 一個矮標題，
## 再加一條線就是同一個分界講兩次（§4.3b「同一個位置上的兩個訊息」的同一條）。
func _section_label(text: String) -> Control:
	var l := UiKit.label(text, 11, Palette.TEXT_SECONDARY, false)
	l.custom_minimum_size = Vector2(0, 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## ★ B3.7.1：建造鈕改成**開關**（使用者指定「按一下選擇，再按一下取消選擇」）。
##
## 手上什麼都沒拿的時候，左鍵就純粹是檢視——點節點看節點、點導管看導管、
## 點空地什麼都不做。那也是**在有導管經過的格子上蓋東西**之外，另一個
## 「我只是想看一下」的正常需求。
##
## ⚠ 放開那一支要**確認自己還是當前那一個才清空**。同一個 `ButtonGroup` 換鈕時
##   會先後送出「舊的 false」與「新的 true」兩個事件，而兩者的順序不是這裡能
##   假設的——沒有這個守衛，換鈕有一半的機率把剛選好的那一個清掉。
func _on_build_type(pressed: bool, type: String) -> void:
	if not pressed:
		if _build_type == type:
			_build_type = ""
			_message = ""
			_refresh_hint()
		return
	_mode = Mode.BUILD
	_build_type = type
	_drag_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


# ── 藍圖庫（B2.3、`10_GDD.md` §3.7）───────────────────────────────────

## 這一份存檔有幾個槽。**吃的是玩家的科技，不是這一局的 `s.mods`**——
## 藍圖庫是跨局資產（§3.7），而每日挑戰的統一配置榜會把 `s.mods` 壓成中性值
## （憲法 B3）。用 `s.mods` 的話，打統一配置榜時玩家的槽會憑空少兩個。
func _bp_slots() -> int:
	var unlocked: Array = (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])
	return Blueprint.slots(Tech.mods(unlocked))


func _blueprints() -> Array:
	return GameState.data.get("blueprints", [])


## 框選存檔。
func _save_blueprint(a: Vector2i, b: Vector2i) -> void:
	var bp := Blueprint.capture(s.nodes, s.conduits, a, b)
	var err := SaveService.add_blueprint(GameState.data, bp, _bp_slots())
	if err != "":
		_message = err
		return
	SaveService.save_from(GameState.data)
	var cost: Dictionary = Blueprint.cost(bp)
	_message = "✔ 已存為藍圖　%d 節點・%d 導管　展開要 %d 礦砂" % [
		(bp["nodes"] as Array).size(), (bp["conduits"] as Array).size(), int(cost["ore"])
	]
	_refresh_blueprints()


## 把手上那張藍圖放在 `cell`。**全有全無**（`BuildController.blueprint_place`）。
func _expand_blueprint(cell: Vector2i) -> void:
	var list := _blueprints()
	if _bp_index < 0 or _bp_index >= list.size():
		_bp_index = -1
		return
	var err := BuildController.blueprint_place(s, list[_bp_index], cell)
	if err != "":
		_message = err
		return
	AudioBus.play("build_place")
	# 放完就放下它。**不留在手上**：藍圖是「一次把一整條產線種下去」，
	# 連放兩次的自然結果是兩份重疊在一起而第二份整份失敗。
	_bp_index = -1
	_message = "✔ 藍圖已展開"
	_refresh_blueprints()
	queue_redraw()


func _on_toggle_blueprint(open: bool) -> void:
	_bp_panel.visible = open
	if open:
		_refresh_blueprints()


## 重畫藍圖抽屜。列出每一張的名字、成本，以及兩顆鈕（展開／刪除）。
func _refresh_blueprints() -> void:
	if _bp_panel == null:
		return
	var col: VBoxContainer = _bp_panel.get_child(0)
	UiKit.clear(col)
	var list := _blueprints()
	col.add_child(UiKit.label(
		"藍圖庫　%d／%d 槽" % [list.size(), _bp_slots()], 16, Palette.TEXT_PRIMARY, false
	))
	col.add_child(UiKit.label(
		"框選：切「藍圖」→ 在地圖上按住拖出一個框",
		13, Palette.TEXT_SECONDARY, false
	))
	if list.is_empty():
		col.add_child(UiKit.label("（尚無藍圖）", 13, Palette.TEXT_SECONDARY, false))
		return
	for i in list.size():
		var bp: Dictionary = list[i]
		var cost: Dictionary = Blueprint.cost(bp)
		var row := UiKit.hbox(6)
		col.add_child(row)
		# 成本寫在清單上，**不是等玩家點下去才知道**（§3.7「自動計算成本」）。
		var alloy_part := "" if int(cost["alloy"]) <= 0 else "・%d 合金" % int(cost["alloy"])
		row.add_child(UiKit.label("%s　%d 礦砂%s" % [
			String(bp.get("name", "")), int(cost["ore"]), alloy_part
		], 13, Palette.TEXT_PRIMARY, false))
		var take := Button.new()
		take.text = "放下" if _bp_index == i else "展開"
		take.pressed.connect(_on_take_blueprint.bind(i))
		row.add_child(UiKit.touchable(take))
		var del := Button.new()
		del.text = "刪除"
		del.pressed.connect(_on_delete_blueprint.bind(i))
		row.add_child(UiKit.touchable(del))


func _on_take_blueprint(i: int) -> void:
	# 再按一次＝放下。拿著藍圖時左鍵會展開它，沒有取消的手勢就等於卡住。
	_bp_index = -1 if _bp_index == i else i
	if _bp_index >= 0:
		_mode = Mode.BUILD
		_message = "藍圖在手上：左鍵點地圖放下它（再按一次「放下」取消）"
	_refresh_blueprints()
	queue_redraw()


func _on_delete_blueprint(i: int) -> void:
	var list := _blueprints()
	if i < 0 or i >= list.size():
		return
	list.remove_at(i)
	GameState.data["blueprints"] = list
	SaveService.save_from(GameState.data)
	_bp_index = -1
	_refresh_blueprints()


## 藍圖鈕。同建造鈕，`toggled` ＋ 再按一次回到建造（B3.7.1）。
func _on_mode(pressed: bool, mode: int) -> void:
	if not pressed:
		if _mode == mode:
			_mode = Mode.BUILD
			_message = ""
			_refresh_hint()
		return
	_mode = mode
	# 換模式就放下手上的藍圖：拿著它的時候左鍵是「展開」，而玩家切走
	# 是為了做別的事——留著會讓下一次左鍵做出他沒想要的事。
	if _bp_index >= 0:
		_bp_index = -1
		_refresh_blueprints()
	_drag_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _refresh_top() -> void:
	_refresh_summon()
	# ★ 快進鈕自己講自己開沒開（B2.4.4）。它不是 toggle（按下去只是切換 tick 倍率），
	#   所以在此之前**畫面上唯一的指示是頂欄那段「▶4×」**——因在底欄、果在頂欄。
	if _ff_button != null:
		_ff_button.text = "▶ 快進中 4×" if s.speed_mult > 1 else "快進 4×"
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	# **能量條不在此列**——它是圖形，長度即資訊（§6.2 硬性要求 1），畫在 `_draw()`。
	if Hooks.naked:
		_top.visible = false
		return
	var r: Dictionary = s.rates
	var core_full := NodeDefs.hp("core")
	var core_col: Color = (
		Palette.WARN_ORANGE if s.core_hp() < core_full else Palette.ORDER_BRIGHT
	)
	# 一欄一列：[數值, 註腳, 顏色]。順序與 `TOP_CELLS` 一致。
	# 合金緊貼礦砂：**兩個都是造價貨幣**，玩家看的是同一個問題（我買得起嗎）。
	# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束），
	# 所以它掛在能量那一格旁邊當註腳，不是一個獨立的數字。
	var texts := [
		[UiKit.commas(int(s.ore)), "▲%.1f/秒" % r["ore_in"], Palette.ORDER_CYAN],
		[UiKit.commas(int(s.alloy)), "▲%.1f/秒" % r["alloy_in"], Palette.ALLOY_VIOLET],
		[
			"%.0f/%.0f" % [r["power_supply"], r["power_demand"]],
			"交戰 %d 座" % int(r["engaged"]),
			Palette.ENERGY_AMBER,
		],
		# ★ 擊殺數**不在頂欄**（B2.4.4）：它是計分不是決策輸入——沒有任何一個
		#   當下的操作取決於它，而頂欄的每一格都要為「我現在該做什麼」服務。
		#   它在局末結算裡；回收者換到的能量在能量面板有專屬一列。
		[
			_phase_parts()[0], _phase_parts()[1],
			Palette.TIDE_MAGENTA if s.phase == "wave" else Palette.TEXT_SECONDARY,
		],
		["%.0f/%.0f" % [maxf(0.0, s.core_hp()), core_full], "", core_col],
	]
	for i in texts.size():
		var col: Color = texts[i][2]
		_top_values[i].text = String(texts[i][0])
		_top_values[i].add_theme_color_override("font_color", col)
		_top_notes[i].text = String(texts[i][1])
		# 註腳走同一個色相但降一階字級：**顏色維持分群，層級交給字級**
		# （§7.2 B-2：顏色分群是這一批做對的事，要留著）。
		_top_notes[i].add_theme_color_override("font_color", Palette.alpha(col, 0.7))
	# ★ 倒數最後 10 秒脈動（`20_ART_DIRECTION.md` §4.3「一定要動」清單，B1.6）。
	#   **它動的是階段那一格**，不是整條頂欄——脈動要指向「時間快到了」這一件事。
	#   週期用 `dur.slow`：比環境呼吸急、又不到讓人分心的程度。
	var phase_label := _top_values[3]
	var urgent: bool = s.phase == "prep" and s.prep_time() - s.phase_time <= 10.0
	phase_label.modulate = Palette.MOD_FULL
	if urgent:
		phase_label.add_theme_color_override("font_color", Palette.WARN_ORANGE)
		phase_label.modulate = Palette.mod_alpha(Motion.pulse01(s.tick_count, Motion.SLOW, 0.45))


## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
##
## ★ 回傳 `[主, 附屬]` 兩段（B2.4.4）：主的是「我還有多少時間／現在第幾波」
## （`text.lg`），附屬的是波號、快進倍率、殘敵（`text.sm`）。
## **原本是一整串塞在同一個 22px 的標籤裡**，量到那一格 299px、把整條頂欄
## 撐出畫面 —— 而它裡面本來就有兩階資訊。
func _phase_text() -> String:
	return _phase_parts()[0]


func _phase_parts() -> Array:
	# ★ 難度層掛在附屬那一段（B2.6）。**只在第 1 層以上出現**：第 0 層寫「標準」
	#   等於在每一局的頂欄佔一格去講「沒有任何額外規則」。
	var tier := "　%s" % Difficulty.of(s.difficulty)["name"] if s.difficulty > 0 else ""
	match s.phase:
		"prep":
			var left: float = maxf(0.0, s.prep_time() - s.phase_time)
			# ★ 快進倍率**不在這裡**（B2.4.4）：它原本同時出現在頂欄與底欄那顆
			#   「快進 4×」鈕上，而那顆鈕自己**看不出開沒開**（它不是 toggle）。
			#   指示搬到按鈕上——因與果放在同一個地方，頂欄也省下一段會變長的字。
			# 駐足在核心的敵人不會隨波次結束而消失（§3.5）。不講的話，
			# 玩家會看到核心在準備期掉血卻找不到原因。
			var left_over := "　殘敵 %d" % s.enemies.size() if not s.enemies.is_empty() else ""
			return ["準備期 %0.1fs" % left, "下一波 %d%s%s" % [s.wave_index + 1, left_over, tier]]
		"wave":
			return ["第 %d 波" % s.wave_index, "敵人 %d%s" % [s.enemies.size(), tier]]
		"won":
			return ["通關", ""]
		_:
			return ["核心已毀", ""]


## 快進只在準備期能按（`10_GDD.md` B5：可跳過等待，戰鬥期不可加速也不可減速）。
func _on_fast_forward() -> void:
	if s.phase != "prep":
		return
	s.speed_mult = 1 if s.speed_mult > 1 else FAST_FORWARD_RATE
	_refresh_top()


## ★ 提前召喚：**按鈕常駐顯示當前獎勵倍率**（`10_GDD.md` §6.2 硬性要求 3）——
## 下注的誘惑要一直在眼前，而不是按下去才知道賭到多少。
## 倍率隨倒數每 tick 縮水，所以這個字串每幀重算。
func _refresh_summon() -> void:
	if _summon_button == null:
		return
	var can: bool = s.phase == "prep"
	_summon_button.disabled = not can
	if Hooks.naked or not can:
		_summon_button.text = "提前召喚"
		return
	var bonus := Score.summon_bonus(maxf(0.0, s.prep_time() - s.phase_time), s.prep_time())
	_summon_button.text = "提前召喚 +%d%%" % roundi((bonus - 1.0) * 100.0)


func _on_summon_now() -> void:
	BattleController.start_wave(s)
	_refresh_top()


## 局末結算（通關或核心歸零）。三個數字照 `10_GDD.md` §7.6 逐項攤開——
## **玩家要看得出研究數據是怎麼算出來的**，一個總分教不會他下一局該改什麼。
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4），
## 而且失敗不扣任何東西（紅線 R1）——局內狀態本來就不持久化。
func _refresh_over() -> void:
	if _ff_button != null:
		_ff_button.disabled = s.phase != "prep"
	if s.phase != "lost" and s.phase != "won":
		if _over_panel != null:
			_over_panel.queue_free()
			_over_panel = null
		return
	if _over_panel != null:
		return
	# ★ 局一結束 `BattleController.step()` 就直接 return，開火線與碎片的 `ttl`
	#   從此不再遞減——它們會**永遠停在畫面上**，看起來像每一座塔都卡在開火的
	#   那一幀（使用者回報「他們還在射擊」）。兩者都是純渲染、不進 `state_hash()`，
	#   由畫面層在這裡收乾淨。
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
	var won: bool = s.phase == "won"
	var waves: int = s.wave_index if won else maxi(0, s.wave_index - 1)
	var score := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	var box := UiKit.panel()
	box.position = Vector2(440, 230)
	var col := UiKit.vbox(10)
	box.add_child(col)
	col.add_child(UiKit.label(
		"通關" if won else "核心已毀", 32, Palette.OK_GREEN if won else Palette.TIDE_MAGENTA
	))
	# ★ 無盡的個人最佳（B2.1a、§7.10）。放在星等的位置——無盡沒有星，
	#   「破了幾項紀錄」就是它的成就感來源。兩欄各自比對（`apply_endless`）。
	if endless_seed != 0:
		# ★ 每日挑戰記在自己那一格，不混進無盡的個人最佳（B2.2）：兩者的地圖
		#   來源一樣，但無盡是「隨便一張圖能撐多久」、每日是「今天這張圖」。
		#   混在一起會讓無盡的紀錄被一張特別好打的日圖洗掉。
		var daily: bool = daily_board != ""
		# ★ 無盡的紀錄逐難度層各一筆（sv3、`data/Difficulty.gd`）：拿第 0 層的
		#   紀錄去比第 3 層的成績，「破紀錄」那三個字就會變成一句謊。
		var slot: Dictionary = (
			((GameState.data.get("daily", {}) as Dictionary).get("today", {}) as Dictionary)
				.get(daily_board, {})
			if daily else Difficulty.best(GameState.data, difficulty)
		)
		var prev_wave := int(slot.get("wave", 0))
		var prev_output := float(slot.get("output", 0.0))
		var fresh := (
			SaveService.apply_daily(GameState.data, daily_date, daily_board, waves, score)
			if daily else SaveService.apply_endless(GameState.data, waves, score, difficulty)
		)
		SaveService.save_from(GameState.data)
		if daily:
			col.add_child(UiKit.label(
				"每日挑戰　%s　%s" % [
					daily_date, "統一配置" if daily_board == Daily.UNIFORM else "自由配置"
				], 13, Palette.ORDER_CYAN, false
			))
		elif difficulty > 0:
			# 紀錄記在哪一層要說出來，否則「最高波次 8 波」看起來像退步。
			col.add_child(UiKit.label(
				"無盡　%s" % Difficulty.name_of(difficulty), 13, Palette.WARN_ORANGE, false
			))
		for line: Array in [
			["最高波次　%d 波" % waves, bool(fresh["wave"]), "前次 %d 波" % prev_wave],
			["最佳產能　%.1f" % score, bool(fresh["output"]), "前次 %.1f" % prev_output],
		]:
			col.add_child(UiKit.label(
				"%s　%s" % [line[0], "★ 新紀錄" if line[1] else line[2]],
				15, Palette.ENERGY_AMBER if line[1] else Palette.TEXT_SECONDARY, false
			))
	# ★ 星等與獎勵只在戰役關卡有（測試圖與沙盤沒有進度可寫）。
	if not level.is_empty():
		var stars := Score.stars(
			won, s.core_hp(), NodeDefs.hp("core"), score, float(level["star_throughput"])
		)
		var gain := SaveService.apply_result(
			GameState.data, String((level["map"] as Dictionary)["id"]),
			stars, int(level["reward"])
		)
		SaveService.save_from(GameState.data)
		col.add_child(UiKit.label(
			"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 32, Palette.ENERGY_AMBER
		))
		for line: String in _star_lines(stars, score):
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
		if gain > 0.0:
			col.add_child(UiKit.label(
				"關卡獎勵　＋%.0f 研究數據" % gain, 13, Palette.OK_GREEN, false
			))
	# ★ 升級材料（B2.7、§7.15 的第一條路）。**只有戰役與無盡算**——
	#   測試圖與沙盤沒有進度可寫（星等與研究數據的同一條線）。
	#   只數波數：加星數加成的話，重刷第 1 關會比打完第 5 關划算。
	var comps := 0
	if not level.is_empty() or endless_seed != 0:
		comps = SaveService.apply_components(GameState.data, waves)
		if comps > 0:
			SaveService.save_from(GameState.data)
			col.add_child(UiKit.label(
				"升級材料　＋%d（撐過的波數）　現有 %d" % [
					comps, SaveService.components(GameState.data)
				], 13, Palette.OK_GREEN, false
			))
	for line: String in [
		"撐過 %d 波　　＋%.0f 研究數據" % [waves, Score.DATA_PER_WAVE * float(waves)],
		"產能積分 %.1f（送達核心 %s 礦砂）　＋%.0f" % [
			score, UiKit.commas(int(s.delivered_total)), Score.DATA_PER_SCORE * score
		],
		"提前召喚累計加成　　＋%.0f" % s.bonus_data,
		"研究數據合計 %.0f　　擊殺 %d" % [
			Score.research_data(waves, score, s.bonus_data), s.kills
		],
		"失敗不扣任何東西" if not won else "",
	]:
		if line != "":
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
	# ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」——
	#   上面那幾行是**成績**，這一行才是**原因**。放在按鈕正上方：
	#   玩家的視線在按「立刻重來」之前一定會經過這裡。
	var why := _diag_line(won)
	if why != "":
		var lbl := UiKit.label(
			why, 13, Palette.WARN_ORANGE if not won else Palette.ORDER_CYAN, false
		)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size.x = 400.0
		col.add_child(lbl)
	var buttons := UiKit.hbox(8)
	col.add_child(buttons)
	var again := Button.new()
	again.text = "立刻重來"
	again.pressed.connect(_restart)
	buttons.add_child(UiKit.touchable(again))
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "回關卡選擇"
		back.pressed.connect(on_exit)
		buttons.add_child(UiKit.touchable(back))
	# 面板本身不吃滑鼠（`UiKit.panel` 的 RG-39），但**這兩顆鈕要點得到**。
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	_over_panel = box


## 三顆星各自的達成與否，逐條講清楚——**沒拿到的那顆要說出差在哪**，
## 不然「兩顆星」只是一個沒有下一步的評分。
func _star_lines(stars: int, score: float) -> Array[String]:
	var threshold := float(level["star_throughput"])
	var out: Array[String] = [
		"%s 通關" % ("★" if stars >= 1 else "☆"),
		"%s 核心無損（%.0f/%.0f）" % [
			"★" if stars >= 2 else "☆", s.core_hp(), NodeDefs.hp("core")
		],
		"%s 產能積分 %.2f ／ 門檻 %.2f" % ["★" if stars >= 3 else "☆", score, threshold],
	]
	return out


# ── 局內選單（B1.4.1）────────────────────────────────────────────────
#
# ★ **不暫停**（`10_GDD.md` B5「不可暫停，但可跳過等待」）。選單開著的這幾秒
#   敵人仍然在走、電仍然在流。這不是偷懶：可暫停的選單就是一個「隨時可以停下來
#   慢慢想」的按鍵，而那正是 B5 要擋掉的東西。面板上直接寫出來，玩家才不會
#   以為是遊戲壞了——**沒說出口的規則會被當成 bug**。

## ESC。**鍵盤不是唯一的路**（手機移植預留條款 P3）：左上角有一顆「選單」鈕
## 做完全同一件事，`_toggle_menu()` 是兩者共用的那一個入口。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 設定浮層開著時**不消費事件**，交給它自己的 ESC（它會回到選單）。
	# 這樣兩邊誰先被呼叫都不影響結果——不必賭 Godot 的輸入傳遞順序。
	if _settings_layer != null:
		return
	get_viewport().set_input_as_handled()
	AudioBus.play("ui_back")   # ESC ＝ 取消手勢，全遊戲同一個音（B1.5）
	_toggle_menu()


func _toggle_menu() -> void:
	if _menu_layer != null:
		_close_menu()
		return
	_open_menu()


## 半透明遮罩。它做兩件事：把戰場壓暗讓選單讀得到，以及**吃掉滑鼠**——
## 選單開著的時候點下去不該蓋出一個節點來（`mouse_filter` 預設 STOP）。
func _scrim() -> Control:
	var layer := ColorRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.color = Palette.alpha(Palette.BG_DEEP, 0.82)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP   # 明寫：擋滑鼠是它一半的工作
	return layer


func _open_menu() -> void:
	_close_menu()
	_menu_layer = _scrim()
	add_child(_menu_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.add_child(center)
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 面板不吃滑鼠，但鈕要點得到
	center.add_child(box)
	var col := UiKit.vbox(8)
	box.add_child(col)
	col.add_child(UiKit.label("選單", 32, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label("時間仍在走。這款遊戲不能暫停。", 13, Palette.WARN_ORANGE))
	_menu_buttons.clear()
	# 「重來」與「退出」的代價寫在鈕上。**不做二次確認**：R1 說失敗只花時間，
	# 而一句括號比一個確認框省一次點擊，也省一整個對話框元件。
	var entries: Array = [
		["繼續", _close_menu],
		["重來（本局歸零）", _restart],
		["設定", _open_settings],
	]
	if on_exit.is_valid():
		entries.append(["退出（放棄本局）", on_exit])
	for entry: Array in entries:
		var b := Button.new()
		b.text = String(entry[0])
		b.custom_minimum_size.x = 200
		b.pressed.connect(entry[1] as Callable)
		_menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))


func _close_menu() -> void:
	if _menu_layer == null:
		return
	# `queue_free()` 要到影格末才生效，中間那一幀遮罩還在畫也還在吃滑鼠——
	# 先 `remove_child()` 讓它當場離開樹（`Campaign._clear()` 同一條）。
	remove_child(_menu_layer)
	_menu_layer.queue_free()
	_menu_layer = null
	_menu_buttons.clear()


## 局內開設定：整個設定畫面原封不動疊上來，不另做一份「局內版設定」——
## 兩份設定畫面遲早會有一份漏掉新選項。
func _open_settings() -> void:
	_close_menu()
	_settings_layer = _scrim()
	add_child(_settings_layer)
	var screen := SettingsScreen.new()
	screen.on_exit = _close_settings
	_settings_layer.add_child(screen)


func _close_settings() -> void:
	if _settings_layer != null:
		remove_child(_settings_layer)
		_settings_layer.queue_free()
		_settings_layer = null
	_open_menu()


func _restart() -> void:
	for c: Node in get_children():
		c.queue_free()
	# 選單／設定浮層是 `get_children()` 的一員，上面那圈已經把它們清掉了；
	# 這裡要跟著把手上的參照放掉，否則下一次 ESC 會以為選單還開著。
	_menu_layer = null
	_settings_layer = null
	_menu_button = null
	_menu_buttons.clear()
	_over_panel = null
	_top = null
	# 這兩個陣列裝的是已經 `queue_free()` 掉的 Label——不清就會拿到斷裂的參照。
	_top_values.clear()
	_top_notes.clear()
	_hint = null
	_ff_button = null
	_summon_button = null
	_prio_panel = null
	_bp_panel = null
	_help_panel = null
	_help_button = null
	_energy_panel = null
	_energy_button = null
	_codex_panel = null
	_codex_button = null
	_codex_label = null
	_zoom_button = null
	_energy_rows.clear()
	_prio_labels.clear()
	_mode_buttons.clear()
	_build_buttons.clear()
	_mode = Mode.BUILD
	_build_type = "extractor"
	# 選取要跟著局一起歸零。**`_sel_wire` 存的是 id，而新的一局的 id 從頭發**——
	# 不清的話重開一關會看到面板指著一條玩家沒選過的線（B3.7）。
	_selected = Vector2i(-1, -1)
	_sel_wire = -1
	s = SessionState.new()
	_setup_session()
	_accum = 0.0
	_message = ""
	_build_ui()


func _refresh_hint() -> void:
	# ⚠ **UI 還沒建完就可能被呼叫**（B3.7.1）：`_build_ui()` 裡設建造鈕的
	#   `button_pressed = true` 會當場送出 `toggled`，而那時提示列還沒建出來。
	#   少了這道守衛的症狀不是報錯，是 `_build_ui()` **從那一行起整支中止**
	#   ——半個畫面沒建出來，而畫面自己不會抱怨（RG-164 的形狀）。
	if _hint == null:
		return
	if Hooks.naked:
		_hint.visible = false
		return
	# ★ 兩行：**上行永遠是「下一步」，下行才是當下這個動作的細節。**
	# B0.7 原本讓預覽「取代」下一步，於是玩家把滑鼠移到地圖上——正是最需要
	# 指引的那一刻——指引就消失了。使用者實玩後的第一句話是「你沒教我怎麼操作」。
	var parts: Array[String] = []
	# 拖曳中就只講這一條線連不連得成——這時玩家問的問題只有那一個。
	if _drag_from.x >= 0:
		_hint.text = "▶ %s\n%s" % [
			"放開在另一個節點上就拉出一條導管；放開在空地／原地則取消。",
			_connect_hint() if _in_map(_hover) else "",
		]
		return
	match _mode:
		Mode.BUILD:
			# ★ 游標壓在導管上時，落點提示是**錯的**——點下去不會蓋東西（B3.7）。
			#   順便把逃生門講出來：想在這一格蓋，就避開線，往格子邊緣點。
			if _bp_index < 0 and s.conduit_near(_hover_p, WIRE_PICK) >= 0:
				parts.append("這條導管：左鍵點一下就檢視它，面板上可以加粗或拆除。想在這一格蓋東西，避開線往格子邊緣點。")
			elif _build_type == "" and _bp_index < 0:
				# ★ B3.7.1：手上什麼都沒拿。**要講得出「現在能做什麼」**，
				#   不然這個狀態讀起來會像「怎麼點都沒反應」。
				parts.append("目前沒有拿著任何節點。左鍵點一座建築或一條導管＝檢視它，面板上就能升級、加粗或拆除。要蓋東西就在左欄點一種。")
			elif _in_map(_hover):
				parts.append_array(BuildController.preview_place(s, _build_type, _hover)["lines"])
			else:
				parts.append("建造 %s：左鍵點一格放下；從既有節點按住拖到另一個節點＝拉導管。" % NodeDefs.label(_build_type))
	if _message != "":
		parts.append(_message)
	_hint.text = "▶ %s\n%s" % [_next_step(), "　".join(parts)]


## ★ 下一步（`50_QA_PLAN.md` §4.4「新玩家開局後 15 秒內知道要做什麼嗎」）。
##
## 這**不是教學系統**，是一句讀當前狀態算出來的話——沒有進度旗標、沒有步驟機、
## 不持久化，玩家拆光重蓋它就跟著退回去。做成教學系統的話它會變成第二套要維護的
## 狀態，而且擋在玩家和遊戲之間；一行提示不會。
##
## 順序＝這張圖真正的依賴鏈：礦→入帳→電→塔→接電。
##
## **每一條都要講出「按哪裡、點哪裡」，不能只講目標。** 使用者實玩 B0.7 的第一句
## 回饋是「你沒教我要怎麼操作」——那時這些字串寫的是「先蓋一台採集器」，
## 而畫面上沒有任何地方說過「蓋」＝左欄選一種、再左鍵點地圖。
## 一句只說目標不說動作的提示，對已經會玩的人是提醒，對新玩家是零。
func _next_step() -> String:
	if s.count_of("extractor") == 0:
		return "左欄點「採集器」→ 左鍵點地圖上任一個青色空心圓（礦點）。這是所有東西的源頭。"
	if float(s.rates["ore_in"]) <= 0.0:
		return "礦砂要「送達核心」才入帳：從採集器按住左鍵，拖到下一個節點放開，一路接到右下角的核心。"
	if s.count_of("generator") == 0:
		return "有礦砂了（看頂欄 ▲/秒）。左欄點「發電機」蓋一台，再從採集器拖一條線給它：4 礦砂/秒 → 20 能量/秒。"
	if _towers() == 0:
		return "電有了。左欄點「錨」（最便宜的塔）蓋在「離紫色路徑 2 格以上」的地方。貼太近會被走過的敵人打壞。"
	if _unpowered_tower():
		return "那座塔還沒接進電網，交戰時一發都打不出：從那座塔按住拖到發電機那一側的節點。"
	# 合金是第三資源，但它排在「防線先站得住」之後才提——B0.7 的教訓是
	# 提示列一次只能給一件事做，塞第二條路線只會讓玩家兩件都不做。
	#
	# ★ **這一關沒解鎖熔爐就不准提它**（B1.2）：叫人去點一顆畫面上不存在的鈕，
	#   比不給提示更糟——玩家會以為是自己看漏了，然後花掉整個準備期在找。
	if _buildable().has("smelter") and s.count_of("smelter") == 0 and s.alloy <= 0.0:
		return "防線站住了。想加粗幹線到 2 級以上%s，都要合金：左欄點「熔爐」，它吃 8 礦砂/秒 ＋ 10 能量/秒，產 2 合金/秒。" % (
			"、或蓋「碎浪」" if _buildable().has("breaker") else ""
		)
	if s.count_of("smelter") > 0 and float(s.rates["alloy_in"]) <= 0.0:
		return "熔爐產的合金也要「送達核心」才入帳：從熔爐拖一條線出去，一路接到核心；同時它的礦砂與電也都要接得到。"
	if s.phase == "prep":
		return "都齊了。等倒數跑完自動開波，或按「提前召喚」提早開。倒數剩越多，這一波掉落倍率越高。"
	return "波次進行中：盯著頂端能量條，橙色那截就是餵不飽的部分；節點上的橙色倒三角＝這個缺料。"


## 連線預覽的逐格回報。**連不成的時候要說出差在哪**——「不是 45°」對玩家
## 沒有動作可做，「橫 4 直 3，要 4/4 或 3/3」才有。
func _connect_hint() -> String:
	if s.node_at(_hover).is_empty():
		return "終點也要是一個節點（先在那裡蓋一個「中繼」）。"
	var cf := _drag_from
	var code: String = Build.can_connect(
		s.sets, s.conduit_keys(), cf, _hover, s.conduit_cells()
	)
	if code == Build.NOT_STRAIGHT:
		var d: Vector2i = _hover - cf
		return "✕ 不是直線：橫 %d 直 %d。要走 45° 兩邊得一樣長；否則先放一個「中繼」轉彎。" % [
			absi(d.x), absi(d.y)
		]
	if code != Build.OK:
		return "✕ " + BuildController.reason_text(code)
	var cost := Build.conduit_cost(cf, _hover)
	var afford := "" if s.ore >= float(cost) else "　（礦砂不夠）"
	return "✔ 可連：%s → %s，%d 礦砂%s" % [
		_label_at(cf), _label_at(_hover), cost, afford
	]


func _towers() -> int:
	var n := 0
	for node: Dictionary in s.nodes:
		if NodeDefs.of(String(node["type"])).get("tower", false):
			n += 1
	return n


## 有沒有塔完全沒接上任何導管？（接了但電不夠是另一回事，那由三態徽章講。）
func _unpowered_tower() -> bool:
	for node: Dictionary in s.nodes:
		if not NodeDefs.of(String(node["type"])).get("tower", false):
			continue
		var wired := false
		for c: Dictionary in s.conduits:
			if c["a"] == node["cell"] or c["b"] == node["cell"]:
				wired = true
				break
		if not wired:
			return true
	return false


# ── 截圖用的示範佈局（只在 TL_PANEL=battle 時建立）─────────────────────
#
# 指令表在 `data/Maps.gd`，與 `TL_SIM` 的 headless 跑局共用同一份——
# 截圖與數字看的必須是同一個局面。
func _demo_layout() -> void:
	# ★ 戰役關卡用它自己的參考解（`data/Campaign.gd`），與 `campaign_test`
	#   跑的是同一份腳本——**截圖與那支測試印出來的數字保證是同一個局面**。
	#   `TL_DEMO_TICKS` 給得夠大就會跑到局末，星等面板才拍得到。
	if not level.is_empty():
		var step := func(st: RefCounted) -> void: BattleController.step(st)
		for f: Dictionary in BuildController.apply_timeline(s, level["demo"], step):
			push_warning("參考解第 %d 步失敗：%s" % [f["index"], f["reason"]])
		for _i in Hooks.demo_ticks:
			BattleController.step(s)
		return

	var sandbox: bool = Hooks.panel == "sandbox"
	# 沙盤的佈局全部是純礦砂造價（沒有加粗），所以那邊不發合金——
	# **合金要從畫面上那座熔爐煉出來，那正是那張圖要證明的事。**
	s.alloy = 0.0 if sandbox else MapsData.DEMO_ALLOY
	var failures := BuildController.apply_ops(
		s, MapsData.SANDBOX_DEMO if sandbox else MapsData.SHOAL_DEMO
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
		BattleController.step(s)
