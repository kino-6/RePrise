class_name BattleView
extends Node2D

## 戦闘画面。BattleSystem（ロジック）に対する表示と入力だけを担当する。
##
## 画面配置（384x240）
##   y   2..17   行動順バー
##   y  24..124  敵
##   y 128..176  メッセージ窓 / コマンド窓
##   y 180..234  パーティ状態（4 人を横 1 列）

signal battle_finished(victory: bool)

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")
const SPRITES := {
	"gel": preload("res://assets/sprites/gel.png"),
	"bat": preload("res://assets/sprites/bat.png"),
	"skull": preload("res://assets/sprites/skull.png"),
	"shade": preload("res://assets/sprites/shade.png"),
	"golem": preload("res://assets/sprites/golem.png"),
	"warden": preload("res://assets/sprites/warden.png"),
}

const MESSAGE_RECT := Rect2(6, 128, 372, 48)

## コマンド窓は 2 列 x 3 行。転職を重ねると技は基本 2 + 習得 12 まで増えるので、
## 収まらないぶんはページに分ける。描ける数で技の上限を決めるのは本末転倒。
const COMMAND_ROWS := 3
const COMMAND_COLS := 2
const COMMANDS_PER_PAGE := COMMAND_ROWS * COMMAND_COLS
const STATUS_RECT := Rect2(6, 180, 372, 54)
const ENEMY_BASELINE := 120
const LINE_DELAY := 0.65

enum State { TURN_START, COMMAND, TARGET, ITEM, MESSAGE, DONE }

## コマンド一覧に混ぜる「どうぐ」の擬似 ID。技と道具は別系統だが、
## 選ぶ場所は 1 つにしたいのでコマンド列に同居させる。
const ITEM_COMMAND := "__item__"

var system: BattleSystem = null
var members: Array[PartyMember] = []

var _state: State = State.TURN_START
var _actor: Battler = null
var _queue: Array[String] = []
var _shown: Array[String] = []
var _timer := 0.0

var _commands: Array[String] = []
var _command_index := 0
var _targets: Array[Battler] = []
var _target_index := 0
var _pending_ability := ""

var _items: Array = []
var _item_index := 0
var _pending_item := ""

var _order_bar: TurnOrderBar = null
var _victory := false
var _outcome_shown := false


func _ready() -> void:
	_order_bar = TurnOrderBar.new()
	add_child(_order_bar)


## party_members は戦闘後に経験値と熟練度を書き戻すために受け取る。
func start(battle: BattleSystem, party_members: Array[PartyMember]) -> void:
	system = battle
	members = party_members
	_state = State.TURN_START
	_queue.clear()
	_shown.clear()
	_outcome_shown = false
	_victory = false
	set_process(true)
	set_process_unhandled_input(true)
	_refresh()


# --------------------------------------------------------------------------
# 進行
# --------------------------------------------------------------------------


func _process(delta: float) -> void:
	if system == null:
		return
	match _state:
		State.TURN_START:
			_begin_turn()
		State.MESSAGE:
			_timer -= delta
			if _timer <= 0.0:
				_advance_message()
		_:
			pass


func _begin_turn() -> void:
	if system.is_over:
		_finish()
		return
	_actor = system.begin_turn()
	if _actor == null:
		_finish()
		return
	_refresh()
	if _actor.is_ally:
		_open_command_menu()
	else:
		var lines := system.perform_enemy(_actor)
		_play_ability_sfx(system.last_ability_id)
		_show(lines)


## 技の系統で効果音を選ぶ。技ごとに音を持たせるのは後からでよく、
## まずは打撃・魔法・回復の 3 種が鳴り分ければ手応えが出る。
func _play_ability_sfx(ability_id: String) -> void:
	match String(Database.ability(ability_id).get("kind", "")):
		"physical":
			Sound.play("hit")
		"magical":
			Sound.play("magic")
		"heal":
			Sound.play("heal")
		_:
			Sound.play("confirm")


## 開発用。コマンド選択が出るまで待ってから撮影するのに使う。
func is_awaiting_command() -> bool:
	return _state == State.COMMAND


## 開発用。2 ページ目以降の見え方を撮るために使う。
func debug_turn_page(delta: int) -> void:
	_turn_page(delta)


## 開発用。どうぐの一覧を撮るために使う。
func debug_open_item_menu() -> void:
	_open_item_menu()


