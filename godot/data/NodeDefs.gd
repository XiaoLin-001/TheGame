extends RefCounted
## 節點資料表（`10_GDD.md` §7.3）。**數值的唯一來源**——不在程式碼裡即興發明。
##
## 不宣告 `class_name`：一律以路徑 `preload`。`--script` 模式（測試）不保證
## global class 可用，而資料表必須連測試都拿得到（`50_QA_PLAN.md` §2）。
##
## 熔爐 Smelter 是 M1（B1.1 第三資源）才進來的，這裡先不列；
## 塔（錨／稜鏡／潮鳴／回收者）是 B0.5，屬於另一張表（§7.4）。

## 資源鍵。解算器一次只解一種（`sim/FlowNetwork.gd`）。
const ORE := "ore"
const POWER := "power"

## 可建造的節點。`core` 不在此列——它由地圖宣告，玩家蓋不出來。
const BUILDABLE := ["extractor", "generator", "relay", "silo"]

const DEFS := {
	"extractor": {
		"name": "採集器",
		"cost": 40,
		"hp": 60.0,
		"ore_out": 6.0,      # 礦砂/秒
		"on_ore_only": true, # 只能蓋在礦點上
	},
	"generator": {
		"name": "發電機",
		"cost": 60,
		"hp": 50.0,
		"ore_in": 4.0,       # 礦砂/秒
		"power_out": 20.0,   # 能量/秒（依礦砂滿足率線性縮放）
	},
	"relay": {
		"name": "中繼",
		"cost": 15,
		"hp": 30.0,
		# 分流／合流／**轉折**。導管只能走 90°/45°，轉彎就靠它（§7.2）。
	},
	"silo": {
		"name": "儲槽",
		"cost": 50,
		"hp": 80.0,
		"capacity": 300.0,   # 能量緩衝
	},
	"core": {
		"name": "核心",
		"cost": 0,
		"hp": 1000.0,
		# 礦砂銀行：demand = max(0, 全網供給 − 其他消費者需求)（§7.3）
	},
}

## 優先權預設值（1–5，依**節點類型**，`10_GDD.md` §3.1）。
## B0.3 還沒有塔，面板要到 B0.5 才拉得動；先給一組會產生正確行為的預設。
const DEFAULT_PRIORITY := {
	"generator": 4,  # 燃料優先於入帳
	"silo": 2,       # 充能搶不贏發電機，這是刻意的
	"core": 1,
	"relay": 1,
	"extractor": 1,
}


static func of(type: String) -> Dictionary:
	return DEFS.get(type, {})


static func label(type: String) -> String:
	return String(of(type).get("name", type))


static func cost(type: String) -> int:
	return int(of(type).get("cost", 0))


static func hp(type: String) -> float:
	return float(of(type).get("hp", 1.0))
