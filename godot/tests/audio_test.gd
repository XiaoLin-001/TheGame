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
	"prod_flow", "enemy_hit", "warn_power", "core_hit",
	"ui_click", "ui_back", "ui_unlock",
]

## 會循環播放的檔案。它們的接點是硬性條件，一次性音效沒有這個問題。
const LOOPING := [
	BGM_DIR + "tl_bgm_battle_base.wav",
	BGM_DIR + "tl_bgm_battle_perc.wav",
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
	quit(t.report())


func _paths() -> Array[String]:
	var out: Array[String] = []
	for key: String in SFX_KEYS:
		out.append(SFX_DIR + "tl_sfx_%s.wav" % key)
	# ★ 每一座塔一個開火音（§5.1「各角色開火音，可辨識」）。清單從資料表推導，
	#   不手抄——手抄的那一份會在加第六座塔的那一天悄悄過關。
	for type: String in NodeDefs.BUILDABLE:
		if bool(NodeDefs.of(type).get("tower", false)):
			out.append(SFX_DIR + "tl_sfx_fire_%s.wav" % type)
	for name: String in ["tl_bgm_battle_base", "tl_bgm_battle_perc", "tl_bgm_menu"]:
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


## ★ 兩層 BGM 同長度。它們是同時起跑、各自循環的兩個播放器——
## 差一個取樣，跑一分鐘就差 60 個，節拍會慢慢地錯開而沒有人說得出哪裡怪。
func _bgm_layers_align(t: T) -> void:
	var base := _frames(_wav(BGM_DIR + "tl_bgm_battle_base.wav"))
	var perc := _frames(_wav(BGM_DIR + "tl_bgm_battle_perc.wav"))
	var menu := _frames(_wav(BGM_DIR + "tl_bgm_menu.wav"))
	t.eq(perc, base, "戰鬥層與底層同長度（無縫切層的前提）")
	t.eq(menu, base, "選單曲同長度（同 BPM 同調性，§5.1）")
	t.eq(base, 16 * RATE, "BGM 一個循環 16.0 秒（90 BPM × 24 拍）")


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
