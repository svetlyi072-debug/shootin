class_name BoneKnight
extends Boss
## Босс «Костяной рыцарь» (символ N). 240 HP (на умной сложности в полтора раза больше,
## см. smart_health_multiplier в bone_knight.tscn).
##   * идёт к игроку, вблизи рубит мечом сверху (20);
##   * метает крутящийся меч (15) — на умной сложности прицельно, в том числе вверх,
##     в игрока на платформе над ним;
##   * получив удар спереди, закрывается щитом на shield_time секунд: пока щит поднят,
##     всё, что летит спереди, не ранит. Бить его надо со спины — через мост над ареной;
##   * если игрок встал на платформу над ним, рыцарь не залезает туда, а подходит снизу,
##     приседает (замах — дрожит и краснеет, успей отойти вбок) и подпрыгивает сквозь
##     платформу: удар в прыжке — 35, после чего он падает обратно на пол.

enum State { IDLE, WALK, SLASH, SHIELD, THROW, LEAP, DEAD }

const SWORD := preload("res://assets/frames/sword.tres")

@export_group("Костяной рыцарь")
@export var walk_speed_tiles := 2.5
@export var slash_range_tiles := 1.8
@export var slash_damage := 20
@export var slash_cooldown := 1.6
@export var throw_interval := 3.0
## Меч метает, когда игрок дальше этого (клетки).
@export var throw_min_range_tiles := 4.0
@export var sword_damage := 15
@export var sword_speed_tiles := 9.0
@export var shield_time := 1.5
@export var shield_cooldown := 5.0

@export_group("Прыжок сквозь платформу")
@export var leap_damage := 35
@export var leap_interval := 3.5
## Замах перед прыжком, сек.
@export var leap_windup := 0.55
## Выше этого (клетки над головой рыцаря) игрока не достать — прыгать не будет.
@export var leap_max_rise_tiles := 6.5
## Прыгает, когда стоит под игроком ближе этого по горизонтали (клетки).
@export var leap_align_tiles := 0.9

const BODY_HEIGHT := 100.0

var _leap_rising := false
var _leap_hit := false


func _ready() -> void:
	super()
	restart_timer("throw", 2.0)


func _boss_ai(_delta: float) -> void:
	match state:
		State.SLASH, State.THROW:
			velocity.x = 0.0
			if _state_time >= 0.55:
				set_state(State.IDLE)
			return
		State.SHIELD:
			velocity.x = 0.0
			if _state_time >= shield_time:
				set_state(State.IDLE)
			return
		State.LEAP:
			_leap_ai()
			return

	face_player()
	var distance := distance_to_player_tiles()
	var player := get_player()
	if smart and timer_ready("shield") and (incoming_projectile(0.5) != null or player.state == Player.State.CHARGE):
		# Видит летящий снаряд или заряжаемую сферу — щит поднимает заранее.
		restart_timer("shield", shield_cooldown)
		set_state(State.SHIELD)
		return
	var perched := smart and _player_perched()
	var under_player := perched and absf(player.global_position.x - global_position.x) <= Game.tiles(leap_align_tiles)
	var punish := smart and player.is_vulnerable() and timer_ready("punish")
	if under_player and timer_ready("leap"):
		restart_timer("leap", leap_interval)
		set_state(State.LEAP)
	elif is_player_in_range(slash_range_tiles) and (timer_ready("slash") or punish):
		if punish:
			restart_timer("punish", 2.5)  # игрок открылся — рубит вне очереди
		restart_timer("slash", slash_cooldown)
		set_state(State.SLASH)
		queue_action(0.3, strike_player.bind(slash_range_tiles + 0.5, slash_damage))
	elif (distance >= throw_min_range_tiles or perched) and timer_ready("throw"):
		restart_timer("throw", throw_interval)
		set_state(State.THROW)
		queue_action(0.3, _throw_sword)
	elif perched and not under_player:
		# Игрок на платформе над ним: встаёт точно под него и ждёт, когда можно прыгнуть.
		set_state(State.WALK)
		boss_walk(walk_speed_tiles * 1.4)
	elif distance > slash_range_tiles:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


