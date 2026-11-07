class_name Slime
extends Enemy
## Враг «Слизняк». 20 HP, +10 к шкале силы (значения базовых параметров — в slime.tscn).

enum State { IDLE, MOVE, ATTACK, DEAD }

@export_group("Слизняк")
## Дальше этого расстояния (клетки) слизняк стоит на месте.
@export var aggro_range_tiles := 5.0
@export var move_speed_tiles := 2.0
@export var attack_range_tiles := 1.0
@export var attack_damage := 5
@export var attack_cooldown := 1.0
## Прыжок-выпад: горизонтальная скорость (клеток/с) и высота (клеток).
@export var lunge_speed_tiles := 4.0
@export var lunge_height_tiles := 0.5


func _update_ai(delta: float) -> void:
	if state == State.ATTACK:
		# Выпад длится, пока слизняк не приземлится.
		if _state_time > 0.1 and is_on_floor():
			velocity.x = 0.0
			set_state(State.MOVE)
		return

	var can_lunge := is_player_in_range(attack_range_tiles) and _attack_cd <= 0.0 and is_on_floor()
	if not smart:
		# Без ИИ: ползает туда-обратно, кусает, только если игрок прямо перед ним.
		if can_lunge and player_in_front():
			_lunge()
		else:
			set_state(State.MOVE)
			patrol(move_speed_tiles * 0.6)
		return

	# Умный: вся тактика (путь, очередь атак, ожидание у щита, финты) — в melee_tactics.
	if melee_tactics(delta, aggro_range_tiles + 1.0, attack_range_tiles, move_speed_tiles) and is_on_floor():
		_lunge()
	else:
		set_state(State.MOVE if moving() else State.IDLE)


func _lunge() -> void:
	_attack_cd = attack_cooldown
	face_player()
	set_state(State.ATTACK)
	var jump_speed := sqrt(2.0 * _gravity * Game.tiles(lunge_height_tiles))
	velocity = Vector2(facing * Game.tiles(lunge_speed_tiles), -jump_speed)
	# TODO: с анимацией наносить урон в момент касания, а не в начале выпада.
	get_player().take_damage(attack_damage, get_center())


func _state_names() -> Array:
	return State.keys()


## Анимации (assets/frames/slime.tres):
##   IDLE   — idle: небольшое пульсирование
##   MOVE   — move: ползёт к игроку, пульсируя
##   ATTACK — attack: прыжок-выпад
##   DEAD   — die: растекается лужей
func _state_animation(for_state: int) -> String:
	match for_state:
		State.MOVE:
			return "move"
		State.ATTACK:
			return "attack"
		State.DEAD:
			return "die"
	return "idle"


func _hurt_animation() -> String:
	return "hurt"
