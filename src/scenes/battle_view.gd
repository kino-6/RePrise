class_name BattleView
extends Node2D

## 戦闘画面。BattleSystem（ロジック）に対する表示と入力だけを担当する。
##
## コマンドは 2 階層。第 1 階層（たたかう / じゅもん / とくぎ / どうぐ / ぼうぎょ /
## にげる / オート）を常に同じ並びで出し、じゅもんと とくぎ と どうぐ だけ
## サブウィンドウを開く。技を全部 1 枚に並べると、覚えるほど選べなくなる。
##
## 画面配置（512x320）
##   y   2.. 22  行動順バー（＋敵の予告）
##   y  28..170  敵
##   y 176..242  メッセージ窓 / コマンド窓
##   y 248..312  パーティ状態（4 人を横 1 列）

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

const MESSAGE_RECT := Rect2(8, 176, 496, 66)
const STATUS_RECT := Rect2(8, 248, 496, 64)
## サブウィンドウ（じゅもん・とくぎ・どうぐ）。敵の上に浮かせる。
const LIST_RECT := Rect2(8, 40, 288, 132)
const ENEMY_BASELINE := 168

## 第 1 階層は 4 列 x 2 行。
const ROOT_COL := 122
const ROOT_LINE := 22
const ROOT_COLS := 4

## サブウィンドウは 1 列。行数はこれを超えたらページ送り。
const LIST_ROWS := 4
const LIST_LINE := 20

const LINE_DELAY := 0.55
## オート戦闘のときのメッセージ送り。手で押さないので短くする。
const AUTO_LINE_DELAY := 0.28

enum State { TURN_START, COMMAND, LIST, TARGET, MESSAGE, DONE }

## 第 1 階層の項目。順番は固定する（毎回同じ位置にあることが速さになる）。
enum Root { FIGHT, SPELL, SKILL, ITEM, GUARD, ESCAPE, AUTO }

const ROOT_LABELS := {
	Root.FIGHT: "たたかう",
	Root.SPELL: "じゅもん",
	Root.SKILL: "とくぎ",
	Root.ITEM: "どうぐ",
	Root.GUARD: "ぼうぎょ",
	Root.ESCAPE: "にげる",
	Root.AUTO: "オート",
}

var system: BattleSystem = null
var members: Array[PartyMember] = []

var _state: State = State.TURN_START
var _actor: Battler = null
var _queue: Array[String] = []
var _shown: Array[String] = []
var _timer := 0.0

## 第 1 階層
var _roots: Array[int] = []
var _root_index := 0

## サブウィンドウ（"spell" / "skill" / "item"）
var _list_kind := ""
var _list_ids: Array[String] = []
var _list_index := 0

var _targets: Array[Battler] = []
var _target_index := 0
var _pending_ability := ""
var _pending_item := ""

var _order_bar: TurnOrderBar = null
var _victory := false
var _outcome_shown := false
var _escaped := false

## オート戦闘。SFC 期の「さくせん」に当たるもので、雑魚戦のテンポのために置く。
## 中身は「傷が深い者がいれば回復、いなければ一番効く攻撃」の 1 本だけ。
var _auto := false

## 被弾の点滅の残り時間。
var _blink := 0.0


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
	_escaped = false
	_auto = false
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
			if _blink > 0.0:
				_blink = maxf(_blink - delta, 0.0)
				queue_redraw()
		_:
			pass


func _begin_turn() -> void:
	if system.is_over or _escaped:
		_finish()
		return
	_actor = system.begin_turn()
	if _actor == null:
		_finish()
		return

	# 毒の進行と眠りの判定。眠っていれば手番を飛ばす。
	var head: Dictionary = system.begin_turn_effects(_actor)
	if not (head["lines"] as Array).is_empty():
		var head_lines: Array[String] = []
		head_lines.assign(head["lines"])
		_show(head_lines)
		return
	if bool(head["skipped"]):
		return

	_refresh()
	if _actor.is_ally:
		if _auto:
			_auto_act()
		else:
			_open_root_menu()
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


## 開発用。サブウィンドウの見え方を撮るのに使う。
func debug_open_item_menu() -> void:
	if _state != State.COMMAND:
		return
	_open_list("item")


func debug_open_spell_menu() -> void:
	if _state != State.COMMAND:
		return
	_open_list("skill")


# --------------------------------------------------------------------------
# 第 1 階層
# --------------------------------------------------------------------------


## その者が使える技を、サブメニュー別に分けて返す。
func _abilities_in(menu: String) -> Array[String]:
	var result: Array[String] = []
	for id in system.usable_abilities(_actor):
		if String(Database.ability(id).get("menu", "")) == menu:
			result.append(id)
	return result


