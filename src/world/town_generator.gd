class_name TownGenerator
extends RefCounted

const TownDialogue := preload("res://src/world/town_dialogue.gd")

## 町の中を作る。
##
## 洞と違って**迷わせない**のが目的。町は目的地であって迷路ではないので、
## 中央に広場を置き、宿・店・出口を広場から必ず見える位置に並べる。
## 迷う町は、用があって寄った人間にとってただの足止めになる。
##
## 乱数は渡された DetRng だけ。同じ世界の同じ町は毎回同じ形になる。

## 町の名の作り方。地形の語 + 場所の語。
## AI に書かせる前の土台で、これだけでも毎回違う名前が出る
## （docs/quest_design.md の「テンプレート語彙表 × DetRng」がこれ）。
static var NAME_HEAD: Array = Vocabulary.nested(
	"town_names", "", "head",
	["かぜ", "いずみ", "しらかば", "あかつき", "みなも", "とうげ"]
)
static var NAME_TAIL: Array = Vocabulary.nested(
	"town_names", "", "tail", ["の里", "の宿場", "の町"]
)

## 町人の一言は `data/town_dialogue.json` に置く。
## 役を増やしても、文章を直すために生成コードへ触れない。

## 町に立つ役。**その町の生物相と危険度で顔ぶれが変わる。**
## 全部の町に同じ 4 人が立っていると、町が変わった気がしない。
const FOLK_ROLES := [
	"innkeeper", "merchant", "elder", "scout", "guard", "blacksmith",
	"healer", "farmer", "miner", "ferryman", "mechanic", "scribe",
	"pilgrim", "refugee", "performer", "beastkeeper", "imperial_officer",
]

## どの町にも必ず居る役（宿・店・物知り）。用が足せることを保証する。
const CORE_ROLES := ["innkeeper", "merchant", "elder"]

## 生物相に合う役。土地の顔を出すためのもの。
const BIOME_ROLES := {
	"wetland": ["ferryman", "healer"],
	"snowfield": ["pilgrim", "refugee"],
	"volcano": ["blacksmith", "mechanic"],
	"badland": ["miner", "refugee"],
	"desert": ["ferryman", "pilgrim"],
	"grassland": ["farmer", "performer"],
	"forest": ["beastkeeper", "scout"],
}

## 何人立たせるか。町の広さで変える。
const FOLK_MIN := 4
const FOLK_MAX := 7


## 町の広さ。生物相と危険度で少し振る（辺境の町は小さい）。
const SIZE_MIN := Vector2i(20, 14)
const SIZE_MAX := Vector2i(30, 20)


static func generate(
	rng: DetRng, danger: int, tileset: String,
	town_index: int = 0, world_variant: int = 0
) -> TownMap:
	# 用途ごとに乱数列を分ける。台詞を1つ増やしても間取りまで変えない。
	var profile := TownProfile.generate(
		rng.fork("profile"), town_index, world_variant, tileset, danger
	)
	var layout_rng := rng.fork("layout")
	var name_rng := rng.fork("name")
	var decor_rng := rng.fork("decor")
	var folk_rng := rng.fork("folk")

	# **寸法より先にProfileが決まっている。** 間取りは町の意味の出力にする。
	var w := layout_rng.range_i(SIZE_MIN.x, SIZE_MAX.x)
	var h := layout_rng.range_i(SIZE_MIN.y, SIZE_MAX.y)
	var map := TownMap.new(w, h)
	map.biome = tileset
	map.profile = profile
	map.town_name = "%s%s" % [
		NAME_HEAD[name_rng.range_i(0, NAME_HEAD.size() - 1)],
		NAME_TAIL[name_rng.range_i(0, NAME_TAIL.size() - 1)],
	]

	for y in h:
		for x in w:
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			map.set_tile(x, y, TownMap.T_WALL if edge else TownMap.T_GROUND)

	# 入口は南辺中央へ固定し、内側の到着余白から町を読み始める。
	map.exit_pos = _place_exit(map, layout_rng)
	map.start_pos = _inward_from(map, map.exit_pos)
	_clear_arrival_space(map)

	# 広場と主街路を先に予約し、施設はその枝へ置く。
	map.plaza_pos = _choose_plaza(map, layout_rng)
	_paint_plaza(map)
	_paint_main_street(map)
	_place_profile_facilities(map, layout_rng)
	_paint_landmark(map)
	_place_decorations(map, decor_rng)

	# 装飾を撒いたあと、固定領域と計画街路をもう一度確定する。
	# こうすれば装飾数を変えても入口契約は壊れない。
	_clear_arrival_space(map)
	_repave_reserved(map)
	_place_folk(map, folk_rng, danger, profile)

	var problems := verify(map)
	if not problems.is_empty():
		push_warning("町生成の検算に失敗: %s" % " / ".join(problems))
	return map


