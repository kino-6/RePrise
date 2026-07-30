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
## 敵の絵。数が増えたので preload の列挙はやめ、初回に読んで覚えておく。
## _draw() の中で読むと、読み込み中の白い板が描かれてしまう。
const FALLBACK_SPRITE := "gel"

static var _sprites: Dictionary = {}


static func sprite_of(name: String) -> Texture2D:
	if _sprites.has(name):
		return _sprites[name]
	var path := "res://assets/sprites/%s.png" % name
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		# 絵が無い敵はデータの取りこぼし。落とさずに代わりを出し、テストで拾う。
		push_warning("敵の絵が無い: %s" % name)
		tex = load("res://assets/sprites/%s.png" % FALLBACK_SPRITE)
	_sprites[name] = tex
	return tex

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
## オート中のメッセージ待ち。
##
## **オートは読ませる場面ではない。** 自分で選んでいるときの間は読む時間として
## 要るが、オートに任せているあいだは結果だけ見えればよい。
## 実測で 1 手番あたり約 2 秒かかり、敵 6 体の戦闘が 25 秒になっていた
## （自動プレイの詰まり検出に引っかかるほど）。
const AUTO_LINE_DELAY := 0.10

## オート中の被弾の点滅。自分で選ぶときより短くする。
const AUTO_BLINK := 0.12
const BLINK := 0.3

## 大技の閃光。
const AUTO_FLASH := 0.18
const FLASH := 0.55

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

## オート戦闘の作戦。中身は src/battle/auto_tactic.gd にある。
var _auto: AutoTactic.Mode = AutoTactic.Mode.OFF

## 被弾の点滅の残り時間。
var _blink := 0.0

## 画面フラッシュの強さ（強い魔法が当たった瞬間）。
var _flash := 0.0

## サブウィンドウが開く演出の進み（0..1）。
var _list_open := 1.0


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
	_auto = AutoTactic.last_mode
	set_process(true)
	set_process_unhandled_input(true)
	_refresh()


# --------------------------------------------------------------------------
# 進行
# --------------------------------------------------------------------------


func _process(delta: float) -> void:
	if system == null:
		return
	if _state == State.LIST and _list_open < 1.0:
		_list_open = minf(_list_open + delta * 9.0, 1.0)
		queue_redraw()

	match _state:
		State.TURN_START:
			_begin_turn()
		State.MESSAGE:
			_timer -= delta
			if _timer <= 0.0:
				_advance_message()
			if _blink > 0.0 or _flash > 0.0:
				_blink = maxf(_blink - delta, 0.0)
				_flash = maxf(_flash - delta * 3.0, 0.0)
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
		if _auto != AutoTactic.Mode.OFF:
			_auto_act()
		else:
			_open_root_menu()
	else:
		var lines := system.perform_enemy(_actor)
		_play_ability_sfx(system.last_ability_id)
		_play_status_sfx()
		_show(lines)


## 効果音を選ぶ。
##
## 属性があるならそれを優先する。炎・氷・雷が同じ音で鳴ると、
## 属性を切り替えている手応えが出ない（音の作り分けは tools/gen_audio.py 側）。
func _play_ability_sfx(ability_id: String) -> void:
	var ab := Database.ability(ability_id)
	var element := String(ab.get("element", ""))
	if element in ["fire", "ice", "bolt"]:
		Sound.play(element)
		return
	match String(ab.get("kind", "")):
		"physical":
			Sound.play("hit")
		"magical":
			Sound.play("magic")
		"heal":
			Sound.play("heal")
		_:
			Sound.play("confirm")


## 状態異常がかかった瞬間の音。かかったかどうかは Battler の状態で判断する
## （ログの文字列を読むと、文言を変えた瞬間に鳴らなくなる）。
func _play_status_sfx() -> void:
	for b in system.allies + system.enemies:
		if b.sleep_turns == BattleSystem.SLEEP_TURNS:
			Sound.play("sleep")
			return
		if b.poison_turns == BattleSystem.POISON_TURNS:
			Sound.play("poison")
			return


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
			_cycle_auto()


