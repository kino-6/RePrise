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
const SFX_VOLUME_DB := -5.0

var _bgm: AudioStreamPlayer = null
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _cache: Dictionary = {}
var _current_bgm := ""
var _warned := false


func _ready() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = BGM_VOLUME_DB
	_bgm.bus = "Master"
	add_child(_bgm)

	for _i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_VOLUME_DB
		add_child(player)
		_voices.append(player)


# --------------------------------------------------------------------------


func play_bgm(name: String) -> void:
	if _current_bgm == name and _bgm.playing:
		return
	var stream := _load(BGM_DIR + name + ".wav")
	if stream == null:
		return
	_apply_loop(stream)
	_current_bgm = name
	_bgm.stream = stream
	_bgm.play()


func stop_bgm() -> void:
	_current_bgm = ""
	_bgm.stop()


## 効果音。空いている再生枠を順に使い回す。
func play(name: String) -> void:
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