## 出口を 4 辺のどれかに開ける。
## 出入口。**南辺の中央に固定する。**
##
## 前は四辺から乱数で選んでいたが、変える理由が無かった。町ごとに出口が飛ぶと
##
##   * 入った直後にどちらを向けばいいか分からない（毎回探し直す）、
##   * 出たつもりが別の辺で、世界地図の上を行ったり来たりする
##     （自動プレイが世界↔町を 8 回続けて往復した）、
##   * 「戻る場所」が覚えられないので町が土地として頭に残らない、
##
## という害だけがあった。町ごとの違いは**入口より先**の街路と地区で作る（C-8）。
## 画面の下端中央から入るのは、往年の RPG が一貫してそうしていた形でもある。
static func _place_exit(map: TownMap, _rng: DetRng) -> Vector2i:
	@warning_ignore("integer_division")
	var at := Vector2i(map.width / 2, map.height - 1)
	map.set_tile(at.x, at.y, TownMap.T_EXIT)
	return at


## 出口の 1 マス内側（入ってきて最初に立つ場所）。
##
## 出口は南辺なので**必ず真上**。近傍の並び順に頼ると、町の形によって
## 左右へずれて「入って正面が壁」になる。
static func _inward_from(map: TownMap, at: Vector2i) -> Vector2i:
	var inside := at + Vector2i(0, -1)
	if inside.y > 0:
		return inside
	@warning_ignore("integer_division")
	return Vector2i(map.width / 2, map.height / 2)


## 入口の内側5×2を素の地面へ戻す。装飾の乱数は入口決定より先に撒くため、
## 最後に予約域を確定させれば乱数列を変えず、毎回同じ読み始めを保証できる。
static func _clear_arrival_space(map: TownMap) -> void:
	for y in range(map.height - 4, map.height - 1):
		for x in range(map.exit_pos.x - 2, map.exit_pos.x + 3):
			if map.in_bounds(x, y):
				map.set_tile(x, y, TownMap.T_GROUND)


## 中央広場。入口との縦軸を少しだけずらし、町ごとの見取り図を作る。
static func _choose_plaza(map: TownMap, rng: DetRng) -> Vector2i:
	@warning_ignore("integer_division")
	var x := clampi(map.exit_pos.x + rng.range_i(-2, 2), 7, map.width - 8)
	@warning_ignore("integer_division")
	var y := clampi(map.height / 2 + rng.range_i(-1, 1), 7, map.height - 7)
	return Vector2i(x, y)


## 5x5 の広場。目印はこのあと中央へ置く。
static func _paint_plaza(map: TownMap) -> void:
	map.plaza_tiles.clear()
	for y in range(map.plaza_pos.y - 2, map.plaza_pos.y + 3):
		for x in range(map.plaza_pos.x - 2, map.plaza_pos.x + 3):
			var at := Vector2i(x, y)
			if not map.in_bounds(x, y):
				continue
			map.set_tile(x, y, TownMap.T_GROUND_ALT)
			map.plaza_tiles.append(at)


## 南入口から広場南端までの主街路。
##
## 最初の3マスは必ず真北。その先でだけ広場のx座標へ曲げる。
static func _paint_main_street(map: TownMap) -> void:
	map.main_street.clear()
	var cursor := map.start_pos
	var bend_y := mini(map.plaza_pos.y + 3, map.start_pos.y - 3)
	_add_path_tile(map, cursor, map.main_street)
	while cursor.y > bend_y:
		cursor += Vector2i.UP
		_add_path_tile(map, cursor, map.main_street)
	while cursor.x != map.plaza_pos.x:
		cursor += Vector2i(signi(map.plaza_pos.x - cursor.x), 0)
		_add_path_tile(map, cursor, map.main_street)
	while cursor.y > map.plaza_pos.y + 2:
		cursor += Vector2i.UP
		_add_path_tile(map, cursor, map.main_street)


static func _add_path_tile(
	map: TownMap, at: Vector2i, result: Array[Vector2i]
) -> void:
	if at not in result:
		result.append(at)
	if map.get_tile(at.x, at.y) in [TownMap.T_GROUND, TownMap.T_GROUND_ALT]:
		map.set_tile(at.x, at.y, TownMap.T_GROUND_ALT)


