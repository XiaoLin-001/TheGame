extends Node
## 音訊匯流排與全域靜音（autoload）。
##
## 鐵律 2（30_TECH_DESIGN.md §4.1）：TL_SHOT 或 TL_MUTE 存在時自動全域靜音。
## **絕不在沒有測試鉤子的情況下開遊戲視窗做自動化驗證** —— 使用者可能正在工作。
##
## ★ B1.4：三條分軌（Master / BGM / SFX）與音量在這裡落地。
## ★ B1.5：音源與播放也在這裡。音源是 `assetgen/gen_audio.py` 程序生成的
## （`20_ART_DIRECTION.md` §6.1 的同一條理由：授權乾淨、體積可控、改一處全同步）。
##
## **靜音是靠 Master 匯流排的 mute，不是靠「不播」**：有鉤子時播放器照樣跑、
## 照樣被自檢問得到狀態，但一個取樣都送不出去。兩條路（不播／靜音）並存的那天，
## 就會有一條沒被驗到。

## 分軌名稱。BGM 與 SFX 都掛在 Master 底下，所以主音量一動兩邊一起動。
## §5.2 的「UI 70%」那一軌**沒有做**：UI 音走 SFX。理由是第四條滑桿買到的是
## 「點擊聲可以單獨調小」，而那要玩家先意識到有這回事——tycoon 的兩畫面上限
## 是同一種紀律，UI 深度不是免費的。已回頭修 §5.2。
const BUSES := ["BGM", "SFX"]

## 靜音時實際套用的分貝。`-80` 是 Godot 的實質無聲下限。
const SILENT_DB := -80.0

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"

## 同時可疊的音效數。一波裡「開火＋受擊」很容易同幀好幾發，
## 少了會被自己蓋掉；多了只是浪費節點。
const SFX_VOICES := 12

## 準備期音樂淡入／淡出的秒數。**只淡音量、不換曲**（§5.1）。
const LAYER_FADE := 1.2

## 準備期音樂的音量（0..1）。戰鬥期是 0。
const PREP_LEVEL := 0.9

var muted: bool = false

var _cache: Dictionary = {}                     # 路徑 → AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
## `base`／`menu` 兩個常駐播放器。
var _music: Dictionary = {}
## 準備期音樂的目標音量（0..1）。`_process` 每幀往它逼近。
## **戰鬥期是 0**——B2.1f 起戰鬥期完全沒有音樂（見 `battle_hush()`）。
var _music_target: float = PREP_LEVEL
var _music_now: float = 0.0
var _flow: AudioStreamPlayer = null
var _flow_level: float = 0.0
## 累計播了幾次一次性音效。自檢用——「局結束之後還在響嗎」只有這個數字答得出來。
var plays: int = 0


func _ready() -> void:
	_ensure_buses()
	muted = Env.want_mute()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if muted:
		print("[TL] audio muted")
	_build_players()


## 專案裡只宣告了 Master，其餘在執行期補上。
## **寫在程式碼而不是 `default_bus_layout.tres`**：分軌名稱要和 `settings` 的
## 鍵對得起來，而那個對應關係放在同一個檔案裡才不會各改各的。
func _ensure_buses() -> void:
	for name: String in BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")


## 把 `settings` 的三個 0..1 音量套到匯流排上。
##
## ★ **靜音時不寫音量**：測試鉤子在跑的時候把音量寫回去，等於讓一個
## 「絕不出聲」的承諾取決於玩家存檔裡剛好存了什麼（鐵律 2）。
func apply(settings: Dictionary) -> void:
	if muted:
		return
	_set_volume("Master", float(settings.get("master", 0.8)))
	_set_volume("BGM", float(settings.get("bgm", 0.6)))
	_set_volume("SFX", float(settings.get("sfx", 0.8)))


## 0..1 的線性音量 → 分貝。**用 `linear_to_db` 而不是自己乘**：
## 人耳是對數的，線性套上去會讓滑桿的前 20% 什麼都聽不出來、後面又爆掉。
## 0 一律送到 `SILENT_DB`（`linear_to_db(0)` 是 −inf，寫進去會出事）。
func _set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, SILENT_DB if v <= 0.0 else linear_to_db(v))