## オートの作戦を回す（切 → いのち → ガンガン → 切）。
##
## コマンド欄からも、A キーからも、同じここを通す。**入口を 2 つにして
## 中身を 2 つ書くと、片方だけ直したときにずれる。**
func _cycle_auto() -> void:
	_auto = AutoTactic.next_mode(_auto)
	AutoTactic.remember(_auto)
	if _auto == AutoTactic.Mode.OFF:
		_open_root_menu()
	else:
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
	_list_open = 0.0
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
	_play_status_sfx()
	_show(lines)


# --------------------------------------------------------------------------
# にげる / オート
# --------------------------------------------------------------------------


## 逃走。素早さ差で決まる。逃げられれば報酬は無いが、資源を残せる。
## 「勝つ以外の終わり方」があると、消耗戦の判断が一段増える。
## 逃げられる見込み（%）。選ぶ前に読めないと、賭けにすらならない。
func escape_odds() -> int:
	if system == null:
		return 0
	for b in system.enemies:
		if bool(Database.monster(b.source_id).get("boss", false)):
			return 0
	var ours := 0
	for b in system.living_allies():
		ours += b.effective_agi()
	var theirs := 0
	for b in system.living_enemies():
		theirs += b.effective_agi()
	return clampi(45 + (ours - theirs) * 2, 15, 92)


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


## オート戦闘の 1 手。判断は AutoTactic に任せ、ここは実行だけを持つ。
func _auto_act() -> void:
	var plan := AutoTactic.decide(system, _actor, _auto)
	_pending_ability = String(plan["ability"])
	_pending_item = ""
	_execute(plan["target"])


# --------------------------------------------------------------------------
# メッセージ
# --------------------------------------------------------------------------


## 画面を白く飛ばすほどの一撃か。全体攻撃か、威力の高い魔法。
func _is_big_hit(ability_id: String) -> bool:
	var ab := Database.ability(ability_id)
	if String(ab.get("target", "")) == "all_enemies":
		return true
	return String(ab.get("kind", "")) == "magical" and int(ab.get("power", 0)) >= 130


func _show(lines: Array[String]) -> void:
	# 誰かに当たった行動なら点滅させる。当たった相手は BattleSystem が持っている
	# （文字列を見て判断すると、文言を変えた瞬間に演出が消える）。
	# 点滅もオート中は短く。ここが 0.3 のままだと、待ちを詰めても 1 手番が縮まない。
	var blink_time := AUTO_BLINK if _auto != AutoTactic.Mode.OFF else BLINK
	_blink = blink_time if not system.last_hit_ids.is_empty() else 0.0
	# 大技の閃光もオート中は短く。**待ちと点滅だけ詰めても、ここが 0.55 のままだと
	# 大技が出た手番だけ長い。** 詰めるところは 3 つ（待ち・点滅・閃光）。
	if not system.last_hit_ids.is_empty() and _is_big_hit(system.last_ability_id):
		_flash = AUTO_FLASH if _auto != AutoTactic.Mode.OFF else FLASH
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
	# 文字の速さは設定から取る。オート中は手で押さないので短く固定。
	_timer = AUTO_LINE_DELAY if _auto != AutoTactic.Mode.OFF else Settings.line_delay()
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

	# オートは Ｑキーで、**いつでも**切り替えられる。
	#
	# 直したところが 2 つある。
	#   * 最初は A に割り当てたが、A は WASD の「左」でもあるので取り合いになった。
	#   * 状態を COMMAND / LIST / TARGET に限っていたが、**オートが動き出すと
	#     その状態を外れる**ので、一度入れたら二度と切り替えられなかった。
	#     切り替えは戦闘中いつでも通す（止め方が無いオートは信用されない）。
	if event.is_action_pressed("auto"):
		Sound.play("confirm")
		_cycle_auto()
		return

	match _state:
		State.COMMAND:
			_input_root(event)
		State.LIST:
			_input_list(event)
		State.TARGET:
			_input_target(event)
		State.MESSAGE:
			# キャンセルはオートの解除を優先する（送りは決定キーでできる）。
			if _auto != AutoTactic.Mode.OFF and event.is_action_pressed("cancel"):
				_auto = AutoTactic.Mode.OFF
				Sound.play("cancel")
				_refresh()
			elif event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
				# 押すたびに 1 行進む。待たされないことが連打の手応えになる。
				_timer = 0.0
				_advance_message()
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
	PixelUI.ui_frame()
	if system == null:
		return
	_draw_backdrop()
	_draw_enemies()
	_draw_message_or_command()
	_draw_party_status()
	if _state == State.LIST:
		_draw_list()
	# フラッシュは最前面。窓の上に乗らないと「画面が光った」に見えない。
	PixelUI.draw_flash(self, _flash)