func _open_command_menu() -> void:
	_commands = system.usable_abilities(_actor)
	# 持ち物があるときだけ「どうぐ」を出す。空の欄を選ばせても意味がない。
	if not GameState.inventory.is_empty():
		_commands.append(ITEM_COMMAND)
	_command_index = 0
	_pending_item = ""
	_state = State.COMMAND
	_refresh()


func _show(lines: Array[String]) -> void:
	_queue = lines.duplicate()
	_shown.clear()
	_state = State.MESSAGE
	_timer = 0.0
	_advance_message()


func _advance_message() -> void:
	if _queue.is_empty():
		_after_messages()
		return
	_shown.append(_queue.pop_front())
	# 窓は 3 行ぶん。溢れたら古い行から捨てる。
	while _shown.size() > 3:
		_shown.pop_front()
	_timer = LINE_DELAY
	_refresh()


func _after_messages() -> void:
	if system.is_over:
		# 決着後は結果表示を 1 回だけ挟み、それも読み終えてから画面を閉じる
		if _outcome_shown:
			_finish()
		else:
			_resolve_outcome()
		return
	_state = State.TURN_START


## 勝敗が決したあとの後始末。ここが DQ6 的な「持ち帰り」の演出点になる。
func _resolve_outcome() -> void:
	_outcome_shown = true
	_victory = system.victory()
	var lines: Array[String] = []
	if _victory:
		var reward := system.rewards()
		lines.append("たたかいに かった！")
		lines.append("%d の けいけんちと %d ゴールドを えた" % [reward["exp"], reward["gold"]])
		GameState.gold += int(reward["gold"])

		for m in members:
			if m.hp <= 0:
				continue  # 倒れていた者には入らない
			if m.gain_exp(int(reward["exp"])) > 0:
				lines.append("%sは レベル %d に あがった！" % [m.name, m.level])
			for ability_id in m.gain_mastery(int(reward["mastery"])):
				# ラン中に覚えた技は、全滅しても拠点に残る
				var ability_name: String = Database.ability(ability_id).get("name", ability_id)
				lines.append("%sは %s を おぼえた！" % [m.name, ability_name])
	else:
		lines.append("パーティは ぜんめつした…")

	_show(lines)


func _finish() -> void:
	if _state == State.DONE:
		return
	_state = State.DONE
	set_process(false)
	set_process_unhandled_input(false)
	# 残 HP/MP を本体へ書き戻す（次の戦闘に持ち越す）
	for i in members.size():
		if i < system.allies.size():
			members[i].sync_from_battler(system.allies[i])
	battle_finished.emit(_victory)


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match _state:
		State.COMMAND:
			_input_command()
		State.TARGET:
			_input_target()
		State.ITEM:
			_input_item()
		State.MESSAGE:
			if Input.is_action_just_pressed("confirm"):
				_timer = 0.0  # 送りを早める
		_:
			pass


@warning_ignore("integer_division")
func _command_page() -> int:
	return _command_index / COMMANDS_PER_PAGE


func _total_items() -> int:
	var total := 0
	for id in GameState.inventory_ids():
		total += GameState.item_count(String(id))
	return total


func _page_count() -> int:
	return maxi(int(ceil(_commands.size() / float(COMMANDS_PER_PAGE))), 1)


func _input_command() -> void:
	if _commands.is_empty():
		return
	if Input.is_action_just_pressed("ui_down"):
		_command_index = (_command_index + 1) % _commands.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("ui_up"):
		_command_index = (_command_index - 1 + _commands.size()) % _commands.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("ui_right"):
		_turn_page(+1)
	elif Input.is_action_just_pressed("ui_left"):
		_turn_page(-1)
	elif Input.is_action_just_pressed("confirm"):
		Sound.play("confirm")
		_choose_command()


## 左右でページごと飛ばす。技が増えるほど上下だけでは遠くなるため。
func _turn_page(delta: int) -> void:
	if _page_count() <= 1:
		return
	var page := posmod(_command_page() + delta, _page_count())
	_command_index = mini(page * COMMANDS_PER_PAGE, _commands.size() - 1)
	Sound.play("cursor")
	_refresh()


func _choose_command() -> void:
	if _commands[_command_index] == ITEM_COMMAND:
		_open_item_menu()
		return
	_pending_item = ""
	_pending_ability = _commands[_command_index]
	var ab := Database.ability(_pending_ability)
	var scope := String(ab.get("target", "one_enemy"))

	# 単体指定が要らない技はそのまま実行
	if scope in ["self", "all_enemies", "all_allies"]:
		_execute(null)
		return

	_targets = _candidates_for(scope)
	if _targets.is_empty():
		_execute(null)
		return
	_target_index = 0
	_state = State.TARGET
	_refresh()


