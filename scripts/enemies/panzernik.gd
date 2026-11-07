class_name Panzernik
extends Enemy
## Враг «Панцирник» (символ p): пещерная мокрица в каменном панцире. 30 HP, +12 к силе.
##   * ходит враскачку, а заметив игрока на своей высоте, дрожит (CURL, 0,6 с — успей
##     отбежать или подготовиться), сворачивается в шар и катится на него (ROLL, 9 клеток
##     в секунду, 12 урона при касании) до стены или до конца разбега;
##   * свёрнутого (и катящегося) пробить почти нельзя: он получает в 4 раза меньше урона;
##   * врезавшись в стену, оглушён на 1,6 с (DIZZY) — тогда урон вдвое больше обычного.
## Умный: ищет путь к игроку, ждёт своей очереди в стае, не катится, пока игрок за щитом,
## и обходит ловушки (как остальные умные враги); на лёгкой катится, только если игрок
## прямо перед ним, и не ищет путь.
## Анимации — assets/frames/panzernik.tres (кадры из design/source).

enum State { IDLE, WALK, CURL, ROLL, DIZZY, DEAD }

@export_group("Панцирник")
## Дальше этого расстояния (клетки) панцирник игрока не замечает.
@export var aggro_range_tiles := 8.0
@export var walk_speed_tiles := 2.0
## Начинает качение, когда игрок ближе этого (клетки) и на одной с ним высоте.
@export var roll_range_tiles := 7.0
@export var roll_speed_tiles := 9.0
@export var roll_damage := 12
## Пауза между качениями, сек.
@export var roll_cooldown := 2.5
## Дрожь перед качением, сек.
@export var curl_time := 0.6
## Дольше этого катиться не будет, сек.
@export var roll_max_time := 2.2
@export var dizzy_time := 1.6
## Во сколько раз свёрнутый получает меньше урона (но не меньше 1) и во сколько раз
## оглушённый получает больше.
@export var armor_divisor := 4
@export var dizzy_damage_factor := 2.0

const STANDING_SIZE := Vector2(40.0, 28.0)
const ROLLED_SIZE := Vector2(34.0, 34.0)

var _roll_dir := 1
var _roll_hit_cd := 0.0
var _was_rolling := false


func _ready() -> void:
	super()
	_shape.shape = _shape.shape.duplicate()  # размер меняется при сворачивании — у каждого свой
	_set_hitbox(false)


func _update_ai(delta: float) -> void:
	_roll_hit_cd = maxf(_roll_hit_cd - delta, 0.0)
	match state:
		State.CURL:
			velocity.x = 0.0
			_body.position = Vector2(randf_range(-1.0, 1.0), 0.0)  # дрожит
			if _state_time >= curl_time:
				_start_roll()
			return
		State.ROLL:
			_roll_ai()
			return
		State.DIZZY:
			velocity.x = 0.0
			if _state_time >= dizzy_time:
				set_state(State.WALK)
			return

	if not smart:
		# Без ИИ: бродит и катится, только если игрок прямо перед ним на его высоте.
		if player_in_front() and _on_player_level() and is_player_in_range(roll_range_tiles * 0.6) and _attack_cd <= 0.0 and is_on_floor():
			_start_curl()
		else:
			set_state(State.WALK)
			patrol(walk_speed_tiles * 0.6)
		return

	if melee_tactics(delta, aggro_range_tiles, roll_range_tiles, walk_speed_tiles) and _on_player_level() and is_on_floor():
		_start_curl()
	else:
		set_state(State.WALK if moving() else State.IDLE)


## Игрок стоит примерно на одной высоте с панцирником (катиться по полу есть смысл).
func _on_player_level() -> bool:
	return absf(get_player().global_position.y - global_position.y) < Game.tiles(1.4)


func _start_curl() -> void:
	velocity.x = 0.0
	face_player()
	set_state(State.CURL)


func _start_roll() -> void:
	face_player()
	_roll_dir = facing
	_roll_hit_cd = 0.0
	set_state(State.ROLL)


func _roll_ai() -> void:
	_body.position = Vector2.ZERO
	velocity.x = _roll_dir * Game.tiles(roll_speed_tiles)
	var player := get_player()
	if _roll_hit_cd <= 0.0 and get_body_rect().intersects(player.get_body_rect()):
		_roll_hit_cd = 0.8
		player.take_damage(roll_damage, get_center())
	if _state_time < 0.15:
		return
	if is_on_wall():
		Sound.play("punch", global_position)
		set_state(State.DIZZY)  # врезался в стену
	elif smart and is_on_floor() and not probe_ahead(_roll_dir)["ground"]:
		set_state(State.WALK)  # впереди пропасть — разворачивается
	elif _state_time > roll_max_time:
		set_state(State.WALK)  # выдохся


func _enter_state(new_state: int) -> void:
	_body.position = Vector2.ZERO
	_body.modulate = Color.WHITE
	_set_hitbox(new_state == State.CURL or new_state == State.ROLL)
	if new_state == State.ROLL:
		_was_rolling = true
	elif _was_rolling:
		_was_rolling = false
		_attack_cd = roll_cooldown  # покатался — отдыхает


func _set_hitbox(rolled: bool) -> void:
	var size := ROLLED_SIZE if rolled else STANDING_SIZE
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = Vector2(0.0, -size.y / 2.0)


## Свёрнутого почти не пробить, оглушённого бьют вдвое сильнее.
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	var dealt := amount
	if state == State.CURL or state == State.ROLL:
		dealt = maxi(roundi(amount / float(armor_divisor)), 1)
		_body.modulate = Color(1.8, 1.8, 1.8)
		get_tree().create_timer(0.08, false).timeout.connect(_restore_color)
	elif state == State.DIZZY:
		dealt = roundi(amount * dizzy_damage_factor)
	super(dealt, source_position)


func _restore_color() -> void:
	if not _dead:
		_body.modulate = Color.WHITE


## В шаре ловушек уже не остерегается: катится напролом.
func _apply_trap_caution(delta: float) -> void:
	if state == State.ROLL:
		return
	super(delta)


func _state_names() -> Array:
	return State.keys()


## Анимации (assets/frames/panzernik.tres):
##   IDLE — idle, WALK — walk, CURL — curl (сворачивается), ROLL — roll (катится),
##   DIZZY — dizzy (оглушён, звёздочки), DEAD — death (панцирь раскалывается).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "walk"
		State.CURL:
			return "curl"
		State.ROLL:
			return "roll"
		State.DIZZY:
			return "dizzy"
		State.DEAD:
			return "death"
	return "idle"


## Свёрнутый и катящийся не «морщатся» от попаданий — они звенят.
func _hurt_animation() -> String:
	if state == State.CURL or state == State.ROLL:
		return ""
	return "hurt"