## 足元の影。楕円を横に潰した帯で描く（draw_circle だと丸すぎる）。
func _draw_ground_shadow(center: Vector2, radius: float) -> void:
	var rows := 5
	for i in rows:
		var k := float(i) / float(rows - 1)
		# 中央が濃く、縁へ向かって薄く細く
		var w := radius * (1.0 - absf(k - 0.5) * 1.4)
		var a := 0.34 * (1.0 - absf(k - 0.5) * 1.2)
		draw_rect(
			Rect2(center.x - w, center.y - rows * 0.5 + i, w * 2.0, 1.0),
			Color(0.0, 0.0, 0.04, a), true
		)


## 戦場の背景。
##
## **一枚の階調で塗るだけでは「場所」にならない。** 後期 SFC の戦闘背景が
## richer に見えたのは、空と地面が別の階調で、その境目に地平線があり、
## 地面に敵の影が落ちていたから。ここは絵を足さずに階調と影だけで作る。
##
## 空は上を暗く、地平に向かって少し明るく。地面は地平で明るく、手前で沈ませる。
## 境目に 1 本明線を置くと、そこが「立っている面」だと読める。
const HORIZON := 118.0


## 生物相ごとの戦闘背景。**あれば使い、無ければ階調へ落ちる。**
##
## 絵が 1 枚も無くても遊べること、というのが取り込みの前提なので、
## 階調背景は消さずに残す（`docs/asset_generation_npc_effects.md` の方針）。
const BATTLE_BG := {
	"grassland": "grassland_twilight",
	"forest": "grassland_twilight",
	"wetland": "drowned_wetland",
	"snowfield": "snowfield_ruins",
	"volcano": "volcanic_caldera",
	"badland": "dungeon_depths",
	"desert": "dungeon_depths",
	# 城の中。生物相ではないので `@` を付けて土地の名と混ざらないようにする。
	"@castle": "imperial_foundry",
}

static var _bg_cache: Dictionary = {}


static func backdrop_of(biome: String) -> Texture2D:
	if _bg_cache.has(biome):
		return _bg_cache[biome]
	var name := String(BATTLE_BG.get(biome, ""))
	var tex: Texture2D = null
	if name != "":
		var path := "res://assets/backgrounds/battle_bg_%s.png" % name
		tex = load(path) if ResourceLoader.exists(path) else null
	_bg_cache[biome] = tex
	return tex


func _draw_backdrop() -> void:
	# 絵があればそれを敷く。2 倍にした敵が広い空白に浮くのを止めるのが目的。
	# 城の中は生物相ではなく城の絵にする（帝国工廠）。**主戦だけ別の場所に見える。**
	var here := GameState.biome_here()
	if String(GameState.site.get("kind", "")) == "castle":
		here = "@castle"
	var art := backdrop_of(here)
	if art != null:
		draw_texture_rect(art, Rect2(0, 0, PixelUI.SCREEN.x, HORIZON + 58.0), false)
		return
	_draw_gradient_backdrop()


## 絵が無いときの背景。**消さずに残す**（1 枚も無くても遊べることが前提）。
func _draw_gradient_backdrop() -> void:
	var biome := GameState.biome_here()
	var ground_top: Color = GROUND_TOP.get(biome, GROUND_TOP["_"])
	var ground_bottom: Color = GROUND_BOTTOM.get(biome, GROUND_BOTTOM["_"])

	# 空
	PixelUI.draw_gradient(
		self, Rect2(0, 0, PixelUI.SCREEN.x, HORIZON),
		Color8(0x04, 0x06, 0x10), Color8(0x1E, 0x26, 0x4C), 12
	)
	# 地面。手前へ向かって沈ませると奥行きが出る。
	PixelUI.draw_gradient(
		self, Rect2(0, HORIZON, PixelUI.SCREEN.x, PixelUI.SCREEN.y - HORIZON),
		ground_top, ground_bottom, 14
	)
	# 地平線。1 本入れるだけで空と地面が別の面になる。
	draw_rect(Rect2(0, HORIZON, PixelUI.SCREEN.x, 1), Color8(0x50, 0x60, 0x98), true)


