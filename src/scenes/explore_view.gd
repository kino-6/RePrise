class_name ExploreView
extends Node2D

const TownInteractionScript := preload("res://src/world/town_interaction.gd")

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
signal ascended
signal boss_reached
signal shop_entered
## 宝箱を開けた。`summons_elite` は**この箱が格上を呼ぶか**（R-3）。
## 判定そのものは `GreedWatch` にあり、ここは踏んだ事実を渡すだけ。
signal chest_opened(amount: int, summons_elite: bool)
signal menu_requested
## ワールドで任意イベントのマスを踏んだ。開くかは main.gd が決める
## （一度きりかどうかを知っているのは向こう側）。
signal event_reached(pos: Vector2i)
## ワールドで拠点地（町・洞・城）を踏んだ。中へ入れるかは main.gd が決める。
## `from` は踏み込む直前のマス。町から出たとき、元の街道へ戻すために使う。
signal site_entered(pos: Vector2i, from: Vector2i)
## 町の人に話しかけた。役・町設定・台詞をまとめて外へ渡す。
signal talked(person: Dictionary)
## 町の中央にある、その土地固有の仕事場を調べた。
signal town_facility_used
signal town_chest_opened
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
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path)
	elif biome.begins_with("town_"):
		# 生成物が欠けた開発環境でも町そのものは成立させる。
		tex = tileset_for(biome.trim_prefix("town_"))
	else:
		tex = TILES_TEX
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

var _frame := 0
var _move_cd := 0.0
var _steps_since_encounter := 0
## 地形重みを掛けない実歩数。戦闘直後の最低歩数保証に使う。
var _walked_since_encounter := 0
## 開発用の実測値。自動プレイが「本当に何歩空いたか」を報告するときに読む。
var _last_encounter_gap := 0
var _active := true
## 町などから出た直後、同じ拠点地を1回だけ通過させる。
##
## ワールドの最短経路上に町があると、町を出た一歩後に同じ町へ踏み戻して
## 永久に往復する。拠点地を障害物にはせず、その1回だけ入場判定を抑える。
var _site_entry_suppressed := Vector2i(-1, -1)


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
	_walked_since_encounter = 0
	_last_encounter_gap = 0
	_site_entry_suppressed = Vector2i(-1, -1)
	_update_camera()
	queue_redraw()


func suppress_site_once(pos: Vector2i) -> void:
	_site_entry_suppressed = pos


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
		talked.emit(who)
		return

	# 中央の目印は飾りではなく、その町の生業を使う仕事場。
	# 通れない物へ押し当てる操作はNPCや宝箱と同じなので、新しいキーを増やさない。
	if target == town.landmark_pos:
		facing = _facing_for(target - player_pos)
		queue_redraw()
		town_facility_used.emit()
		return

	# 案内札とは別の、本当に開けられる町の物資箱。
	if target == town.supply_chest_pos:
		facing = _facing_for(target - player_pos)
		town.clear_supply_chest()
		queue_redraw()
		town_chest_opened.emit()
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

	var from := player_pos
	player_pos = target
	_frame = (_frame + 1) % 3
	_update_camera()
	queue_redraw()

	var world: WorldMap = map
	# 街道のイベントは拠点地より先に見る（拠点地の上にも重なることがある）。
	if world.events.has(target) and not world.sites.has(target):
		_steps_since_encounter = 0
		_walked_since_encounter = 0
		event_reached.emit(target)
		return
	if world.sites.has(target):
		var suppressed := target == _site_entry_suppressed
		# 1回の移動で必ず解除する。別方向へ歩いたなら、次に戻ったときは入れる。
		_site_entry_suppressed = Vector2i(-1, -1)
		if suppressed:
			return
		# 拠点地の上では遭遇しない。踏んだ歩数も数えない（門前で溜めるのを防ぐ）。
		_steps_since_encounter = 0
		_walked_since_encounter = 0
		site_entered.emit(target, from)
		return
	_site_entry_suppressed = Vector2i(-1, -1)

	# 地形で歩きにくさが変わる。草原 1 / 丘 2 / 森 3。
	# 通れる・通れない以外の意味を地形に持たせないと、ただの模様になる。
	_steps_since_encounter += world.encounter_weight(target.x, target.y)
	_walked_since_encounter += 1
	poison_ticked.emit()

	if _should_encounter():
		_last_encounter_gap = _walked_since_encounter
		_steps_since_encounter = 0
		_walked_since_encounter = 0
		encounter_triggered.emit()


