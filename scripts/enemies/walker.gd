class_name WalkerEnemy
extends Enemy
## Наземный враг общего вида: стоит, пока игрок далеко, идёт к нему и бьёт вблизи.
## По желанию:
##   * бросает снаряд издалека (гоблин — бомбы): задайте throw_frames;
##   * «спит», притворяясь предметом, пока к нему не подойдут (мимик — сундук):
##     включите starts_dormant.
## Числа и имена анимаций настраиваются в .tscn конкретного врага
## (goblin.tscn, mushroom.tscn, rat.tscn, mimic.tscn).

enum State { IDLE, MOVE, ATTACK, THROW, DORMANT, WAKE, DEAD }

@export_group("Поведение")
## Дальше этого расстояния (клетки) враг стоит на месте.
@export var aggro_range_tiles := 6.0
@export var move_speed_tiles := 3.0
@export var attack_range_tiles := 1.0
@export var attack_damage := 10
@export var attack_cooldown := 1.2
## Длительность удара и момент от начала замаха, когда он ранит, сек.
@export var attack_duration := 0.5
@export var attack_hit_time := 0.25

@export_group("Бросок")
## Снаряд (SpriteFrames с анимациями fly и explode). Пусто — враг не бросает.
@export var throw_frames: SpriteFrames
@export var throw_damage := 12
@export var throw_cooldown := 3.0
## Бросает, когда игрок на таком расстоянии (клетки).
@export var throw_min_range_tiles := 3.0
@export var throw_max_range_tiles := 7.0
@export var throw_duration := 0.6
## Момент от начала броска, когда снаряд вылетает, сек.
@export var throw_release_time := 0.35
@export var throw_explode_radius_tiles := 1.2
@export var throw_scale := 1.0

@export_group("Засада")
## Враг «спит» (мимик притворяется сундуком), пока игрок не подойдёт ближе wake_range_tiles
## или не ударит его.
@export var starts_dormant := false
@export var wake_range_tiles := 2.0
@export var wake_duration := 0.8
## Если больше нуля, пока враг «спит» и просыпается, его тело низкое (px): так зомби лежит
## в могиле, а не торчит невидимой колонной. Когда встал — тело обычного роста.
@export var dormant_height := 0.0

@export_group("Анимации")
@export var anim_idle := "idle"
@export var anim_move := "run"
@export var anim_attack := "attack"
@export var anim_throw := "throw"
@export var anim_hurt := "take_hit"
@export var anim_death := "death"
@export var anim_dormant := "closed"
@export var anim_wake := "wake"

var _throw_cd := 0.0
var _stand_size := Vector2.ZERO
var _stand_y := 0.0


func _ready() -> void:
	if starts_dormant:
		state = State.DORMANT
	super()
	if dormant_height > 0.0:
		# Форма тела общая для всех экземпляров сцены — берём свою копию.
		_shape.shape = _shape.shape.duplicate()
		_stand_size = (_shape.shape as RectangleShape2D).size
		_stand_y = _shape.position.y
		_set_lying(state == State.DORMANT)
	# Первый бросок — почти сразу, как только враг заметит игрока (иначе успевает добежать).
	_throw_cd = randf_range(0.2, 0.8)


func _update_ai(delta: float) -> void:
	_throw_cd = maxf(_throw_cd - delta, 0.0)
	match state:
		State.DORMANT:
			velocity.x = 0.0
			if distance_to_player_tiles() <= wake_range_tiles:
				set_state(State.WAKE)
			return
		State.WAKE:
			velocity.x = 0.0
			face_player()
			if _state_time >= wake_duration:
				set_state(State.IDLE)
			return
		State.ATTACK:
			velocity.x = 0.0
			if _state_time < attack_duration:
				return
			set_state(State.MOVE)
		State.THROW:
			velocity.x = 0.0
			if _state_time < throw_duration:
				return
			set_state(State.MOVE)

	var distance := distance_to_player_tiles()
	var can_attack := is_player_in_range(attack_range_tiles) and _attack_cd <= 0.0
	if not smart:
		# Без ИИ: ходит своим маршрутом, бьёт только того, кто прямо перед ним, не бросает.
		if can_attack and player_in_front():
			_start_attack()
		else:
			set_state(State.MOVE)
			patrol(move_speed_tiles * 0.6)
		return

	if throw_frames == null:
		if melee_tactics(delta, aggro_range_tiles, attack_range_tiles, move_speed_tiles):
			_start_attack()
		else:
			set_state(State.MOVE if moving() else State.IDLE)
		return
	_ranged_tactics(delta, distance, can_attack)
	if state != State.ATTACK and state != State.THROW:
		set_state(State.MOVE if moving() else State.IDLE)