func _candidates_for(scope: String) -> Array[Battler]:
	match scope:
		"one_ally":
			return system.living_allies()
		"one_ally_dead":
			var fallen: Array[Battler] = []
			for b in system.allies:
				if not b.is_alive():
					fallen.append(b)
			return fallen
		_:
			return system.living_enemies()


func _open_item_menu() -> void:
	_items = GameState.inventory_ids()
	if _items.is_empty():
		return
	_item_index = 0
	_state = State.ITEM
	_refresh()


func _input_item() -> void:
	if Input.is_action_just_pressed("cancel"):
		Sound.play("cancel")
		_state = State.COMMAND
		_refresh()
		return
	if _items.is_empty():
		return
	if Input.is_action_just_pressed("ui_down"):
		_item_index = (_item_index + 1) % _items.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("ui_up"):
		_item_index = (_item_index - 1 + _items.size()) % _items.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("confirm"):
		Sound.play("confirm")
		_choose_item()


func _choose_item() -> void:
	_pending_item = String(_items[_item_index])
	_pending_ability = ""
	_targets = _candidates_for(String(Database.item(_pending_item).get("target", "one_ally")))
	if _targets.is_empty():
		# 生き返らせる相手がいない等。手番を空費させずに戻す。
		Sound.play("cancel")
		_state = State.COMMAND
		_refresh()
		return
	_target_index = 0
	_state = State.TARGET
	_refresh()


func _input_target() -> void:
	if Input.is_action_just_pressed("cancel"):
		Sound.play("cancel")
		_state = State.COMMAND
		_refresh()
		return
	if _targets.is_empty():
		return
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_target_index = (_target_index + 1) % _targets.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_target_index = (_target_index - 1 + _targets.size()) % _targets.size()
		Sound.play("cursor")
		_refresh()
	elif Input.is_action_just_pressed("confirm"):
		_execute(_targets[_target_index])


func _execute(target: Battler) -> void:
	if _pending_item != "":
		# 在庫を減らすのは GameState の仕事。BattleSystem には効果だけを解かせる。
		if not GameState.consume_item(_pending_item):
			_state = State.COMMAND
			_refresh()
			return
		var item_lines := system.use_item(_actor, _pending_item, target)
		Sound.play("heal")
		_pending_item = ""
		_show(item_lines)
		return
	var lines := system.perform(_actor, _pending_ability, target)
	_play_ability_sfx(_pending_ability)
	_show(lines)


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _refresh() -> void:
	if _order_bar != null and system != null:
		_order_bar.set_order(system.turn_order(TurnOrderBar.MAX_SHOWN))
	queue_redraw()


func _draw() -> void:
	if system == null:
		return
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x0E, 0x12, 0x20), true)
	_draw_enemies()
	_draw_message_or_command()
	_draw_party_status()


func _draw_enemies() -> void:
	var foes := system.enemies
	if foes.is_empty():
		return
	var spacing := 256.0 / (foes.size() + 1)
	for i in foes.size():
		var b := foes[i]
		if not b.is_alive():
			continue
		var tex: Texture2D = SPRITES.get(b.sprite, SPRITES["gel"])
		var pos := Vector2(spacing * (i + 1) - tex.get_width() * 0.5, ENEMY_BASELINE - tex.get_height())
		draw_texture(tex, pos.floor())

		# 対象選択中はカーソルを出す
		if _state == State.TARGET and not _targets.is_empty() and _targets[_target_index] == b:
			draw_texture(CURSOR_TEX, Vector2(pos.x + tex.get_width() * 0.5 - 4, pos.y - 10).floor())
			PixelUI.draw_text(self, Vector2(pos.x, pos.y - 12), b.name, PixelUI.C_ACTIVE, 10)


