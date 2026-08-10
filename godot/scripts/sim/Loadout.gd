extends RefCounted
## 一局帶進去的**局外成長**（`10_GDD.md` §1 B2、§3.10；B2.7.1）。純函式、零副作用。
##
## ── 為什麼要有這個 module ──────────────────────────────────────────
## `SessionState.setup()` 原本是「一個成長軸一個位置參數」：
## `setup(map, unlocked, tech)` → B2.7 加等級軸變成四個 → B2.6 的難度層會是第五個。
## 而它旁邊那道憲法閘（B3：統一配置榜與玩家的任何進度與課金完全無關）
## 也跟著一軸一道：`Daily.tech_for()`、`Daily.levels_for()`、`Daily.difficulty_for()`…
##
## **那道閘於是變成「靠列舉守住」的東西，而漏掉一道不會有任何東西報錯**——
## 一條可以課金加速的軸就這樣洩進統一榜。同一個形狀本案已經踩過兩次：
## RG-142（以 type 為鍵的表，`match` 沒對到就靜靜地什麼都不做）與
## RG-149（「全部在畫面內」的斷言只列舉了鈕）。第三次踩到的會是憲法。
##
## 所以這裡把「這一局帶進去的全部局外成長」收成**一個字典**：
##   · `SessionState.setup()` 的參數不再隨軸數成長
##   · `Daily.meta_for()` 是**一道閘**，不是一軸一道
##   · 測試可以**列舉 `of()` 的每一個鍵**，斷言它在統一榜上全被歸零
##     ——B2.6 加難度層時忘記處理它，那條斷言會自己變紅
##
## ⚠ **建造欄（`unlocked`）不在這裡**：統一配置榜給的不是「空的」而是一份
##    明列的固定清單（`Daily.UNIFORM_BUILD`），規則和這裡的「一律歸零」不同。

const Levels := preload("res://data/Levels.gd")

## ★ 這一份字典有哪些鍵。**測試列舉的就是它**——新增一軸要同時加在這裡，
## 而忘記加的下場是它根本進不了局，那是**吵的**（功能沒生效），
## 不是安靜的（洩進統一榜）。兩種漏法之中，這一種是安全的那一種。
const KEYS: Array[String] = ["tech", "levels", "difficulty"]

## 什麼成長都沒有。`SessionState.setup()` 的預設值，也是統一配置榜拿到的東西。
const NEUTRAL := {}


## 存檔 → 這一局帶進去的局外成長。
##
## ★ `difficulty` 不在存檔裡（B2.6）：它是**這一局的選擇**，由難度層選擇畫面
## 傳進來。放進 loadout 而不是自成一個參數，是為了讓憲法 B3 那道閘仍然只有一道
## ——統一配置榜恆為第 0 層，而那是 `Daily.meta_for()` 已經在做的事。
static func of(save: Dictionary, difficulty: int = 0) -> Dictionary:
	return {
		"tech": (save.get("tech", {}) as Dictionary).get("unlocked", []),
		"levels": save.get("levels", {}),
		"difficulty": difficulty,
	}


## 已解鎖的科技（`Tech.mods()` 吃的那個陣列）。
static func tech_of(meta: Dictionary) -> Array:
	return meta.get("tech", [])


## 等級軸那一格（`Levels.apply()` 吃的那個字典）。
static func levels_of(meta: Dictionary) -> Dictionary:
	return meta.get("levels", {})


## 難度層那一格（`Difficulty.apply()` 吃的那個數）。**沒有就是第 0 層。**
static func difficulty_of(meta: Dictionary) -> int:
	return int(meta.get("difficulty", 0))


## 這一份 loadout 是不是完全中性（沒有任何局外成長）。
##
## **問的是每一個鍵**，不是 `is_empty()`：`{"tech": [], "levels": {}}` 也該算中性，
## 而它不是空字典。日後加一軸只要在 `KEYS` 加一個名字，這一支自動涵蓋它。
static func is_neutral(meta: Dictionary) -> bool:
	for key: String in KEYS:
		var v: Variant = meta.get(key, null)
		if v == null:
			continue
		if v is Array and not (v as Array).is_empty():
			return false
		if v is Dictionary and not (v as Dictionary).is_empty():
			return false
		# ★ 純量軸（難度層，B2.6）。少了這一條，`{"difficulty": 3}` 會被判成中性
		#   ——而這支函式唯一的工作就是回答「統一配置榜上這份 loadout 乾淨嗎」。
		if typeof(v) == TYPE_INT and int(v) != 0:
			return false
		if typeof(v) == TYPE_FLOAT and not is_zero_approx(float(v)):
			return false
	return true
