class_name ExploreView
extends Node2D

## 歩く画面。**ワールドでも洞の中でも、これ 1 本を使う。**
##
## ここが持っているのは歩き・カメラ・描画・遭遇判定だけで、地図の中身には
## 依存していない（`FieldMap`）。ワールド用にもう 1 本作ると、
## 片方だけ直したバグが必ず出る。地図の型を揃えて 1 本に保つこと。
##
## 「踏んだら何が起きるか」は地図の種類ごとに違うので、
## タイルを踏んだことだけを signal で外へ出し、判断は main.gd に持たせる。

signal encounter_triggered
signal descended
signal boss_reached
signal shop_entered
signal chest_opened(amount: int)
signal menu_requested
## ワールドで任意イベントのマスを踏んだ。開くかは main.gd が決める
## （一度きりかどうかを知っているのは向こう側）。
signal event_reached(pos: Vector2i)
## ワールドで拠点地（町・洞・城）を踏んだ。中へ入れるかは main.gd が決める。
signal site_entered(pos: Vector2i)
## 町の人に話しかけた。
signal talked(line: String)
## 宿の扉を踏んだ。
signal inn_entered
## 町の出口を踏んだ。
signal town_left
## 主の間の扉が隣にある。踏む前に知らせるためのもの。
signal door_nearby
## 1 歩あるいた。毒の進行はここで解決する（歩数で削るのが DQ の作法）。
signal poison_ticked

const TILE := 16
const MOVE_DELAY := 0.10
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

var map: FieldMap = null
var player_pos := Vector2i.ZERO
var facing := FACE_DOWN
var rng: DetRng = null
var hero_tex: Texture2D = null

## 物知りが話す内容を外から差し込む口（main.gd が封の手掛かりを入れる）。
## ExploreView は世界の事情を知らないので、文章はここでは作らない。
var rumor: Callable = Callable()

var _frame := 0
var _move_cd := 0.0
var _steps_since_encounter := 0
var _active := true


## leader_job は先頭キャラの職業。職業ごとに差し色の違うスプライトがある。
## at を渡すと、そこから始める（町から出たとき、元の位置へ戻すのに使う）。
func setup(
	field: FieldMap, encounter_rng: DetRng, leader_job: String = "soldier",
	at: Vector2i = Vector2i(-1, -1)
) -> void:
	map = field
	rng = encounter_rng
	hero_tex = _load_hero(leader_job)
	player_pos = field.start_pos if at.x < 0 else at
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
	if map is WorldMap:
		_try_move_world(target)
	elif map is TownMap:
		_try_move_town(target)
	else:
		_try_move_dungeon(target)


## 町の中を 1 歩。**町では敵が出ない**（安全地帯であることが町の値打ち）。
func _try_move_town(target: Vector2i) -> void:
	var town: TownMap = map

	# 人は押し当てて話す（洞の宝箱と同じ作法）。マスには乗らない。
	if town.folk.has(target):
		facing = _facing_for(target - player_pos)
		queue_redraw()
		var who: Dictionary = town.folk[target]
		# 物知りだけは決まり文句ではなく、そのときの手掛かりを話す。
		var line := String(who.get("line", ""))
		if String(who.get("kind", "")) == "elder" and rumor.is_valid():
			var hint := String(rumor.call())
			if hint != "":
				line = hint
		talked.emit(line)
		return

	if not map.is_walkable(target.x, target.y):
		queue_redraw()
		return

	player_pos = target
	_frame = (_frame + 1) % 3
	_update_camera()
	queue_redraw()

	var tile := map.get_tile(target.x, target.y)
	if tile == TownMap.T_SHOP:
		shop_entered.emit()
	elif tile == TownMap.T_DOOR:
		inn_entered.emit()
	elif tile == TownMap.T_EXIT:
		town_left.emit()


## ワールドを 1 歩。踏んだ拠点地を知らせるだけで、中へ入れるかは main.gd が決める。
func _try_move_world(target: Vector2i) -> void:
	if not map.is_walkable(target.x, target.y):
		queue_redraw()  # 向きだけ変える
		return

	player_pos = target
	_frame = (_frame + 1) % 3
	_update_camera()
	queue_redraw()

	var world: WorldMap = map
	# 街道のイベントは拠点地より先に見る（拠点地の上にも重なることがある）。
	if world.events.has(target) and not world.sites.has(target):
		_steps_since_encounter = 0
		event_reached.emit(target)
		return
	if world.sites.has(target):
		# 拠点地の上では遭遇しない。踏んだ歩数も数えない（門前で溜めるのを防ぐ）。
		_steps_since_encounter = 0
		site_entered.emit(target)
		return

	# 地形で歩きにくさが変わる。草原 1 / 丘 2 / 森 3。
	# 通れる・通れない以外の意味を地形に持たせないと、ただの模様になる。
	_steps_since_encounter += world.encounter_weight(target.x, target.y)
	poison_ticked.emit()

	if _should_encounter():
		_steps_since_encounter = 0
		encounter_triggered.emit()


