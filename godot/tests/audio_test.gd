extends SceneTree
## 音訊（`20_ART_DIRECTION.md` §5；B1.5）。
##
## 這支測試**不播任何聲音**——它問的是「音源本身有沒有滿足設計條件」，
## 那幾個條件在耳朵上是「怪怪的」，在資料上卻是可以直接量的：
##   ① 每一個程式碼會去要的檔案都真的存在（含**每一座塔各自的開火音**，
##      清單從 `NodeDefs` 推導 → 日後多一座塔沒配音會在這裡失敗，不是上線才發現）。
##   ② 三首 BGM **同長度**。戰鬥層是疊上去的，長度一差就會漸漸走音（§5.1 無縫接軌）。
##   ③ ★ **循環接點不爆音**：會 loop 的檔案，最後一個取樣與第一個取樣要接得上。
##      這正是「切層無爆音」在資料上的樣子，也是耳朵最容易漏掉、量起來最便宜的一項。
##   ④ 沒有削頂、沒有全靜音的檔案。
##
## 跑法：<godot> --headless --path godot --script res://tests/audio_test.gd

const T := preload("res://tests/_assert.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const RATE := 22050

## 與塔無關的音效鍵（塔的那幾個由 `NodeDefs` 推）。
const SFX_KEYS := [
	"build_place", "build_wire", "build_destroyed",
	"prod_flow", "enemy_hit", "warn_power", "core_hit", "wave_start",
	"ui_click", "ui_back", "ui_unlock",
]

## 會循環播放的檔案。它們的接點是硬性條件，一次性音效沒有這個問題。
const LOOPING := [
	BGM_DIR + "tl_bgm_battle_base.wav",
	BGM_DIR + "tl_bgm_menu.wav",
	SFX_DIR + "tl_sfx_prod_flow.wav",
]


func _initialize() -> void:
	var t := T.new("audio_test")
	_files_exist(t)
	_format(t)
	_bgm_layers_align(t)
	_loops_are_seamless(t)
	_levels(t)
	_sting_is_not_a_hit(t)
	quit(t.report())


func _paths() -> Array[String]:
	var out: Array[String] = []
	for key: String in SFX_KEYS:
		out.append(SFX_DIR + "tl_sfx_%s.wav" % key)
	# ★ 每一座**會開火的**塔一個開火音（§5.1「各角色開火音，可辨識」）。
	#   清單從資料表推導，不手抄——手抄的那一份會在加第六座塔的那一天悄悄過關。
	#
	# ⚠ 篩選條件是 `tower and rof > 0`，**不是只看 `tower`**（B1.8）。
	#   潮鳴的 `rof` 是 0：`BattleController._fire()` 直接跳過它 → 它永遠不產生
	#   開火線 → `Battle._audio_tick()` 永遠推導不出 `fire_knell`。
	#   舊的判準只看 `tower`，於是這支測試**要求一個永遠播不到的 wav 存在**，
	#   那個檔案就一路過關、一路被打包，還被改過一次音色（B1.5.1）。
	#
	#   **這是「斷言存在性」與「斷言可達性」的差別**：檢查資產在不在的測試，
	#   永遠抓不到「這個資產從來沒被播過」。潮鳴的回饋改走視覺（§1.6）。
	for type: String in NodeDefs.BUILDABLE:
		var def := NodeDefs.of(type)
		if bool(def.get("tower", false)) and float(def.get("rof", 0.0)) > 0.0:
			out.append(SFX_DIR + "tl_sfx_fire_%s.wav" % type)
	for name: String in ["tl_bgm_battle_base", "tl_bgm_menu"]:
		out.append(BGM_DIR + name + ".wav")
	return out


func _files_exist(t: T) -> void:
	for path: String in _paths():
		t.ok(ResourceLoader.exists(path), "音源存在　%s" % path.get_file())


func _wav(path: String) -> AudioStreamWAV:
	return load(path) as AudioStreamWAV


## ⚠ `w.data` 是**屬性**，每讀一次就複製一整份 PackedByteArray（BGM 是 700KB）。
## 第一版把它寫在取樣迴圈裡，於是 5 萬次迴圈複製了 35GB，測試看起來像當掉了。
## 一律先取出來放進區域變數再索引。
func _frames(w: AudioStreamWAV) -> int:
	var per := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if w.stereo:
		per *= 2
	return w.data.size() / per


## 全部 16-bit 單聲道 22.05kHz。**不是為了省空間才統一**——`AudioBus` 算
## 循環點時要除以「每一格幾個位元組」，格式一混，那個除法就會算出半個取樣。
func _format(t: T) -> void:
	for path: String in _paths():
		var w := _wav(path)
		if w == null:
			t.ok(false, "讀不到 %s" % path.get_file())
			continue
		t.eq(w.format, AudioStreamWAV.FORMAT_16_BITS, "16-bit　%s" % path.get_file())
		t.ok(not w.stereo, "單聲道　%s" % path.get_file())
		t.eq(w.mix_rate, RATE, "取樣率　%s" % path.get_file())
		t.ok(_frames(w) > 0, "非空檔　%s" % path.get_file())


## 兩首 BGM 同長度、同 BPM、同調性（§5.1）。
##
## ★ B2.1f 刪掉了第三首（戰鬥打擊層 `tl_bgm_battle_perc`）——戰鬥期沒有音樂了。
##   所以這裡也**斷言它不存在**：留著一個沒人播的 wav 會一路被打包、被改音色、
##   再被誤以為還在用（潮鳴的開火音就這樣活過一整批，見 `_paths()` 的註解）。
func _bgm_layers_align(t: T) -> void:
	var base := _frames(_wav(BGM_DIR + "tl_bgm_battle_base.wav"))
	var menu := _frames(_wav(BGM_DIR + "tl_bgm_menu.wav"))
	t.eq(menu, base, "選單曲與準備期曲同長度（同 BPM 同調性，§5.1）")
	t.eq(base, 16 * RATE, "BGM 一個循環 16.0 秒（90 BPM × 24 拍）")
	t.ok(
		not ResourceLoader.exists(BGM_DIR + "tl_bgm_battle_perc.wav"),
		"★ 戰鬥打擊層已刪除（B2.1f：戰鬥期沒有音樂）"
	)


## ★ 號令**不能是一個打擊音**（B2.1f）。
##
## 使用者砍掉戰鬥曲的理由是它有「一個敲擊聲，意義不明且會與其他東西誤會」。
## 那顆敲擊的問題不是音色難聽，是它**在物理上就是一個前景瞬態**——
## 耳朵把瞬態一律歸類成「剛剛發生了一件事」，然後去找那件事。
## 這款遊戲的音訊是診斷通道，所以一個不對應任何事件的瞬態＝訓練假警報。
##
## 取代它的號令必須走反方向：**起音慢**。這是可以直接量的——
## 從開頭到第一次達到峰值 90% 要花幾個取樣。
## 量的是**到達滿音量要多久**（第一次觸及峰值 90%）。打擊類全部在 10 ms 以內，
## 號令實測 411 ms（三個音疊上來才滿）。門檻訂 100 ms——從實測退一大步，
## 照實測填會讓之後任何一次音色微調都假紅，但 100 ms 已經是「絕不可能被聽成
## 一記敲擊」的區間，還是驗得到東西。
func _sting_is_not_a_hit(t: T) -> void:
	const SLOW_MS := 100.0
	const FAST_MS := 12.0
	var sting := _attack_ms(SFX_DIR + "tl_sfx_wave_start.wav")
	t.ok(
		sting >= SLOW_MS,
		"★ 開打號令是宣告不是打擊：滿音量要 %.0f ms ≥ %.0f" % [sting, SLOW_MS]
	)
	# 對照組：打擊類的必須是快的。少了這一半，上面那條可以靠「把全部音效都
	# 做成慢起音」通過——那是把問題搬走，不是解決。
	for key: String in ["build_place", "build_wire", "enemy_hit", "fire_anchor"]:
		var ms := _attack_ms(SFX_DIR + "tl_sfx_%s.wav" % key)
		t.ok(ms <= FAST_MS, "打擊類仍是瞬態　%s（滿音量 %.0f ms ≤ %.0f）" % [key, ms, FAST_MS])
	t.ok(
		sting > _attack_ms(SFX_DIR + "tl_sfx_core_hit.wav") * 3.0,
		"★ 號令比全場最醒目的那個打擊音（核心受擊）慢三倍以上才滿"
	)


## 到達滿音量的時間：從第一個取樣到**第一次**觸及峰值 90% 的毫秒數。
func _attack_ms(path: String) -> float:
	var d := _wav(path).data
	var n := d.size() / 2
	var peak := 0
	for i in n:
		peak = maxi(peak, absi(d.decode_s16(i * 2)))
	var target := int(float(peak) * 0.9)
	for i in n:
		if absi(d.decode_s16(i * 2)) >= target:
			return float(i) * 1000.0 / float(RATE)
	return 0.0


## ★ 循環接點不爆音。
##
## ⚠ **不能拿「接點的跳幅」去比一個固定門檻**。第一版就是這樣寫的，結果 330Hz
## 的鋪底音自己每一個取樣就跳 6%——那不是爆音，那只是一條正常的正弦。
## 真正會「啪」一聲的是**接點的跳幅遠大於它附近的跳幅**，所以門檻要自己校準：
## 拿接點兩側各 128 個取樣的平均步幅當基準，接點不得超過它的 4 倍。
func _loops_are_seamless(t: T) -> void:
	for path: String in LOOPING:
		var d := _wav(path).data
		var n := d.size() / 2
		var seam: int = absi(d.decode_s16(0) - d.decode_s16((n - 1) * 2))
		var total := 0
		for i in 128:
			total += absi(d.decode_s16((i + 1) * 2) - d.decode_s16(i * 2))
			total += absi(d.decode_s16((n - 1 - i) * 2) - d.decode_s16((n - 2 - i) * 2))
		var local := maxf(float(total) / 256.0, 50.0)
		t.ok(
			float(seam) <= local * 4.0,
			"循環接點不爆音　%s（接點跳幅 %d，鄰近平均 %.0f）" % [path.get_file(), seam, local]
		)


## 沒有削頂（近滿刻度的取樣會方波化 → 破音），也沒有整支靜音的檔案。
func _levels(t: T) -> void:
	for path: String in _paths():
		var d := _wav(path).data
		var peak := 0
		# 每 7 個取樣看一個。峰值是連續的，抽樣不會漏掉削頂那一段，
		# 但 18 個檔案全掃會讓這支測試變成最慢的一支。
		var i := 0
		while i < d.size() - 1:
			peak = maxi(peak, absi(d.decode_s16(i)))
			i += 14
		t.ok(peak > 3000, "不是靜音檔　%s（峰值 %d）" % [path.get_file(), peak])
		t.ok(peak < 32400, "沒有削頂　%s（峰值 %d）" % [path.get_file(), peak])