## 地面の色は土地ごとに変える。雪原で戦っているのに土色だと、
## せっかく生物相を持たせた意味が薄れる。
const GROUND_TOP := {
	"_": Color8(0x24, 0x2C, 0x50),
	"grassland": Color8(0x2E, 0x4A, 0x2A),
	"forest": Color8(0x24, 0x3C, 0x24),
	"wetland": Color8(0x22, 0x34, 0x2C),
	"badland": Color8(0x40, 0x34, 0x22),
	"desert": Color8(0x54, 0x44, 0x2A),
	"snowfield": Color8(0x50, 0x58, 0x70),
	"volcano": Color8(0x48, 0x22, 0x1C),
}
const GROUND_BOTTOM := {
	"_": Color8(0x0A, 0x0C, 0x1E),
	"grassland": Color8(0x10, 0x1C, 0x12),
	"forest": Color8(0x0C, 0x16, 0x0E),
	"wetland": Color8(0x0C, 0x14, 0x12),
	"badland": Color8(0x18, 0x12, 0x0C),
	"desert": Color8(0x22, 0x1A, 0x10),
	"snowfield": Color8(0x1C, 0x20, 0x30),
	"volcano": Color8(0x1C, 0x0A, 0x08),
}


## 敵を描く。
##
## **等倍で出していたので、顔も装備も主の格も潰れていた。**
## 48x48 や 64x64 を 512x320 にそのまま置くと、SFC 期の敵より小さい。
## 最近傍の 2 倍で出す ―― **半端な倍率は使わない**（ドットが滲む）。
##
## 位置・影・カーソル・状態・数字は**すべて表示矩形から計算する**。
## 絵の元寸から計算していると、倍率を変えるたびに全部がずれる。
const ENEMY_SCALE := 2.0

## 奥の段の持ち上げ（表示寸法に対する割合ではなく固定）。
## 真上に重ねると 1 体に見えるので、上へ逃がして右へずらす。
const BACK_ROW_LIFT := 30.0
const BACK_ROW_SHIFT := 22.0


