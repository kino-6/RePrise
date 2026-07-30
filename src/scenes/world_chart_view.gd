class_name WorldChartView
extends Node2D

## 世界を歩くための地図。地形・町・城と、判明した封だけを示す。
##
## 世界生成の答えを全部見せる画面ではない。地図イベントで得た情報が
## 実際に増え、町へ戻るか封へ向かうかを決められることが役目。

signal closed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")

const HEADER_RECT := Rect2(8, 8, 496, 36)
const MAP_RECT := Rect2(8, 50, 300, 198)
const LEGEND_RECT := Rect2(316, 50, 188, 198)
const HINT_RECT := Rect2(8, 256, 496, 56)
const TILE_SCALE := 3
const INPUT_LOCK := 0.15

const C_SEA := Color8(20, 34, 58)
const C_PLAIN := Color8(70, 126, 70)
const C_FOREST := Color8(37, 84, 57)
const C_HILL := Color8(132, 105, 65)
const C_MOUNTAIN := Color8(83, 83, 94)
const C_SNOW := Color8(190, 210, 210)
const C_DESERT := Color8(190, 156, 83)
const C_SWAMP := Color8(61, 91, 74)
const C_LAVA := Color8(180, 55, 38)
const C_ROAD := Color8(178, 139, 74)
const C_ROUTE := Color8(248, 211, 94)
const C_TOWN := Color8(236, 225, 181)
const C_CAVE := Color8(226, 139, 64)
const C_CASTLE := Color8(195, 69, 80)
const C_CURRENT := Color8(91, 222, 235)

var _world: WorldMap = null
var _player_pos := Vector2i.ZERO
var _route_revealed := false
var _input_lock := 0.0


func open(world: WorldMap, player_pos: Vector2i, route_revealed: bool) -> void:
	_world = world
	_player_pos = player_pos
	_route_revealed = route_revealed
	_input_lock = INPUT_LOCK
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	_input_lock = maxf(_input_lock - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("confirm"):
		Sound.play("cancel")
		close()
		closed.emit()


func _draw() -> void:
	PixelUI.ui_frame()
	draw_rect(
		Rect2(Vector2.ZERO, PixelUI.SCREEN),
		Color8(10, 14, 24),
		true
	)
	_draw_header()
	_draw_map()
	_draw_legend()
	_draw_hint()


func _draw_header() -> void:
	PixelUI.draw_window(self, HEADER_RECT, WINDOW_TEX)
	var right := ""
	if _world != null:
		right = Terms.DANGER_AT % _world.danger_at(_player_pos.x, _player_pos.y)
	UiPanel.inside(self, PixelUI.content(HEADER_RECT)).row(
		Terms.WORLD_MAP, right,
		PixelUI.C_ACTIVE, PixelUI.C_TEXT, PixelUI.SIZE_HEAD
	)


func _draw_map() -> void:
	PixelUI.draw_window(self, MAP_RECT, WINDOW_TEX)
	if _world == null:
		return
	var inner := PixelUI.content(MAP_RECT)
	var map_size := Vector2(
		_world.width * TILE_SCALE,
		_world.height * TILE_SCALE
	)
	var origin := (inner.position + (inner.size - map_size) * 0.5).floor()
	draw_rect(Rect2(origin, map_size), C_SEA, true)
	for y in _world.height:
		for x in _world.width:
			var at := Vector2i(x, y)
			draw_rect(
				Rect2(
					origin + Vector2(at * TILE_SCALE),
					Vector2(TILE_SCALE, TILE_SCALE)
				),
				_tile_color(_world.get_tile(x, y)),
				true
			)

	# 地図を読み解いた報酬は、城までの本街道を明色で重ねて残す。
	if _route_revealed:
		for at in _world.main_road:
			draw_rect(Rect2(
				origin + Vector2(at * TILE_SCALE) + Vector2.ONE,
				Vector2.ONE
			), C_ROUTE, true)

	_draw_marker(origin, _world.start_pos, PixelUI.C_TEXT_DIM, 5)
	for raw_pos in _world.sites:
		var pos: Vector2i = raw_pos
		if not _world.chart_site_visible(pos):
			continue
		var kind := String(_world.site_at(pos).get("kind", ""))
		match kind:
			"town":
				_draw_marker(origin, pos, C_TOWN, 5)
			"cave":
				var seal := _world.seal_at(pos)
				_draw_marker(
					origin, pos,
					PixelUI.C_ACTIVE if bool(seal.get("broken", false)) else C_CAVE,
					5
				)
			"castle":
				_draw_marker(origin, pos, C_CASTLE, 7)

	# 現在地は拠点の上からでも必ず読める輪郭にする。
	var current := origin + Vector2(_player_pos * TILE_SCALE) + Vector2(1, 1)
	draw_rect(Rect2(current - Vector2(3, 3), Vector2(7, 7)), C_CURRENT, false, 1.0)


func _draw_marker(origin: Vector2, pos: Vector2i, color: Color, size: int) -> void:
	@warning_ignore("integer_division")
	var half := size / 2
	var center := origin + Vector2(pos * TILE_SCALE) + Vector2(1, 1)
	draw_rect(
		Rect2(center - Vector2(half, half), Vector2(size, size)),
		color,
		true
	)


func _tile_color(tile: int) -> Color:
	match tile:
		WorldMap.T_PLAIN, WorldMap.T_GATE, WorldMap.T_TOWN, WorldMap.T_CAVE, WorldMap.T_CASTLE:
			return C_PLAIN
		WorldMap.T_FOREST:
			return C_FOREST
		WorldMap.T_HILL:
			return C_HILL
		WorldMap.T_MOUNTAIN:
			return C_MOUNTAIN
		WorldMap.T_SNOW:
			return C_SNOW
		WorldMap.T_DESERT:
			return C_DESERT
		WorldMap.T_SWAMP:
			return C_SWAMP
		WorldMap.T_LAVA:
			return C_LAVA
		WorldMap.T_ROAD:
			return C_ROAD
		_:
			return C_SEA


func _draw_legend() -> void:
	PixelUI.draw_window(self, LEGEND_RECT, WINDOW_TEX)
	var panel := UiPanel.inside(self, PixelUI.content(LEGEND_RECT))
	panel.line(Terms.MAP_LEGEND, PixelUI.C_TEXT_DIM)
	panel.line("◇ %s" % Terms.MAP_CURRENT, C_CURRENT)
	panel.line("□ %s" % Terms.MAP_TOWN, C_TOWN)
	panel.line("▲ %s" % Terms.MAP_SEAL, C_CAVE)
	panel.line("■ %s" % Terms.MAP_CASTLE, C_CASTLE)
	if _route_revealed:
		panel.line("━ %s" % Terms.MAP_SAFE_ROUTE, C_ROUTE)
	panel.skip(4.0)
	var known := 0
	var total := 0
	if _world != null:
		total = _world.seals.size()
		for seal in _world.seals:
			if bool(seal.get("known", false)) or bool(seal.get("broken", false)):
				known += 1
	panel.line(Terms.MAP_KNOWN_SEALS % [known, total], PixelUI.C_TEXT)


func _draw_hint() -> void:
	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var panel := UiPanel.inside(self, PixelUI.content(HINT_RECT))
	panel.line(
		Terms.MAP_REVEAL_NOTE if _route_revealed else Terms.MAP_UNKNOWN_NOTE,
		PixelUI.C_TEXT_DIM
	)
	panel.line(Terms.MAP_CLOSE_HINT, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
