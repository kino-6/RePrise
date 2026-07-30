extends Node

## 音の再生（オートロード名: Sound）。
##
## 音声 WAV は容量が大きいのでリポジトリには入れず、tools/gen_audio.py で
## 生成する。つまり「まだ生成していない環境」が普通に存在するので、
## 音が 1 つも無くてもゲームは完全に動くように作る。

const BGM_DIR := "res://assets/audio/bgm/"
const SFX_DIR := "res://assets/audio/sfx/"

## 同時に鳴らせる効果音の数。足りないと打撃音が途切れる。
const SFX_VOICES := 6

const BGM_VOLUME_DB := -9.0
const BGM_SILENT_DB := -42.0
const BGM_FADE_SECONDS := 0.34
const SFX_VOLUME_DB := -5.0

var _bgm_players: Array[AudioStreamPlayer] = []
var _active_bgm := 0
var _bgm_tween: Tween = null
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _cache: Dictionary = {}
var _current_bgm := ""
var _warned := false


## 自動で走らせているときは音を出さない。
##
## **撮影・自動プレイ・headless は「人が見ていない実行」なので鳴らす理由が無い。**
## `check_ui.py` は 23 画面を並列に立てるため、鳴ると 23 個の BGM が
## 同時に鳴って実際にうるさい。音そのものを確かめたいときだけ `--audio` を付ける。
##
##     godot --path . -- --shot=battle            # 無音
##     godot --path . -- --shot=battle --audio    # 鳴らす（音の確認用）
static func _should_mute() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--audio" in args:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	for arg in args:
		if arg.begins_with("--shot=") or arg.begins_with("--play="):
			return true
	return false


var _muted := false


func _ready() -> void:
	_muted = _should_mute()
	for _i in 2:
		var bgm_player := AudioStreamPlayer.new()
		bgm_player.volume_db = BGM_VOLUME_DB
		bgm_player.bus = "Master"
		add_child(bgm_player)
		_bgm_players.append(bgm_player)

	for _i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_VOLUME_DB
		add_child(player)
		_voices.append(player)


# --------------------------------------------------------------------------


func play_bgm(name: String) -> void:
	if _muted:
		return
	var current := _bgm_players[_active_bgm]
	if _current_bgm == name and current.playing:
		return
	var stream := _load(BGM_DIR + name + ".wav")
	if stream == null:
		return
	_apply_loop(stream)
	_current_bgm = name

	if _bgm_tween != null:
		_bgm_tween.kill()
	var previous := current
	_active_bgm = 1 - _active_bgm
	var incoming := _bgm_players[_active_bgm]
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = BGM_SILENT_DB if previous.playing else BGM_VOLUME_DB
	incoming.play()
	if not previous.playing:
		return

	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	_bgm_tween.tween_property(previous, "volume_db", BGM_SILENT_DB, BGM_FADE_SECONDS)
	_bgm_tween.tween_property(incoming, "volume_db", BGM_VOLUME_DB, BGM_FADE_SECONDS)
	_bgm_tween.finished.connect(_finish_bgm_crossfade.bind(previous))


func stop_bgm() -> void:
	_current_bgm = ""
	if _bgm_tween != null:
		_bgm_tween.kill()
	for player in _bgm_players:
		player.stop()
		player.volume_db = BGM_VOLUME_DB


func _finish_bgm_crossfade(previous: AudioStreamPlayer) -> void:
	previous.stop()
	previous.volume_db = BGM_VOLUME_DB
	_bgm_tween = null


## 効果音。空いている再生枠を順に使い回す。
func play(name: String) -> void:
	if _muted:
		return
	var stream := _load(SFX_DIR + name + ".wav")
	if stream == null:
		return
	# 使われていない枠を優先し、無ければ最も古い枠を奪う
	for i in _voices.size():
		var index := (_next_voice + i) % _voices.size()
		if not _voices[index].playing:
			_next_voice = (index + 1) % _voices.size()
			_voices[index].stream = stream
			_voices[index].play()
			return
	_voices[_next_voice].stream = stream
	_voices[_next_voice].play()
	_next_voice = (_next_voice + 1) % _voices.size()


# --------------------------------------------------------------------------


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		if not _warned:
			_warned = true
			push_warning("音声が見つからない。python tools/gen_audio.py で生成できる（無くても動作する）。")
		return null
	var stream: AudioStream = load(path)
	_cache[path] = stream
	return stream


## BGM をループさせる。Godot の wav 取り込みは既定でループしないので、
## 読み込んだ側で指定する（.import を手で書くより壊れにくい）。
func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 4  # 16bit ステレオ = 1 フレーム 4 バイト