func _try_move_dungeon(target: Vector2i) -> void:
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


## 遭遇の判定は Encounter に置いてある（シミュレータと同じ式を使うため）。
func _should_encounter() -> bool:
	return Encounter.should_meet(rng, _steps_since_encounter, GameState.event_encounter_bias)


func _update_camera() -> void:
	var focus := Vector2(player_pos * TILE) + Vector2(TILE, TILE) * 0.5
	var cam := focus - Vector2(PixelUI.SCREEN) * 0.5
	var span := Vector2(map.width * TILE, map.height * TILE)
	var limit := span - Vector2(PixelUI.SCREEN)
	# **画面より狭い地図は中央へ寄せる。** 端に寄せると片側だけ余白になり、
	# 「地図が途中で切れている」ように見える（町がそうだった）。
	cam.x = clampf(cam.x, 0.0, maxf(limit.x, 0.0)) if limit.x > 0.0 else limit.x * 0.5
	cam.y = clampf(cam.y, 0.0, maxf(limit.y, 0.0)) if limit.y > 0.0 else limit.y * 0.5
	position = -cam.floor()


func _draw() -> void:
	PixelUI.ui_frame()
	if map == null:
		return

	# **地図の外を先に塗りつぶす。** 町は 20〜30 タイルで画面（32 タイル）より
	# 狭いことがあり、余った右側に前の場面の絵が残って見えていた。
	# 町を 32 タイルへ水増しすると歩く距離が増えるだけなので、塗りで解く。
	draw_rect(
		Rect2(-position, Vector2(PixelUI.SCREEN)), Color8(0x06, 0x07, 0x10), true
	)

	# 画面に映る範囲だけ描く
	var origin := (-position / TILE).floor()
	var span := Vector2(PixelUI.SCREEN) / TILE + Vector2(2, 2)

	for y in range(int(origin.y), int(origin.y + span.y)):
		for x in range(int(origin.x), int(origin.x + span.x)):
			if not map.in_bounds(x, y):
				continue
			if map.is_void(x, y):
				continue
			var t := map.render_tile(x, y)
			draw_texture_rect_region(
				tileset_for(map.biome),
				Rect2(x * TILE, y * TILE, TILE, TILE),
				Rect2(t * TILE, 0, TILE, TILE)
			)

	# 町の人。主人公と同じ 24x32 のシートを使い、職業の絵を役に割り当てる。
	# 専用の絵を起こさずに「人が居る」を作る。
	if map is TownMap:
		var town: TownMap = map
		for pos in town.folk:
			var who: Vector2i = pos
			var tex := _folk_texture(String(town.folk[pos].get("kind", "")))
			if tex == null:
				continue
			# NPC は 24x32 の 1 コマ（歩かないので切り出しは先頭だけ）。
			draw_texture_rect_region(
				tex, Rect2((Vector2(who * TILE) + CHAR_OFFSET).floor(), Vector2(CHAR_W, CHAR_H)),
				Rect2(0, 0, CHAR_W, CHAR_H)
			)

	if hero_tex == null:
		return
	var at := Vector2(player_pos * TILE) + CHAR_OFFSET
	draw_texture_rect_region(
		hero_tex,
		Rect2(at.x, at.y, CHAR_W, CHAR_H),
		Rect2(_frame * CHAR_W, facing * CHAR_H, CHAR_W, CHAR_H)
	)


## 町の人の見た目。**役の名前がそのまま絵の名前**（`npc_<役>.png`）。
##
## もとは 4 役を主人公の絵に割り当てていた（町に自分と同じ姿が 4 人立っていた）。
## 17 種そろっているので、対応表を持たずに名前で引く ―― 表を挟むと、
## 絵を足すたびに表を直す必要があり、また「絵はあるのに出ない」が起きる。
static var _folk_tex: Dictionary = {}


func _folk_texture(kind: String) -> Texture2D:
	if _folk_tex.has(kind):
		return _folk_tex[kind]
	var path := "res://assets/sprites/npc_%s.png" % kind
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_folk_tex[kind] = tex
	return tex


func _load_hero(job: String) -> Texture2D:
	var path := "res://assets/sprites/hero_%s.png" % job
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/hero_soldier.png"
	return load(path)