## 広場の左右へ宿と店を置き、別々の枝道で結ぶ。
static func _place_profile_facilities(map: TownMap, rng: DetRng) -> void:
	var door_y := map.plaza_pos.y - 2
	var left_x := maxi(map.plaza_pos.x - rng.range_i(5, 6), 4)
	var right_x := mini(map.plaza_pos.x + rng.range_i(5, 6), map.width - 5)
	var left_size := Vector2i(rng.range_i(5, 6), rng.range_i(3, 4))
	var right_size := Vector2i(rng.range_i(5, 6), rng.range_i(3, 4))
	var left_plot := _plot_for_door(Vector2i(left_x, door_y), left_size)
	var right_plot := _plot_for_door(Vector2i(right_x, door_y), right_size)
	var inn_left := rng.chance(50)
	var left_kind := TownMap.T_DOOR if inn_left else TownMap.T_SHOP
	var right_kind := TownMap.T_SHOP if inn_left else TownMap.T_DOOR
	var left_door := _place_building(map, left_plot, left_kind)
	var right_door := _place_building(map, right_plot, right_kind)
	map.inn_pos = left_door if inn_left else right_door
	map.shop_pos = right_door if inn_left else left_door

	map.facility_paths.clear()
	_connect_facility(
		map, left_door, map.plaza_pos + Vector2i(-2, 0)
	)
	_connect_facility(
		map, right_door, map.plaza_pos + Vector2i(2, 0)
	)


static func _plot_for_door(door: Vector2i, size: Vector2i) -> Rect2i:
	@warning_ignore("integer_division")
	return Rect2i(
		door.x - size.x / 2,
		door.y - size.y + 1,
		size.x,
		size.y
	)


static func _connect_facility(
	map: TownMap, door: Vector2i, anchor: Vector2i
) -> void:
	var cursor := door
	if cursor not in map.facility_paths:
		map.facility_paths.append(cursor)
	while cursor.y != anchor.y:
		cursor += Vector2i(0, signi(anchor.y - cursor.y))
		_add_path_tile(map, cursor, map.facility_paths)
	while cursor.x != anchor.x:
		cursor += Vector2i(signi(anchor.x - cursor.x), 0)
		_add_path_tile(map, cursor, map.facility_paths)


## Profileの目印。既存タイルだけで、通りから読める2〜3要素に絞る。
static func _paint_landmark(map: TownMap) -> void:
	var at := map.plaza_pos
	map.landmark_pos = at
	match map.profile.landmark_id:
		"great_tree":
			map.set_tile(at.x, at.y, TownMap.T_WALL)
		"forge":
			map.set_tile(at.x, at.y, TownMap.T_SIGN)
			map.set_tile(at.x, at.y - 1, TownMap.T_WALL)
		"bell":
			map.set_tile(at.x, at.y, TownMap.T_SIGN)
			map.set_tile(at.x, at.y - 1, TownMap.T_WALL)
		"gear":
			for dx in [-1, 0, 1]:
				map.set_tile(at.x + dx, at.y, TownMap.T_SIGN)
		"shrine":
			map.set_tile(at.x, at.y, TownMap.T_SIGN)
			map.set_tile(at.x - 1, at.y - 1, TownMap.T_WALL)
			map.set_tile(at.x + 1, at.y - 1, TownMap.T_WALL)
		"pen":
			map.set_tile(at.x, at.y, TownMap.T_SIGN)
			for dx in [-1, 0, 1]:
				map.set_tile(at.x + dx, at.y - 1, TownMap.T_WALL)
		_:
			# well / banner。単独の看板を水場・旗柱の抽象記号にする。
			map.set_tile(at.x, at.y, TownMap.T_SIGN)


## Profileの問題で散らかり方を変える。ただし予約した導線へは置かない。
static func _place_decorations(map: TownMap, rng: DetRng) -> void:
	var count := rng.range_i(7, 13)
	if map.profile.problem_id in ["broken_road", "failing_mine"]:
		count += 4
	elif map.profile.problem_id in ["shortage", "dry_well"]:
		count -= 2
	for _i in 120:
		if count <= 0:
			break
		var at := Vector2i(
			rng.range_i(2, map.width - 3),
			rng.range_i(2, map.height - 3)
		)
		if _reserved(map, at):
			continue
		if map.get_tile(at.x, at.y) != TownMap.T_GROUND:
			continue
		map.set_tile(at.x, at.y, TownMap.T_GROUND_ALT)
		count -= 1


