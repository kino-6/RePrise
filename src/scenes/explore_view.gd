class_name ExploreView
extends Node2D

## ダンジョン探索画面。タイル単位で歩き、階段で next floor、宝箱で金貨。

signal encounter_triggered
signal descended
signal boss_reached
signal shop_entered
signal chest_opened(amount: int)
signal menu_requested

const TILE := 16
const MOVE_DELAY := 0.10
const MIN_SAFE_STEPS := 5  ## この歩数までは絶対に敵が出ない（階段直後の事故防止）

const TILES_TEX: Texture2D = preload("res://assets/tiles/dungeon.png")

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


func set_active(value: bool) -> void:
	_active = value
	set_process(value)


func _process(delta: float) -> void:
	if not _active or map == null:
		return
	_move_cd -= delta
	if _move_cd > 0.0:
		return

	# 決定キーでメニュー。DQ と同じ作法で、道具・つよさ・そうびはここから触る。
	if Input.is_action_just_pressed("confirm"):
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

	# 出店は踏んで入る。踏み直せば何度でも入れる（立っている間は開かない）。
	if tile == DungeonMap.T_SHOP:
		shop_entered.emit()
		return

	if _should_encounter():
		_steps_since_encounter = 0
		encounter_triggered.emit()


## 歩くほど出やすくなる。連戦が続いて詰まないよう下限歩数を設ける。
func _should_encounter() -> bool:
	if _steps_since_encounter < MIN_SAFE_STEPS:
		return false
	return rng.chance(4 + _steps_since_encounter)


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
				TILES_TEX,
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