func _try_move_dungeon(target: Vector2i) -> void:
	var tile := map.get_tile(target.x, target.y)

	# 宝箱は「押し当てて開ける」。マスには乗らない。
	if tile == DungeonMap.T_CHEST:
		var dungeon: DungeonMap = map
		# **開ける前の数**で決める。1 つ目を開けた時点で残りの箱に印が出るので、
		# 「これ以上は呼ぶ」を読んでから手を伸ばすことになる（後出しにしない）。
		var summons := GreedWatch.summons(dungeon.chests_taken)
		dungeon.chests_taken += 1
		map.set_tile(target.x, target.y, DungeonMap.T_FLOOR)
		map.chests.erase(target)
		queue_redraw()
		chest_opened.emit(rng.range_i(8, 30), summons)
		return


	if not map.is_walkable(target.x, target.y):
		queue_redraw()  # 向きだけ変える
		return

	player_pos = target
	_frame = (_frame + 1) % 3
	_steps_since_encounter += 1
	_walked_since_encounter += 1
	_update_camera()
	queue_redraw()

	if tile == DungeonMap.T_STAIRS:
		descended.emit()
		return
	if tile == DungeonMap.T_UP_STAIRS:
		ascended.emit()
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
		_last_encounter_gap = _walked_since_encounter
		_steps_since_encounter = 0
		_walked_since_encounter = 0
		encounter_triggered.emit()


## 遭遇の判定は Encounter に置いてある（シミュレータと同じ式を使うため）。
func _should_encounter() -> bool:
	return Encounter.should_meet(
		rng, _walked_since_encounter, _steps_since_encounter,
		GameState.event_encounter_bias
	)


## 自動プレイ用。通常遭遇で確定した歩数を一度だけ返す。
func dev_take_encounter_gap() -> int:
	var gap := _last_encounter_gap
	_last_encounter_gap = 0
	return gap


func _update_camera() -> void:
	var focus := Vector2(player_pos * TILE) + Vector2(TILE, TILE) * 0.5
	# 上の現在地窓と下のパーティ窓を除いた、実際に読める帯の中央へ置く。
	# 画面全体の中央を使うと、町の南入口に立った主人公が下HUDの裏へ隠れる。
	const FIELD_TOP := 44.0
	const FIELD_BOTTOM := 264.0
	const CHAR_PAD := 16.0
	var visible_center := Vector2(
		PixelUI.SCREEN.x * 0.5,
		(FIELD_TOP + FIELD_BOTTOM) * 0.5
	)
	var cam := focus - visible_center
	var span := Vector2(map.width * TILE, map.height * TILE)
	var limit := span - Vector2(PixelUI.SCREEN)
	# **画面より狭い地図は中央へ寄せる。** 端に寄せると片側だけ余白になり、
	# 「地図が途中で切れている」ように見える（町がそうだった）。
	cam.x = clampf(cam.x, 0.0, maxf(limit.x, 0.0)) if limit.x > 0.0 else limit.x * 0.5
	# キャラはタイルより縦に長いので上下へ1タイル余分に送れるようにする。
	# 地図端に少し暗い余白が見えても、主人公が窓の下へ消えるよりよい。
	var min_y := -FIELD_TOP - CHAR_PAD
	var max_y := span.y - FIELD_BOTTOM + CHAR_PAD
	cam.y = (
		clampf(cam.y, min_y, max_y)
		if max_y >= min_y
		else (min_y + max_y) * 0.5
	)
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
	var art_biome := "town_%s" % map.biome if map is TownMap else map.biome
	var map_tiles := tileset_for(art_biome)

	for y in range(int(origin.y), int(origin.y + span.y)):
		for x in range(int(origin.x), int(origin.x + span.x)):
			if not map.in_bounds(x, y):
				continue
			if map.is_void(x, y):
				continue
			var t := map.render_tile(x, y)
			draw_texture_rect_region(
				map_tiles,
				Rect2(x * TILE, y * TILE, TILE, TILE),
				Rect2(t * TILE, 0, TILE, TILE)
			)

	# 格上の敵は、踏む前から分かる赤い菱形で示す。地形タイルを上書きしないので、
	# 「街道の脇にいて避けられる」ことも同時に読める。
	if map is WorldMap:
		var world: WorldMap = map
		for raw_pos in world.events:
			var event_pos: Vector2i = raw_pos
			var instance: Dictionary = world.events[event_pos]
			if not bool(instance.get("visible_elite", false)) or GameState.event_done.has(event_pos):
				continue
			_draw_elite_mark(Vector2(event_pos * TILE) + Vector2(TILE, TILE) * 0.5)

	# 欲が呼ぶ格上（R-3）。1 つ目の宝箱を開けたら、**残りの箱に赤い印**が付く。
	# 世界に置かれた格上と同じ赤い菱形と「!」を使う ―― 呼ぶものが同じなので、
	# 記号も同じにする。印が出てから手を伸ばすかどうかが選択になる。
	if map is DungeonMap:
		var dungeon: DungeonMap = map
		if GreedWatch.summons(dungeon.chests_taken):
			for chest_pos in dungeon.chests:
				_draw_elite_mark(
					Vector2(chest_pos * TILE) + Vector2(TILE * 0.5, -2.0)
				)

	# 町の人。主人公と同じ 24x32 のシートを使い、職業の絵を役に割り当てる。
	# 専用の絵を起こさずに「人が居る」を作る。
	if map is TownMap:
		var town: TownMap = map
		_draw_town_marker(town.inn_pos, Terms.TOWN_INN_MARK, PixelUI.C_MP)
		_draw_town_marker(town.shop_pos, Terms.TOWN_SHOP_MARK, PixelUI.C_ACTIVE)
		var town_index := int(GameState.site.get("index", 0))
		var work_used := GameState.town_actions_done.has(
			TownInteractionScript.facility_key(town_index, town)
		)
		_draw_town_marker(
			town.landmark_pos, Terms.TOWN_WORK_MARK,
			PixelUI.C_TEXT_DIM if work_used else PixelUI.C_HP_OK
		)
		for pos in town.folk:
			var who: Vector2i = pos
			var tex := _folk_texture(String(town.folk[pos].get("kind", "")))
			if tex == null:
				continue
			_draw_character_shadow(Vector2(who * TILE) + CHAR_OFFSET)
			# NPC は 24x32 の 1 コマ（歩かないので切り出しは先頭だけ）。
			draw_texture_rect_region(
				tex, Rect2((Vector2(who * TILE) + CHAR_OFFSET).floor(), Vector2(CHAR_W, CHAR_H)),
				Rect2(0, 0, CHAR_W, CHAR_H)
			)

	if hero_tex == null:
		return
	var at := Vector2(player_pos * TILE) + CHAR_OFFSET
	_draw_character_shadow(at)
	draw_texture_rect_region(
		hero_tex,
		Rect2(at.x, at.y, CHAR_W, CHAR_H),
		Rect2(_frame * CHAR_W, facing * CHAR_H, CHAR_W, CHAR_H)
	)