func _open_root_menu() -> void:
	_roots.clear()
	_roots.append(Root.FIGHT)
	if not _abilities_in("spell").is_empty():
		_roots.append(Root.SPELL)
	if not _abilities_in("skill").is_empty():
		_roots.append(Root.SKILL)
	if not GameState.inventory.is_empty():
		_roots.append(Root.ITEM)
	_roots.append(Root.GUARD)
	_roots.append(Root.ESCAPE)
	_roots.append(Root.AUTO)
	_root_index = 0
	_pending_item = ""
	_pending_ability = ""
	_state = State.COMMAND
	_refresh()


func _input_root(event: InputEvent) -> void:
	if _roots.is_empty():
		return
	if event.is_action_pressed("ui_right"):
		_move_root(+1)
	elif event.is_action_pressed("ui_left"):
		_move_root(-1)
	elif event.is_action_pressed("ui_down"):
		_move_root(ROOT_COLS)
	elif event.is_action_pressed("ui_up"):
		_move_root(-ROOT_COLS)
	elif event.is_action_pressed("confirm"):
		Sound.play("confirm")
		_choose_root()


func _move_root(delta: int) -> void:
	_root_index = posmod(_root_index + delta, _roots.size())
	Sound.play("cursor")
	_refresh()


func _choose_root() -> void:
	match _roots[_root_index]:
		Root.FIGHT:
			_begin_ability("attack")
		Root.GUARD:
			_begin_ability("guard")
		Root.SPELL:
			_open_list("spell")
		Root.SKILL:
			_open_list("skill")
		Root.ITEM:
			_open_list("item")
		Root.ESCAPE:
			_try_escape()
		Root.AUTO:
			_auto = true
			_auto_act()


# --------------------------------------------------------------------------
# サブウィンドウ
# --------------------------------------------------------------------------


func _open_list(kind: String) -> void:
	_list_kind = kind
	_list_ids.clear()
	if kind == "item":
		for id in GameState.inventory_ids():
			_list_ids.append(String(id))
	else:
		_list_ids = _abilities_in(kind)
	if _list_ids.is_empty():
		Sound.play("cancel")
		return
	_list_index = 0
	_state = State.LIST
	_refresh()