func _draw_enemies() -> void:
	var foes := system.enemies
	if foes.is_empty():
		return

	# 1 行に何体置けるかは**表示寸法**から決める。いちばん広い絵に合わせる。
	var widest := 0.0
	for b in foes:
		widest = maxf(widest, sprite_of(b.sprite).get_width() * ENEMY_SCALE)
	var fit := maxi(int(PixelUI.SCREEN.x / maxf(widest + 8.0, 1.0)), 1)
	var per_row := mini(foes.size(), maxi(fit, 1))
	if foes.size() > fit:
		per_row = int(ceil(foes.size() / 2.0))
	var spacing := float(PixelUI.SCREEN.x) / (per_row + 1)
	var highlighted := _highlighted_targets()

	for i in foes.size():
		var b := foes[i]
		if not b.is_alive():
			continue
		# 当たった相手は一瞬だけ消して点滅させる。SFC 期の被弾表現で、
		# ダメージの数字が出るより先に「どこに効いたか」が分かる。
		if _blink > 0.0 and b.id in system.last_hit_ids and fmod(_blink, 0.12) > 0.06:
			continue

		var tex: Texture2D = sprite_of(b.sprite)
		var size := tex.get_size() * ENEMY_SCALE
		@warning_ignore("integer_division")
		var tier := i / per_row
		var slot := i % per_row
		var rect := Rect2(
			Vector2(
				spacing * (slot + 1) - size.x * 0.5 + tier * BACK_ROW_SHIFT,
				ENEMY_BASELINE - size.y - tier * BACK_ROW_LIFT
			).floor(),
			size
		)

		# 足元の影。これが無いと敵が宙に浮いて見える。
		_draw_ground_shadow(Vector2(rect.get_center().x, rect.end.y - 1.0), size.x * 0.40)
		# 最近傍で 2 倍。整数倍なのでドットは崩れない。
		draw_texture_rect(tex, rect, false)

		# 受けたダメージを相手の上に出す。メッセージ窓の文字だけだと
		# 「どこに何が起きたか」が数字と場所で結び付かない。
		if _blink > 0.0 and system.last_hit_amount.has(b.id):
			var text := "%d" % int(system.last_hit_amount[b.id])
			var lift := (0.3 - _blink) * 26.0
			PixelUI.draw_text(
				self,
				Vector2(rect.get_center().x - PixelUI.text_width(text) * 0.5, rect.position.y - 22 - lift),
				text, PixelUI.C_ACTIVE
			)

		# 状態異常は敵にも出す。眠らせた相手が分からないと意味が無い。
		var tag := b.status_tag()
		if tag != "":
			PixelUI.draw_text(
				self, Vector2(rect.position.x, rect.position.y - 14), tag,
				PixelUI.C_MP, PixelUI.SIZE_SUB
			)

		if b in highlighted:
			draw_texture(
				CURSOR_TEX, Vector2(rect.get_center().x - 4, rect.position.y - 12).floor()
			)
			PixelUI.draw_text(
				self,
				Vector2(rect.get_center().x - PixelUI.text_width(b.name) * 0.5, rect.position.y - 30),
				b.name, PixelUI.C_ACTIVE
			)


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
		# オート中は右上に作戦を出しているので、その幅ぶん狭めて折り返す
		# （切らずに置いたら 42px 重なった）。
		var width := 300.0 if _auto != AutoTactic.Mode.OFF else 460.0
		PixelUI.draw_text(
			self, origin + Vector2(0, i * 19),
			PixelUI.clip(_shown[i], width, PixelUI.SIZE_TEXT), PixelUI.C_TEXT
		)

	# オート中は止め方を出す。始め方だけ見えていて止め方が見えないのは不親切で、
	# 「戻れなくなった」と思われる。
	#
	# **作戦の説明は隅に出さない。** 戦闘中の隅に長い文を置くと、読まないのに
	# 場所を取るだけになる。呼び名（守備重視 / 攻撃重視）で足りる。
	if _auto != AutoTactic.Mode.OFF:
		PixelUI.draw_text_right(
			self, Vector2(MESSAGE_RECT.end.x - 12, MESSAGE_RECT.position.y + 6),
			"%s　Ｑ きりかえ　Ｘ かいじょ" % AutoTactic.label(_auto),
			PixelUI.C_ACTIVE, PixelUI.SIZE_SUB
		)


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
		if _roots[i] == Root.AUTO:
			label = AutoTactic.label(_auto)
			# カーソルが乗っているときは、押すと何になるかとその基準を出す。
			if on:
				var next_auto := AutoTactic.next_mode(_auto)
				PixelUI.draw_text_right(
					self, Vector2(MESSAGE_RECT.end.x - 12, MESSAGE_RECT.end.y - 22),
					"→ %s" % AutoTactic.label(next_auto),
					PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
				)
		# 逃げられる見込みを添える。0% は主（逃げられない相手）。
		if _roots[i] == Root.ESCAPE:
			var odds := escape_odds()
			label = "にげる ×" if odds <= 0 else "にげる %d%%" % odds
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if _roots[i] == Root.AUTO and _auto != AutoTactic.Mode.OFF:
			tint = PixelUI.C_ACTIVE
		PixelUI.draw_text(self, at, label, tint)


## じゅもん / とくぎ / どうぐ のサブウィンドウ。
##
## 「待70」が何のことか分からない、という指摘への答えがこの窓の見出し。
## MP と「つぎのてばんまで」を列見出しとして常に出し、数字の意味を画面内で閉じる。
func _draw_list() -> void:
	# 開く途中は枠だけ伸ばして、中身は開き終わってから出す。
	if _list_open < 1.0:
		PixelUI.draw_window(self, PixelUI.opening(LIST_RECT, _list_open), WINDOW_TEX)
		return
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	var inner := PixelUI.content(LIST_RECT)
	var origin := inner.position + Vector2(16, 0)

	PixelUI.draw_text(self, origin + Vector2(150, 2), "MP", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	PixelUI.draw_text(
		self, origin + Vector2(184, 2), "つぎのてばん", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
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
		if _blink > 0.0 and system.last_hit_amount.has(b.id):
			PixelUI.draw_text(
				self, base + Vector2(0, -18), "-%d" % int(system.last_hit_amount[b.id]),
				PixelUI.C_HP_LOW
			)
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