## 格上が居る／呼べる場所を示す赤い菱形と「!」。
##
## 世界に置かれた 1 体（R-1）と、欲が呼ぶ格上（R-3）で**同じ記号を使う**。
## 出てくるものが同じなのに印が違うと、覚え直しが要るだけで何も伝わらない。
func _draw_elite_mark(center: Vector2) -> void:
	var outer := PackedVector2Array([
		center + Vector2(0, -9), center + Vector2(9, 0),
		center + Vector2(0, 9), center + Vector2(-9, 0),
	])
	var inner := PackedVector2Array([
		center + Vector2(0, -6), center + Vector2(6, 0),
		center + Vector2(0, 6), center + Vector2(-6, 0),
	])
	draw_colored_polygon(outer, PixelUI.C_SHADOW)
	draw_colored_polygon(inner, PixelUI.C_HP_LOW)
	PixelUI.draw_text(
		self, (center + Vector2(-3, -8)).floor(), "!", Color.WHITE, PixelUI.SIZE_TEXT
	)


## 施設タイルの絵だけでは宿・店・仕事場を区別できなかったため、
## 14pxの短い札を入口へ重ねる。仕事場だけは利用後に色を落とす。
func _draw_town_marker(at: Vector2i, label: String, color: Color) -> void:
	if at.x < 0 or label == "":
		return
	var width := PixelUI.text_width(label, PixelUI.SIZE_TEXT) + 6.0
	var pos := Vector2(at * TILE) + Vector2((TILE - width) * 0.5, 0)
	draw_rect(Rect2(pos, Vector2(width, 16)), Color8(0x08, 0x0A, 0x12), true)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(width - 2, 1)), color.darkened(0.25), true)
	PixelUI.draw_text(self, pos + Vector2(3, 0), label, color, PixelUI.SIZE_TEXT)


## 地形の細かい模様と人物の足を分離する、共通の接地影。
##
## 魔法使いの絵そのものは十分読めるのに、実画面では足元が草や石畳へ溶けていた。
## 主人公とNPCへ同じ影を置き、「別々の素材を貼った」印象も弱める。
func _draw_character_shadow(at: Vector2) -> void:
	var dark := Color8(0x08, 0x0A, 0x12)
	draw_rect(Rect2((at + Vector2(4, 28)).floor(), Vector2(16, 2)), dark, true)
	draw_rect(Rect2((at + Vector2(7, 30)).floor(), Vector2(10, 1)), dark, true)


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
