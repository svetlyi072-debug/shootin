class_name SkeletonEnemy
extends Enemy
## Враг «Скелет». 40 HP, +15 к шкале силы (значения базовых параметров — в skeleton.tscn).
## Без ИИ — ходит туда-обратно и рубит, только если игрок прямо перед ним.
## Умный — выслеживает игрока, обходит с фланга, а увидев летящую в него пулю или сферу,
## закрывается щитом: пока щит поднят, удары спереди не проходят.

enum State { IDLE, WALK, ATTACK, BLOCK, DEAD }

@export_group("Скелет")
## Дальше этого расстояния (клетки) скелет игрока не замечает.
@export var aggro_range_tiles := 8.0
@export var walk_speed_tiles := 4.0
@export var attack_range_tiles := 1.0
@export var attack_damage := 15
@export var attack_cooldown := 1.5
## Длительность замаха (состояние ATTACK), сек.
@export var attack_duration := 0.4
## Сколько держит щит, закрывшись от снаряда (умный режим), сек.
@export var block_time := 0.7


func _update_ai(delta: float) -> void:
	match state:
		State.ATTACK:
			velocity.x = 0.0
			if _state_time < attack_duration:
				return
			set_state(State.WALK)
		State.BLOCK:
			velocity.x = 0.0
			if _state_time < block_time:
				return
			set_state(State.WALK)

	var can_attack := is_player_in_range(attack_range_tiles) and _attack_cd <= 0.0
	if not smart:
		if can_attack and player_in_front():
			_attack()
		else:
			set_state(State.WALK)
			patrol(walk_speed_tiles * 0.5)
		return

	var strike := melee_tactics(delta, aggro_range_tiles, attack_range_tiles, walk_speed_tiles)
	if state == State.BLOCK:
		return  # закрылся щитом от снаряда (или заранее — увидев, что в него целятся)
	if strike:
		_attack()
	else:
		set_state(State.WALK if moving() else State.IDLE)


func _attack() -> void:
	_attack_cd = attack_cooldown
	velocity.x = 0.0
	face_player()
	set_state(State.ATTACK)
	queue_action(attack_duration * 0.5, strike_player.bind(attack_range_tiles + 0.4, attack_damage))


## Умный скелет не прыгает от пуль, а закрывается щитом.
func _dodge(_threat_velocity: Vector2) -> void:
	velocity.x = 0.0
	face_player()
	set_state(State.BLOCK)


## Пока щит поднят, пули и удары спереди не ранят. Заряженная сфера (урон от 30)
## пробивает щит.
const SHIELD_BREAK_DAMAGE := 30


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	var frontal := signf(source_position.x - global_position.x) == facing
	if state == State.BLOCK and frontal and amount < SHIELD_BREAK_DAMAGE:
		_body.modulate = Color(1.8, 1.8, 1.8)
		get_tree().create_timer(0.08, false).timeout.connect(_restore_color)
		return
	super(amount, source_position)


func _restore_color() -> void:
	_body.modulate = Color.WHITE


func _state_names() -> Array:
	return State.keys()


## Анимации (assets/frames/skeleton.tres):
##   IDLE   — idle: стоит, покачиваясь
##   WALK   — walk: ходьба
##   ATTACK — attack: замах мечом (8 кадров = attack_duration)
##   BLOCK  — shield: закрылся щитом
##   DEAD   — death: рассыпается
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "walk"
		State.ATTACK:
			return "attack"
		State.BLOCK:
			return "shield"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "take_hit"