static func _repave_reserved(map: TownMap) -> void:
	for group in [map.main_street, map.facility_paths, map.plaza_tiles]:
		for raw_at in group:
			var at: Vector2i = raw_at
			if map.get_tile(at.x, at.y) == TownMap.T_GROUND:
				map.set_tile(at.x, at.y, TownMap.T_GROUND_ALT)


static func _reserved(map: TownMap, at: Vector2i) -> bool:
	return (
		at in map.main_street
		or at in map.facility_paths
		or at in map.plaza_tiles
		or (
			absi(at.x - map.exit_pos.x) <= 2
			and at.y >= map.height - 4
		)
	)


## 建物 1 つ。区画を壁で埋め、下辺の中央を入口にする。
static func _place_building(map: TownMap, plot: Rect2i, entrance: int) -> Vector2i:
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			map.set_tile(x, y, TownMap.T_WALL)
	var door := Vector2i(plot.position.x + plot.size.x / 2, plot.end.y - 1)
	map.set_tile(door.x, door.y, entrance)
	# 看板を入口の隣に。何の建物かが近づく前に分かる。
	var sign_at := Vector2i(door.x + 2, door.y)
	if sign_at.x < plot.end.x:
		map.set_tile(sign_at.x, sign_at.y, TownMap.T_SIGN)
	return door


## 町人を置く。
##
## **必ず居る役 → 土地に合う役 → 残りから**の順で選ぶ。
## 用（宿・店・手掛かり）が足せることを先に保証し、そのうえで顔ぶれを振る。
static func _place_folk(
	map: TownMap, rng: DetRng, danger: int, profile: TownProfile
) -> void:
	var biome := String(map.biome)
	var roles: Array[String] = []
	roles.append_array(CORE_ROLES)
	# 生業・支配・問題の当事者を、汎用の土地役より先に確保する。
	for role in profile.roles():
		if role not in roles:
			roles.append(role)
	for role in BIOME_ROLES.get(biome, []):
		if String(role) not in roles:
			roles.append(String(role))
	var rest: Array = FOLK_ROLES.filter(func(r: String) -> bool: return r not in roles)
	rng.shuffle(rest)
	var wanted := maxi(rng.range_i(FOLK_MIN, FOLK_MAX), roles.size())
	for r in rest:
		if roles.size() >= wanted:
			break
		roles.append(String(r))

	var spots: Array[Vector2i] = []
	for _i in 320:
		if spots.size() >= roles.size():
			break
		var at := Vector2i(rng.range_i(2, map.width - 3), rng.range_i(2, map.height - 3))
		if map.get_tile(at.x, at.y) not in [TownMap.T_GROUND, TownMap.T_GROUND_ALT]:
			continue
		if at == map.start_pos or at == map.exit_pos or _reserved(map, at):
			continue
		var near := false
		for other in spots:
			if absi(other.x - at.x) + absi(other.y - at.y) < 3:
				near = true
				break
		if near:
			continue
		# 人は壁と同じく通れない。入口固定で乱数列が変わったとき、宿の前を
		# 町人が塞ぐ町が実際に一つ出た。置くたびに必須地点への道を再検算する。
		map.folk[at] = {}
		var dist := map.distance_field(map.start_pos)
		var routes_kept := true
		for goal in [map.inn_pos, map.shop_pos, map.exit_pos]:
			if dist[goal.y * map.width + goal.x] < 0:
				routes_kept = false
				break
		if not routes_kept:
			map.folk.erase(at)
			continue
		spots.append(at)

	for i in spots.size():
		var role := String(roles[i % roles.size()])
		var pool: Array = TownDialogue.role_lines(role)
		var line := profile.line_for(role)
		if line == "":
			line = String(pool[rng.range_i(0, pool.size() - 1)])
		map.folk[spots[i]] = {
			"kind": role,
			"line": line,
			"danger": danger,
			"profile": profile.signature(),
		}


