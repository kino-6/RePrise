class_name ExploreView
extends Node2D

## ダンジョン探索画面。タイル単位で歩き、階段で next floor、宝箱で金貨。

signal encounter_triggered
signal descended
signal boss_reached
signal shop_entered
signal chest_opened(amount: int)
signal menu_requested
## 主の間の扉が隣にある。踏む前に知らせるためのもの。
signal door_nearby
## 1 歩あるいた。毒の進行はここで解決する（歩数で削るのが DQ の作法）。
signal poison_ticked

const TILE := 16
const MOVE_DELAY := 0.10
## この歩数までは絶対に敵が出ない（階段直後の事故防止）。
## 自動プレイで 150 秒回したら遊んだ時間の 54% が戦闘だったので広げた。
## 1 階を歩き切るのに 80 歩ほどかかるので、18 歩に 1 回で 4〜5 戦になる。
const MIN_SAFE_STEPS := 9

const TILES_TEX: Texture2D = preload("res://assets/tiles/dungeon.png")

## 階ごとの地形。素材が無い場所は既定（dungeon）に落ちる。
static var _tilesets: Dictionary = {}


static func tileset_for(biome: String) -> Texture2D:
	if _tilesets.has(biome):
		return _tilesets[biome]
	var path := "res://assets/tiles/%s.png" % biome
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else TILES_TEX
	_tilesets[biome] = tex
	return tex

## キャラは 16x16 のタイルより大きい。足元をタイルに合わせ、頭は上へはみ出させる。
const CHAR_W := 24
const CHAR_H := 32
const CHAR_OFFSET := Vector2(-4, -16)

# hero.png の行の並び
enum { FACE_DOWN, FACE_LEFT, FACE_RIGHT, FACE_UP }

var map: DungeonMap = null
var player_pos := Vector2i.ZERO
var facing := FACE_DOWN
var rng: DetRng = null
var hero_tex: Texture2D = null

var _frame := 0
var _move_cd := 0.0
var _steps_since_encounter := 0
var _active := true


## leader_job は先頭キャラの職業。職業ごとに差し色の違うスプライトがある。
func setup(dungeon: DungeonMap, encounter_rng: DetRng, leader_job: String = "soldier") -> void:
	map = dungeon
	rng = encounter_rng
	hero_tex = _load_hero(leader_job)
	player_pos = dungeon.start_pos
	facing = FACE_DOWN
	_frame = 0
	_steps_since_encounter = 0
	_update_camera()
	queue_redraw()


## 探索へ戻った直後に決定キーを拾わないための待ち時間。
##
## メニューを「とじる」で閉じると、その同じキーを探索側が拾って
## メニューを開き直していた。**閉じられない**ように見えるが、実際は
## 閉じて即座に開いている。UI をまたぐ入力は必ず一拍おく。
const RESUME_LOCK := 0.18

var _resume_lock := 0.0


func set_active(value: bool) -> void:
	_active = value
	set_process(value)
	if value:
		_resume_lock = RESUME_LOCK


func _process(delta: float) -> void:
	if not _active or map == null:
		return
	_move_cd -= delta
	if _resume_lock > 0.0:
		_resume_lock -= delta
	if _move_cd > 0.0:
		return

	# 決定キーでメニュー。DQ と同じ作法で、道具・つよさ・そうびはここから触る。
	if _resume_lock <= 0.0 and Input.is_action_just_pressed("confirm"):
		Sound.play("confirm")
		menu_requested.emit()
		return

	var dir := Vector2i.ZERO
	if Input.is_action_pressed("ui_left"):
		dir = Vector2i.LEFT
	elif Input.is_action_pressed("ui_right"):
		dir = Vector2i.RIGHT
	elif Input.is_action_pressed("ui_up"):
		dir = Vector2i.UP
	elif Input.is_action_pressed("ui_down"):
		dir = Vector2i.DOWN
	if dir == Vector2i.ZERO:
		return

	facing = _facing_for(dir)
	_move_cd = MOVE_DELAY
	_try_move(player_pos + dir)


## 開発用。目的地へ向かう次の一歩を入力アクション名で返す。
## 自動プレイが階段まで歩くのに使う（src/dev/autoplay.gd）。
func dev_step_toward(target: Vector2i) -> String:
	if map == null:
		return ""
	var path := map.route(player_pos, target)
	if path.is_empty():
		return ""
	var step: Vector2i = path[0] - player_pos
	if step == Vector2i.UP:
		return "ui_up"
	if step == Vector2i.DOWN:
		return "ui_down"
	if step == Vector2i.LEFT:
		return "ui_left"
	return "ui_right"