## Меч летит в игрока (умный — с упреждением, под любым углом); без ИИ — прямо перед собой.
func _throw_sword() -> void:
	var from := get_center() + Vector2(facing * Game.tiles(1.2), -Game.tiles(0.2))
	var direction := Vector2(facing, 0.0)
	if smart:
		var aim := predict_player(0.4) - from
		if aim.length_squared() > 1.0:
			direction = aim.normalized()
	EnemyProjectile.launch(get_parent(), from, direction * Game.tiles(sword_speed_tiles), SWORD, {
		"damage": sword_damage,
		"scale": 0.8,
		"radius": 12.0,
		"lifetime": 3.0,
		"flip_with_velocity": true,
	})


# --- Прыжок сквозь платформу ---------------------------------------------------------------

## Сколько пикселей надо подняться, чтобы голова рыцаря дошла до середины тела игрока.
func _leap_rise_px() -> float:
	return global_position.y - BODY_HEIGHT - get_player().get_center().y + 14.0


## Игрок стоит выше рыцаря на платформе, но в пределах прыжка.
func _player_perched() -> bool:
	var player := get_player()
	var rise := _leap_rise_px()
	return player.is_on_floor() and rise > 24.0 and rise <= Game.tiles(leap_max_rise_tiles)


func _leap_ai() -> void:
	velocity.x = 0.0
	if not _leap_rising:
		face_player()
		_body.position = Vector2(randf_range(-2.5, 2.5), randf_range(-1.0, 1.0))  # дрожит перед прыжком
		if _state_time >= leap_windup:
			_launch_leap()
		return
	# Прыжок строго вверх: платформы пролетает насквозь и не цепляется за них.
	if not _leap_hit and get_body_rect().grow(6.0).intersects(get_player().get_body_rect()):
		_leap_hit = true
		get_player().take_damage(leap_damage, get_center())
	var landed := is_on_floor() and _state_time > leap_windup + 0.15
	if landed or _state_time > leap_windup + 2.5:
		set_state(State.IDLE)


func _launch_leap() -> void:
	_leap_rising = true
	_leap_hit = false
	_body.position = Vector2.ZERO
	set_collision_mask_value(5, false)  # слой сквозных платформ: пока прыгает, они для него не существуют
	var rise := clampf(_leap_rise_px() + 8.0, 32.0, Game.tiles(leap_max_rise_tiles) + 8.0)
	velocity.y = -sqrt(2.0 * _gravity * rise)
	_restart_animation("attack2")


func _enter_state(new_state: int) -> void:
	_leap_rising = false
	if new_state != State.LEAP:
		set_collision_mask_value(5, true)  # стоит на платформах, как обычно
		_body.position = Vector2.ZERO
		_restore_color()
	else:
		_body.modulate = Color(1.7, 0.7, 0.5)  # замах: краснеет


## Щит: спереди не пробить, пока он поднят. Первый удар спереди поднимает щит.
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if _dead:
		return
	var frontal := _is_frontal(source_position)
	if state == State.SHIELD and frontal:
		_flash_block()
		return
	super(amount, source_position)
	if smart and not _dead and frontal and timer_ready("shield") and state != State.SLASH and state != State.THROW and state != State.LEAP:
		restart_timer("shield", shield_cooldown)
		set_state(State.SHIELD)


func _is_frontal(source_position: Vector2) -> bool:
	var dx := source_position.x - global_position.x
	return dx * facing >= 0.0 or absf(dx) < 4.0


func _flash_block() -> void:
	hint_once("Рыцарь закрылся щитом — бей со спины!")
	_body.modulate = Color(2.0, 2.0, 2.0)
	get_tree().create_timer(0.08, false).timeout.connect(_restore_color)


func _restore_color() -> void:
	_body.modulate = Color(1.0, 0.7, 0.7) if is_enraged() else Color.WHITE


func _state_names() -> Array:
	return State.keys()


## Анимации (кадры скелета, увеличенные и окрашенные — см. bone_knight.tscn).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "walk"
		State.SLASH:
			return "attack2"
		State.SHIELD:
			return "shield"
		State.THROW:
			return "throw"
		State.LEAP:
			return "attack"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "take_hit"