func _input_list(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.COMMAND
		_refresh()
		return
	if _list_ids.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		_list_index = (_list_index + 1) % _list_ids.size()
		Sound.play("cursor")
		_refresh()
	elif event.is_action_pressed("ui_up"):
		_list_index = (_list_index - 1 + _list_ids.size()) % _list_ids.size()
		Sound.play("cursor")
		_refresh()
	elif event.is_action_pressed("confirm"):
		Sound.play("confirm")
		if _list_kind == "item":
			_begin_item(_list_ids[_list_index])
		else:
			_begin_ability(_list_ids[_list_index])


# --------------------------------------------------------------------------
# 対象選び
# --------------------------------------------------------------------------


func _begin_ability(ability_id: String) -> void:
	_pending_item = ""
	_pending_ability = ability_id
	var scope := String(Database.ability(ability_id).get("target", "one_enemy"))
	_begin_target(scope)


func _begin_item(item_id: String) -> void:
	_pending_item = item_id
	_pending_ability = ""
	_begin_target(String(Database.item(item_id).get("target", "one_ally")))


func _begin_target(scope: String) -> void:
	# 単体指定が要らないものはそのまま実行
	if scope in ["self", "all_enemies", "all_allies"]:
		_execute(null)
		return
	_targets = _candidates_for(scope)
	if _targets.is_empty():
		# 生き返らせる相手がいない等。手番を空費させずに戻す。
		Sound.play("cancel")
		_state = State.COMMAND
		_refresh()
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


func _input_target(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.LIST if _list_kind != "" and _pending_ability != "attack" else State.COMMAND
		if _state == State.LIST and _list_ids.is_empty():
			_state = State.COMMAND
		_refresh()
		return
	if _targets.is_empty():
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_target_index = (_target_index + 1) % _targets.size()
		Sound.play("cursor")
		_refresh()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_target_index = (_target_index - 1 + _targets.size()) % _targets.size()
		Sound.play("cursor")
		_refresh()
	elif event.is_action_pressed("confirm"):
		_execute(_targets[_target_index])


func _execute(target: Battler) -> void:
	_list_kind = ""
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
# にげる / オート
# --------------------------------------------------------------------------


## 逃走。素早さ差で決まる。逃げられれば報酬は無いが、資源を残せる。
## 「勝つ以外の終わり方」があると、消耗戦の判断が一段増える。
func _try_escape() -> void:
	var ours := 0
	for b in system.living_allies():
		ours += b.effective_agi()
	var theirs := 0
	for b in system.living_enemies():
		theirs += b.effective_agi()
	var odds := 45 + (ours - theirs) * 2
	if system.enemies.any(func(b: Battler) -> bool:
		return bool(Database.monster(b.source_id).get("boss", false))):
		# 主からは逃げられない。ここで逃げられると終わりが無くなる。
		_show(["しかし　まわりこまれてしまった！"] as Array[String])
		return
	if system.rng.chance(clampi(odds, 15, 92)):
		_escaped = true
		Sound.play("cancel")
		_show(["パーティは にげだした！"] as Array[String])
	else:
		_show(["しかし　まわりこまれてしまった！"] as Array[String])


## オート戦闘の 1 手。DQ4 の「いのちだいじに」に近い素朴な指針にしてある。
## 賢さより読みやすさを優先する（何をするか分からない自動戦闘は使われない）。
func _auto_act() -> void:
	var hurt := _most_hurt_ally()
	if hurt != null:
		var heal_id := _best_heal()
		if heal_id != "":
			_pending_ability = heal_id
			_pending_item = ""
			_execute(hurt)
			return

	var attack_id := _best_attack()
	_pending_ability = attack_id
	_pending_item = ""
	var scope := String(Database.ability(attack_id).get("target", "one_enemy"))
	if scope in ["self", "all_enemies", "all_allies"]:
		_execute(null)
		return
	var foes := system.living_enemies()
	_execute(foes[0] if not foes.is_empty() else null)


func _most_hurt_ally() -> Battler:
	var worst: Battler = null
	for b in system.living_allies():
		if b.hp * 100 / maxi(b.max_hp, 1) <= 45:
			if worst == null or b.hp * 100 / b.max_hp < worst.hp * 100 / worst.max_hp:
				worst = b
	return worst


func _best_heal() -> String:
	for id in system.usable_abilities(_actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) == "heal" and String(ab.get("target", "")) == "one_ally":
			return id
	return ""


## いちばん期待値の高い攻撃。属性の相性までは見ない（見ると読めなくなる）。
func _best_attack() -> String:
	var best := "attack"
	var best_power := 0
	for id in system.usable_abilities(_actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) not in ["physical", "magical"]:
			continue
		var power := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		# 手番の重さで割る。CTB では「1 手あたり」ではなく「時間あたり」が効率。
		power = power * 100 / maxi(int(ab.get("cost", 100)), 1)
		if power > best_power:
			best_power = power
			best = id
	return best


# --------------------------------------------------------------------------
# メッセージ
# --------------------------------------------------------------------------


func _show(lines: Array[String]) -> void:
	# 誰かに当たった行動なら点滅させる。当たった相手は BattleSystem が持っている
	# （文字列を見て判断すると、文言を変えた瞬間に演出が消える）。
	_blink = 0.3 if not system.last_hit_ids.is_empty() else 0.0
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
	_timer = AUTO_LINE_DELAY if _auto else LINE_DELAY
	_refresh()


func _after_messages() -> void:
	if _escaped:
		_finish()
		return
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
		lines.append("%d の けいけんちと %d %sを えた" % [reward["exp"], reward["gold"], Terms.GOLD])
		GameState.earn_gold(int(reward["gold"]))
		GameState.kills += system.enemies.size()

		# ぬすんだ道具はここで持ち物へ入れる（戦闘ロジックは持ち物に触らない）。
		for item_id in reward.get("items", []):
			GameState.add_item(String(item_id))

		# 「手の記憶」を買っているぶんだけ熟練の入りが良くなる。
		var mastery := int(reward["mastery"])
		mastery += mastery * GameState.upgrade_value("mastery_gain") / 100

		for m in members:
			if m.hp <= 0:
				continue  # 倒れていた者には入らない
			if m.gain_exp(int(reward["exp"])) > 0:
				lines.append("%sは レベル %d に あがった！" % [m.name, m.level])
			for ability_id in m.gain_mastery(mastery):
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
	# 逃げた場合は「負けていないが勝ってもいない」。ランは続く。
	battle_finished.emit(_victory or _escaped)


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


## 入力はイベントそのもので判定する。Input.is_action_just_pressed() を
## _unhandled_input の中で見ると、1 フレームに 2 つ届いた入力を取りこぼす
## （連打が効かない、の正体がこれだった）。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match _state:
		State.COMMAND:
			_input_root(event)
		State.LIST:
			_input_list(event)
		State.TARGET:
			_input_target(event)
		State.MESSAGE:
			if event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
				# 押すたびに 1 行進む。待たされないことが連打の手応えになる。
				_timer = 0.0
				_advance_message()
			# オート中はどのキーでも解除できる
			elif _auto:
				_auto = false
		_:
			pass


func _total_items() -> int:
	var total := 0
	for id in GameState.inventory_ids():
		total += GameState.item_count(String(id))
	return total


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _refresh() -> void:
	if _order_bar != null and system != null:
		_order_bar.set_order(system.turn_order(TurnOrderBar.MAX_SHOWN))
		_order_bar.set_telegraph(_telegraph())
	queue_redraw()


## 敵の予告。行動順の先頭にいる敵が次に何をするかを 1 行で出す。
## 相手の手が見えていないと、こちらが手を変える理由が生まれない。
func _telegraph() -> String:
	if system == null:
		return ""
	for b in system.turn_order(6):
		if b.is_ally or b.planned_ability == "":
			continue
		var ab := Database.ability(b.planned_ability)
		return "%s は %s の かまえ" % [b.name, ab.get("name", b.planned_ability)]
	return ""


func _draw() -> void:
	if system == null:
		return
	# 一色で塗ると背景が「無い」ように見える。上を暗く、床の高さを明るく。
	PixelUI.draw_gradient(
		self, Rect2(Vector2.ZERO, PixelUI.SCREEN),
		Color8(0x06, 0x08, 0x12), Color8(0x1C, 0x22, 0x3C)
	)
	_draw_enemies()
	_draw_message_or_command()
	_draw_party_status()
	if _state == State.LIST:
		_draw_list()


func _draw_enemies() -> void:
	var foes := system.enemies
	if foes.is_empty():
		return
	# 画面の幅に等間隔で置く。1 体なら中央に来る。
	var spacing := float(PixelUI.SCREEN.x) / (foes.size() + 1)
	var highlighted := _highlighted_targets()
	for i in foes.size():
		var b := foes[i]
		if not b.is_alive():
			continue
		# 当たった相手は一瞬だけ消して点滅させる。SFC 期の被弾表現で、
		# ダメージの数字が出るより先に「どこに効いたか」が分かる。
		if _blink > 0.0 and b.id in system.last_hit_ids and fmod(_blink, 0.12) > 0.06:
			continue
		var tex: Texture2D = SPRITES.get(b.sprite, SPRITES["gel"])
		var pos := Vector2(spacing * (i + 1) - tex.get_width() * 0.5, ENEMY_BASELINE - tex.get_height())
		draw_texture(tex, pos.floor())

		# 状態異常は敵にも出す。眠らせた相手が分からないと意味が無い。
		var tag := b.status_tag()
		if tag != "":
			PixelUI.draw_text(
				self, Vector2(pos.x, pos.y - 16), tag, PixelUI.C_MP, PixelUI.SIZE_SUB
			)

		if b in highlighted:
			draw_texture(CURSOR_TEX, Vector2(pos.x + tex.get_width() * 0.5 - 4, pos.y - 12).floor())
			PixelUI.draw_text(self, Vector2(pos.x, pos.y - 32), b.name, PixelUI.C_ACTIVE)


## いま狙っている相手。グループ技なら同じ種族をまとめて光らせる。
func _highlighted_targets() -> Array[Battler]:
	var result: Array[Battler] = []
	if _state != State.TARGET or _targets.is_empty():
		return result
	var chosen := _targets[_target_index]
	if chosen.is_ally:
		return result
	var scope := String(Database.ability(_pending_ability).get("target", "one_enemy"))
	if scope == "group_enemy":
		return system.group_of(chosen)
	result.append(chosen)
	return result


func _draw_message_or_command() -> void:
	PixelUI.draw_window(self, MESSAGE_RECT, WINDOW_TEX)
	var origin := PixelUI.content(MESSAGE_RECT).position + Vector2(14, 0)

	if _state in [State.COMMAND, State.LIST, State.TARGET]:
		_draw_root_menu(origin)
		return

	for i in _shown.size():
		PixelUI.draw_text(self, origin + Vector2(0, i * 19), _shown[i], PixelUI.C_TEXT)


func _draw_root_menu(origin: Vector2) -> void:
	for i in _roots.size():
		@warning_ignore("integer_division")
		var col := i % ROOT_COLS
		var row := i / ROOT_COLS
		var at := origin + Vector2(col * ROOT_COL, row * ROOT_LINE)
		var on := i == _root_index and _state == State.COMMAND
		if on:
			draw_texture(CURSOR_TEX, (at + Vector2(-14, 2)).floor())
		var label := String(ROOT_LABELS[_roots[i]])
		if _roots[i] == Root.AUTO and _auto:
			label = "オート中"
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if _roots[i] == Root.AUTO and _auto:
			tint = PixelUI.C_ACTIVE
		PixelUI.draw_text(self, at, label, tint)


## じゅもん / とくぎ / どうぐ のサブウィンドウ。
##
## 「待70」が何のことか分からない、という指摘への答えがこの窓の見出し。
## MP と「つぎのてばんまで」を列見出しとして常に出し、数字の意味を画面内で閉じる。
func _draw_list() -> void:
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	var inner := PixelUI.content(LIST_RECT)
	var origin := inner.position + Vector2(16, 0)

	PixelUI.draw_text(self, origin + Vector2(150, 2), "MP", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	PixelUI.draw_text(
		self, origin + Vector2(184, 2), "つぎのてばんまで", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)

	var first := (_list_index / LIST_ROWS) * LIST_ROWS
	for i in range(first, mini(first + LIST_ROWS, _list_ids.size())):
		var at := origin + Vector2(0, 20 + (i - first) * LIST_LINE)
		var on := i == _list_index and _state == State.LIST
		if on:
			draw_texture(CURSOR_TEX, (at + Vector2(-14, 2)).floor())
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM

		if _list_kind == "item":
			var it := Database.item(_list_ids[i])
			PixelUI.draw_text(self, at, String(it.get("name", _list_ids[i])), tint)
			PixelUI.draw_text(
				self, at + Vector2(150, 2), "%d こ" % GameState.item_count(_list_ids[i]),
				PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
			)
			PixelUI.draw_text(
				self, at + Vector2(192, 2),
				"%d" % _actor.scaled_cost(int(it.get("cost", 100))),
				PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
			)
			continue

		var ab := Database.ability(_list_ids[i])
		PixelUI.draw_text(self, at, String(ab.get("name", _list_ids[i])), tint)
		var mp := int(ab.get("mp", 0))
		PixelUI.draw_text(
			self, at + Vector2(150, 2), "%d" % mp if mp > 0 else "-",
			PixelUI.C_MP if mp > 0 else PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		PixelUI.draw_text(
			self, at + Vector2(192, 2), "%d" % _actor.scaled_cost(int(ab.get("cost", 100))),
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)

	# 説明文。選んでいるものが何をするかは、常に見えていてよい。
	var desc := ""
	if _list_index < _list_ids.size():
		var data := (
			Database.item(_list_ids[_list_index]) if _list_kind == "item"
			else Database.ability(_list_ids[_list_index])
		)
		desc = String(data.get("desc", ""))
	PixelUI.draw_text(
		self, Vector2(inner.position.x + 4, inner.end.y - 18), desc,
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)


func _draw_party_status() -> void:
	PixelUI.draw_window(self, STATUS_RECT, WINDOW_TEX)
	var allies := system.allies
	var inner := PixelUI.content(STATUS_RECT)
	var aiming: Battler = null
	if _state == State.TARGET and not _targets.is_empty() and _targets[_target_index].is_ally:
		aiming = _targets[_target_index]

	for i in allies.size():
		var b := allies[i]
		# 1 人ぶん 122px を横に 4 つ。名前 / 数値 / ゲージを縦に積む。
		var base := inner.position + Vector2(6 + i * 122, 2)

		var name_color := PixelUI.C_TEXT
		if not b.is_alive():
			name_color = PixelUI.C_HP_LOW
		elif _actor == b and _state in [State.COMMAND, State.LIST, State.TARGET]:
			name_color = PixelUI.C_ACTIVE
		# 味方を狙っているときは、その者にカーソルを出す。
		# これが無いと「回復が自分にしか使えない」ように見える。
		if aiming == b:
			draw_texture(CURSOR_TEX, (base + Vector2(-12, 3)).floor())
			name_color = PixelUI.C_ACTIVE

		PixelUI.draw_text(self, base, b.name, name_color)
		var tag := b.status_tag()
		if tag != "":
			PixelUI.draw_text(self, base + Vector2(62, 2), tag, PixelUI.C_HP_LOW, PixelUI.SIZE_SUB)
		PixelUI.draw_text(
			self, base + Vector2(0, 20), "%d/%d" % [b.hp, b.max_hp],
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		if b.max_mp > 0:
			PixelUI.draw_text(self, base + Vector2(66, 20), "M%d" % b.mp, PixelUI.C_MP, PixelUI.SIZE_SUB)

		var hp_ratio := float(b.hp) / maxf(float(b.max_hp), 1.0)
		PixelUI.draw_gauge(self, Rect2(base.x, base.y + 38, 112, 5), hp_ratio, PixelUI.hp_color(hp_ratio))