## Тактика метателя (гоблин): держит дистанцию броска, отступает, если игрок подошёл
## вплотную, ищет позицию, откуда видно игрока, бросает на упреждение.
func _ranged_tactics(delta: float, distance: float, can_attack: bool) -> void:
	if try_dodge():
		return
	if should_flee() or _wants_healing():
		_retreat_or_heal(move_speed_tiles)
		return
	if not update_awareness(aggro_range_tiles + 2.0, delta):
		patrol(move_speed_tiles * 0.4)
		return
	if not can_see_player():
		navigate_to(_last_seen, move_speed_tiles)  # обходит стену, чтобы снова видеть цель
		return
	read_player_aim()
	var player := get_player()
	if can_attack:
		_start_attack()
	elif _can_throw(distance):
		_start_throw()
	elif distance < throw_min_range_tiles:
		# Игрок подошёл слишком близко — отступаем на дистанцию броска (кайтим).
		var away := 1 if global_position.x > player.global_position.x else -1
		if not move_smart(global_position.x + away * Game.tiles(2.0), move_speed_tiles * 1.1):
			navigate_to(player.global_position, move_speed_tiles)  # зажали в угол — в рукопашную
	elif distance > throw_max_range_tiles:
		navigate_to(player.global_position, move_speed_tiles)
	else:
		velocity.x = 0.0
		face_player()


func _start_attack() -> void:
	_attack_cd = attack_cooldown
	velocity.x = 0.0
	face_player()
	set_state(State.ATTACK)
	queue_action(attack_hit_time, strike_player.bind(attack_range_tiles + 0.3, attack_damage))


func _can_throw(distance: float) -> bool:
	return throw_frames != null and _throw_cd <= 0.0 and is_on_floor() \
		and distance >= throw_min_range_tiles and distance <= throw_max_range_tiles


func _start_throw() -> void:
	_throw_cd = throw_cooldown
	face_player()
	set_state(State.THROW)
	queue_action(throw_release_time, _release_projectile)


func _release_projectile() -> void:
	var from := get_center() + Vector2(facing * Game.tiles(0.4), -Game.tiles(0.4))
	var target := get_player().global_position + Vector2(0.0, -Game.tiles(0.3))
	var flight_time := clampf(from.distance_to(target) / Game.tiles(7.0), 0.6, 1.1)
	if smart:
		# На упреждение: туда, где игрок будет к моменту падения бомбы.
		target.x = predict_player(flight_time).x
	EnemyProjectile.launch(get_parent(), from, EnemyProjectile.lob_velocity(from, target, flight_time, _gravity), throw_frames, {
		"gravity": _gravity,
		"damage": throw_damage,
		"explode_radius": Game.tiles(throw_explode_radius_tiles),
		"scale": throw_scale,
		"radius": 8.0,
	})


func _enter_state(new_state: int) -> void:
	if dormant_height > 0.0:
		_set_lying(new_state == State.DORMANT or new_state == State.WAKE)


## Лежащее тело — низкое (dormant_height), стоящее — как в сцене. Ноги остаются на земле.
func _set_lying(lying: bool) -> void:
	var rect := _shape.shape as RectangleShape2D
	var height := dormant_height if lying else _stand_size.y
	rect.size = Vector2(_stand_size.x, height)
	_shape.position.y = -height / 2.0 if lying else _stand_y


## Удар по спящему будит его.
func _on_damaged(_amount: int) -> void:
	if state == State.DORMANT:
		set_state(State.WAKE)


## Пока игрок недоступен (погиб, уровень пройден), спящий так и спит.
func _on_no_target() -> void:
	if state == State.DORMANT:
		velocity.x = 0.0
		return
	super()


func _state_names() -> Array:
	return State.keys()


func _state_animation(for_state: int) -> String:
	match for_state:
		State.MOVE:
			return anim_move
		State.ATTACK:
			return anim_attack
		State.THROW:
			return anim_throw
		State.DORMANT:
			return anim_dormant
		State.WAKE:
			return anim_wake
		State.DEAD:
			return anim_death
	return anim_idle


func _hurt_animation() -> String:
	return anim_hurt