## 町の生成契約。画面から見えない設定接続もここで疑う。
static func verify(map: TownMap) -> Array[String]:
	var problems: Array[String] = []
	@warning_ignore("integer_division")
	var expected_exit := Vector2i(map.width / 2, map.height - 1)
	if map.exit_pos != expected_exit:
		problems.append("入口が南辺中央ではない")
	if map.start_pos != expected_exit + Vector2i.UP:
		problems.append("開始位置が入口直上ではない")
	if map.profile == null or map.profile.signature() == "":
		problems.append("TownProfileが無い")
	if map.plaza_pos.x < 0 or map.landmark_pos != map.plaza_pos:
		problems.append("広場と目印が無い")

	# 到着余白は計画街路だけを許し、建物・看板・装飾・人を置かない。
	for y in range(map.height - 4, map.height - 1):
		for x in range(map.exit_pos.x - 2, map.exit_pos.x + 3):
			var at := Vector2i(x, y)
			if map.folk.has(at):
				problems.append("到着余白を住人が塞ぐ")
				continue
			var tile := map.get_tile(x, y)
			if tile == TownMap.T_GROUND_ALT and at in map.main_street:
				continue
			if tile != TownMap.T_GROUND:
				problems.append(
					"到着余白に計画外の物がある:%s=%d" % [str(at), tile]
				)

	if map.main_street.size() < 3:
		problems.append("主街路が3歩に満たない")
	else:
		for i in mini(3, map.main_street.size()):
			var at: Vector2i = map.main_street[i]
			if at.x != map.exit_pos.x or at.y != map.start_pos.y - i:
				problems.append("主街路の最初の3歩が真北ではない")
		for i in range(1, map.main_street.size()):
			var before: Vector2i = map.main_street[i - 1]
			var current: Vector2i = map.main_street[i]
			if absi(before.x - current.x) + absi(before.y - current.y) != 1:
				problems.append("主街路が途切れている")
				break
		for at in map.main_street:
			if map.folk.has(at):
				problems.append("主街路を住人が塞ぐ")
				break
		if map.main_street.back() not in map.plaza_tiles:
			problems.append("主街路が広場へ届かない")

	var dist := map.distance_field(map.start_pos)
	for goal in [map.inn_pos, map.shop_pos, map.exit_pos]:
		if (
			not map.in_bounds(goal.x, goal.y)
			or dist[goal.y * map.width + goal.x] < 0
		):
			problems.append("必須施設へ届かない")

	for door in [map.inn_pos, map.shop_pos]:
		var has_sign := false
		for y in range(door.y - 2, door.y + 3):
			for x in range(door.x - 2, door.x + 3):
				if map.in_bounds(x, y) and map.get_tile(x, y) == TownMap.T_SIGN:
					has_sign = true
		if not has_sign:
			problems.append("施設の看板が扉から見えない")

	var required_roles: Array[String] = ["elder"]
	if map.profile != null:
		for role in map.profile.roles():
			if role not in required_roles:
				required_roles.append(role)
	for role in required_roles:
		var found := false
		var approachable := false
		for raw_pos in map.folk:
			var pos: Vector2i = raw_pos
			if String(map.folk[pos].get("kind", "")) != role:
				continue
			found = true
			for step in FieldMap.NEIGHBORS:
				var near := pos + step
				if (
					map.in_bounds(near.x, near.y)
					and map.is_walkable(near.x, near.y)
					and dist[near.y * map.width + near.x] >= 0
				):
					approachable = true
		if not found:
			problems.append("Profileの住人がいない:%s" % role)
		elif not approachable:
			problems.append("情報役へ話しかけられない:%s" % role)

	return _unique(problems)


static func _unique(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if value not in result:
			result.append(value)
	return result


## 固定入口と寸法を違いとして数えない、町内部の正規化指紋。
##
## ランダム装飾のT_GROUND_ALTは通常地面へ潰し、広場・計画街路・施設・建物と
## Profileだけを残す。「入口を振っただけ」「石を撒いただけ」を別形にしない。
static func internal_fingerprint(map: TownMap) -> String:
	var profile_key := map.profile.signature() if map.profile != null else "none"
	var result := "%s|I%s|S%s|" % [
		profile_key,
		str(map.inn_pos - map.plaza_pos),
		str(map.shop_pos - map.plaza_pos),
	]
	for dy in range(-6, 7):
		for dx in range(-10, 11):
			var at := map.plaza_pos + Vector2i(dx, dy)
			if not map.in_bounds(at.x, at.y):
				result += " "
			elif at == map.inn_pos:
				result += "I"
			elif at == map.shop_pos:
				result += "S"
			elif at == map.landmark_pos:
				result += "L"
			elif at in map.main_street:
				result += "r"
			elif at in map.facility_paths:
				result += "f"
			elif at in map.plaza_tiles:
				result += "p"
			else:
				match map.get_tile(at.x, at.y):
					TownMap.T_WALL, TownMap.T_WALL_TOP:
						result += "#"
					TownMap.T_SIGN:
						result += "!"
					_:
						result += "."
		result += "\n"
	return result