func _facing_for(dir: Vector2i) -> int:
	if dir == Vector2i.LEFT:
		return FACE_LEFT
	if dir == Vector2i.RIGHT:
		return FACE_RIGHT
	if dir == Vector2i.UP:
		return FACE_UP
	return FACE_DOWN


func _try_move(target: Vector2i) -> void:
	var tile := map.get_tile(target.x, target.y)

	# 宝箱は「押し当てて開ける」。マスには乗らない。
	if tile == DungeonMap.T_CHEST:
		map.set_tile(target.x, target.y, DungeonMap.T_FLOOR)
		map.chests.erase(target)
		queue_redraw()
		chest_opened.emit(rng.range_i(8, 30))
		return


	if not map.is_walkable(target.x, target.y):
		queue_redraw()  # 向きだけ変える
		return

	player_pos = target
	_frame = (_frame + 1) % 3
	_steps_since_encounter += 1
	_update_camera()
	queue_redraw()

	if tile == DungeonMap.T_STAIRS:
		descended.emit()
		return

	# 最終階の出口は下りではなく主の間。踏んだ時点でボス戦に入る。
	if tile == DungeonMap.T_DOOR:
		boss_reached.emit()
		return

	# 主の間が隣にあるなら知らせる。扉は地形に紛れるので、
	# 気づかないまま踏んで開幕から不利、という事故が起きる。
	for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if map.get_tile(player_pos.x + step.x, player_pos.y + step.y) == DungeonMap.T_DOOR:
			door_nearby.emit()
			break

	# 出店は踏んで入る。踏み直せば何度でも入れる（立っている間は開かない）。
	if tile == DungeonMap.T_SHOP:
		shop_entered.emit()
		return

	poison_ticked.emit()

	if _should_encounter():
		_steps_since_encounter = 0
		encounter_triggered.emit()


## 歩くほど出やすくなる。連戦が続いて詰まないよう下限歩数を設ける。
##
## 確率は歩数の半分ずつ上がる。線形に上げると 10 歩そこそこで必ず出るようになり、
## 探索が戦闘の待ち時間になってしまう（実際そうなっていた）。
func _should_encounter() -> bool:
	if _steps_since_encounter < MIN_SAFE_STEPS:
		return false
	@warning_ignore("integer_division")
	var odds := 3 + _steps_since_encounter / 2
	return rng.chance(odds)


func _update_camera() -> void:
	var focus := Vector2(player_pos * TILE) + Vector2(TILE, TILE) * 0.5
	var cam := focus - Vector2(PixelUI.SCREEN) * 0.5
	var limit := Vector2(map.width * TILE, map.height * TILE) - Vector2(PixelUI.SCREEN)
	cam.x = clampf(cam.x, 0.0, maxf(limit.x, 0.0))
	cam.y = clampf(cam.y, 0.0, maxf(limit.y, 0.0))
	position = -cam.floor()


func _draw() -> void:
	if map == null:
		return

	# 画面に映る範囲だけ描く
	var origin := (-position / TILE).floor()
	var span := Vector2(PixelUI.SCREEN) / TILE + Vector2(2, 2)

	for y in range(int(origin.y), int(origin.y + span.y)):
		for x in range(int(origin.x), int(origin.x + span.x)):
			if not map.in_bounds(x, y):
				continue
			var t := map.render_tile(x, y)
			if t == DungeonMap.T_VOID:
				continue
			draw_texture_rect_region(
				tileset_for(map.biome),
				Rect2(x * TILE, y * TILE, TILE, TILE),
				Rect2(t * TILE, 0, TILE, TILE)
			)

	if hero_tex == null:
		return
	var at := Vector2(player_pos * TILE) + CHAR_OFFSET
	draw_texture_rect_region(
		hero_tex,
		Rect2(at.x, at.y, CHAR_W, CHAR_H),
		Rect2(_frame * CHAR_W, facing * CHAR_H, CHAR_W, CHAR_H)
	)


func _load_hero(job: String) -> Texture2D:
	var path := "res://assets/sprites/hero_%s.png" % job
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/hero_soldier.png"
	return load(path)