## 目前的分貝（設定畫面的自檢要能問「這個滑桿真的接到東西了嗎」）。
func volume_db(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return SILENT_DB if i < 0 else AudioServer.get_bus_volume_db(i)


# ── 播放（B1.5）────────────────────────────────────────────────────────

func _build_players() -> void:
	for _i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	_flow = AudioStreamPlayer.new()
	_flow.bus = "SFX"
	_flow.volume_db = SILENT_DB
	add_child(_flow)
	for key: String in ["base", "menu"]:
		var p := AudioStreamPlayer.new()
		p.bus = "BGM"
		p.volume_db = SILENT_DB
		add_child(p)
		_music[key] = p


## 讀一個音檔並**把它設成循環**。
##
## Godot 的 WAV 匯入器預設不循環，而循環點寫在 `.import` 裡就等於把一個
## 「這首歌要接得起來」的硬性設計條件藏在一個會被 `--import` 重新生成的檔案裡。
## 寫在程式碼這一側，改音源不會把它弄丟。
func _stream(path: String, looped: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("音源不存在：%s（跑 `python assetgen/gen_audio.py`）" % path)
		return null
	var st: AudioStream = load(path)
	var w := st as AudioStreamWAV
	if looped and w != null:
		var bytes_per_frame := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if w.stereo:
			bytes_per_frame *= 2
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / bytes_per_frame - 1
	_cache[path] = st
	return st


## 放一個音效。`key` 是檔名去掉 `tl_sfx_` 與副檔名（例：`build_place`）。
## 找不到就只是不出聲並警告一次——**音源缺一個不該讓遊戲當掉**。
func play(key: String, db: float = 0.0) -> void:
	var st := _stream(SFX_DIR + "tl_sfx_%s.wav" % key, false)
	if st == null:
		return
	plays += 1
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = st
	p.volume_db = db
	p.play()


## 換曲。
##
## ★ B2.1f：`"battle"` 只起 `base` 一層，而且**它是準備期的曲子**。
##   戰鬥期沒有音樂——開打時放一次 `wave_start` 的號令，音樂淡出到全靜。
##   舊版還有一層 `perc`（戰鬥打擊層），連同它的「敲玻璃」動機一起刪掉了：
##   那顆敲擊是整首唯一的前景瞬態，而這款遊戲的音訊是**診斷通道**
##   （核心受擊是全場最醒目的音、缺電有警報、生產嗡鳴的音量跟著流量走）。
##   瞬態一律被讀成「剛剛發生了一件事」，而它不對應任何事件。
func music(track: String) -> void:
	for key: String in _music:
		var p: AudioStreamPlayer = _music[key]
		var want: bool = (
			(track == "battle" and key == "base") or (track == "menu" and key == "menu")
		)
		if want and not p.playing:
			p.stream = _stream(BGM_DIR + _bgm_file(key), true)
			if p.stream != null:
				p.play()
		elif not want and p.playing:
			p.stop()
	if track == "menu":
		_music["menu"].volume_db = linear_to_db(PREP_LEVEL)
	_music_target = PREP_LEVEL
	_music_now = PREP_LEVEL
	_music["base"].volume_db = linear_to_db(PREP_LEVEL)


func _bgm_file(key: String) -> String:
	return "tl_bgm_menu.wav" if key == "menu" else "tl_bgm_battle_%s.wav" % key


## 戰鬥期靜音（B2.1f）：`true` ＝ 正在打，音樂淡出到全靜；`false` ＝ 準備期，淡回來。
## 呼叫端每幀丟現況進來也沒關係。
##
## **靜的是音樂，不是全部**：生產嗡鳴（`flow()`）與所有 SFX 照舊——
## 戰鬥期要聽的本來就是那些，音樂只是在跟它們搶。
func battle_hush(on: bool) -> void:
	_music_target = 0.0 if on else PREP_LEVEL


## 生產的低頻循環（§5.1「音量隨總流量微調」）。`level` 是 0..1 的總流量比例。
func flow(level: float) -> void:
	_flow_level = clampf(level, 0.0, 1.0)
	if _flow_level <= 0.01:
		if _flow.playing:
			_flow.stop()
		return
	if not _flow.playing:
		var st := _stream(SFX_DIR + "tl_sfx_prod_flow.wav", true)
		if st == null:
			return
		_flow.stream = st
		_flow.play()
	# 0.15..0.55 的線性音量：它是底噪，不該蓋過任何一個要傳達訊息的音。
	_flow.volume_db = linear_to_db(0.15 + 0.40 * _flow_level)


func _process(delta: float) -> void:
	if _music.is_empty():
		return
	var base: AudioStreamPlayer = _music["base"]
	if is_equal_approx(_music_now, _music_target) and not base.playing:
		return
	var step := delta / LAYER_FADE
	_music_now = move_toward(_music_now, _music_target, step)
	base.volume_db = SILENT_DB if _music_now <= 0.001 else linear_to_db(_music_now)


## 自檢用：準備期音樂此刻的 0..1 音量。**戰鬥期必須是 0**——
## 「戰鬥期沒有音樂」這件事只有這個數字證明得了。
func music_level() -> float:
	return _music_now


func music_playing(key: String) -> bool:
	return _music.has(key) and (_music[key] as AudioStreamPlayer).playing