func _draw_message_or_command() -> void:
	PixelUI.draw_window(self, MESSAGE_RECT, WINDOW_TEX)
	var origin := MESSAGE_RECT.position + Vector2(12, 15)

	if _state == State.ITEM:
		for i in _items.size():
			var item_id := String(_items[i])
			var it := Database.item(item_id)
			@warning_ignore("integer_division")
			var pos := origin + Vector2((i / COMMAND_ROWS) * 178, (i % COMMAND_ROWS) * 13)
			if i == _item_index:
				draw_texture(CURSOR_TEX, (pos + Vector2(-8, -8)).floor())
			var tint := PixelUI.C_TEXT if i == _item_index else PixelUI.C_TEXT_DIM
			PixelUI.draw_text(self, pos, String(it.get("name", item_id)), tint, 11)
			PixelUI.draw_text(
				self, pos + Vector2(78, 0),
				"%d こ  待%d" % [
					GameState.item_count(item_id),
					_actor.scaled_cost(int(it.get("cost", 100)))
				],
				PixelUI.C_TEXT_DIM, 9
			)
		return

	if _state == State.COMMAND:
		# カーソルのいるページだけを描く。ページはカーソルに従って自動でめくれる。
		var page := _command_page()
		var first := page * COMMANDS_PER_PAGE
		var last := mini(first + COMMANDS_PER_PAGE, _commands.size())
		for i in range(first, last):
			var ab := Database.ability(_commands[i])
			var slot := i - first
			@warning_ignore("integer_division")
			var col := slot / COMMAND_ROWS
			var row := slot % COMMAND_ROWS
			var pos := origin + Vector2(col * 178, row * 13)
			if i == _command_index:
				draw_texture(CURSOR_TEX, (pos + Vector2(-8, -8)).floor())
			var cost := _actor.scaled_cost(int(ab.get("cost", 100)))
			var mp_cost := int(ab.get("mp", 0))
			if _commands[i] == ITEM_COMMAND:
				var item_color := PixelUI.C_TEXT if i == _command_index else PixelUI.C_TEXT_DIM
				PixelUI.draw_text(self, pos, "どうぐ", item_color, 11)
				PixelUI.draw_text(
					self, pos + Vector2(78, 0),
					"%d こ" % _total_items(), PixelUI.C_TEXT_DIM, 9
				)
				continue
			var label: String = String(ab.get("name", _commands[i]))
			var color := PixelUI.C_TEXT if i == _command_index else PixelUI.C_TEXT_DIM
			PixelUI.draw_text(self, pos, label, color, 11)
			# コストを常に見せる。CTB では「次いつ動けるか」が選択の核心なので隠さない。
			var suffix := "待%d" % cost
			if mp_cost > 0:
				suffix = "MP%d %s" % [mp_cost, suffix]
			PixelUI.draw_text(self, pos + Vector2(78, 0), suffix, PixelUI.C_TEXT_DIM, 9)

		# 続きがあることを隠さない。見えない技を選べる状態が一番たちが悪い。
		if _page_count() > 1:
			var mark := "◀%d/%d▶" % [page + 1, _page_count()]
			PixelUI.draw_text(
				self, Vector2(MESSAGE_RECT.end.x - PixelUI.text_width(mark, 9) - 10,
				MESSAGE_RECT.end.y - 8), mark, PixelUI.C_TEXT_DIM, 9
			)
		return

	for i in _shown.size():
		PixelUI.draw_text(self, origin + Vector2(0, i * 13), _shown[i], PixelUI.C_TEXT, 11)


func _draw_party_status() -> void:
	PixelUI.draw_window(self, STATUS_RECT, WINDOW_TEX)
	var allies := system.allies
	for i in allies.size():
		var b := allies[i]
		# 1 人ぶん 92px を横に 4 つ。名前 / 数値 / ゲージを縦に積む。
		var base := STATUS_RECT.position + Vector2(10 + i * 92, 16)

		var name_color := PixelUI.C_TEXT
		if not b.is_alive():
			name_color = PixelUI.C_HP_LOW
		elif _actor == b and _state in [State.COMMAND, State.TARGET]:
			name_color = PixelUI.C_ACTIVE
		PixelUI.draw_text(self, base, b.name, name_color, 12)
		PixelUI.draw_text(self, base + Vector2(0, 14), "%d/%d" % [b.hp, b.max_hp], PixelUI.C_TEXT_DIM, 10)
		if b.max_mp > 0:
			PixelUI.draw_text(self, base + Vector2(50, 14), "M%d" % b.mp, PixelUI.C_MP, 10)

		var hp_ratio := float(b.hp) / maxf(float(b.max_hp), 1.0)
		PixelUI.draw_gauge(self, Rect2(base.x, base.y + 18, 84, 5), hp_ratio, PixelUI.hp_color(hp_ratio))
