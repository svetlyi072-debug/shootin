class_name Bat
extends Enemy
## Враг «Летучая мышь». 10 HP, +5 к шкале силы (значения базовых параметров — в bat.tscn).
## Живая мышь летает без гравитации, мёртвая — падает.
##
## Атака: мышь замирает и трясётся (WINDUP — в этот момент её можно ударить или
## подстрелить), затем пикирует к игроку (DIVE). Урон наносится при касании во время
## пике, поэтому от него можно увернуться.

enum State { IDLE, FLY, WINDUP, DIVE, RECOVER, DEAD }

@export_group("Летучая мышь")
## Дальше этого расстояния (клетки) мышь машет крыльями на месте.
@export var aggro_range_tiles := 6.0
@export var fly_speed_tiles := 7.0
@export var attack_range_tiles := 1.0
@export var attack_damage := 10
@export var attack_cooldown := 2.0
## На какой высоте над игроком (клетки) мышь держится между атаками.
## Должно быть так, чтобы мышь оставалась в досягаемости удара игрока.
@export var hover_height_tiles := 1.0
## Замах перед пике, сек. Мышь замирает и краснеет.
@export var windup_time := 0.4
## Пике: скорость (клеток/с) и длительность (сек).
@export var dive_speed_tiles := 10.0
@export var dive_time := 0.2
## Набор высоты после пике, сек.
@export var recover_time := 0.4

var _dive_hit := false
var _wander_time := 0.0
## Резкий уход в сторону от снаряда (умный режим): пока > 0, скорость не перехватываем.
var _jink_time := 0.0


func _uses_gravity() -> bool:
	return _dead


func _update_ai(delta: float) -> void:
	_wander_time += delta
	if _jink_time > 0.0:
		_jink_time -= delta
		return
	match state:
		State.WINDUP:
			velocity = Vector2.ZERO
			_body.position = Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0))
			face_player()
			# Умная мышь видит, что игрок открыт (замахнулся, заряжает), и бьёт сразу.
			var quick := smart and get_player().is_vulnerable() and _state_time >= windup_time * 0.4
			if _state_time >= windup_time or quick:
				_dive()
			return
		State.DIVE:
			_check_dive_contact()
			if _state_time >= dive_time:
				set_state(State.RECOVER)
			return
		State.RECOVER:
			velocity = Vector2(0.0, -Game.tiles(fly_speed_tiles) * 0.5)
			if _state_time >= recover_time:
				set_state(State.FLY)
			return

	var can_attack := is_player_in_range(attack_range_tiles) and _attack_cd <= 0.0
	if not smart:
		# Без ИИ: кружит у своего места, пикирует, только если игрок оказался рядом.
		if can_attack:
			_attack_cd = attack_cooldown
			set_state(State.WINDUP)
		else:
			set_state(State.FLY)
			_fly_to(_wander_point(), 0.5)
		return

	try_dodge()
	if _jink_time > 0.0:
		return
	if not update_awareness(aggro_range_tiles, delta):
		_drop_token()
		set_state(State.FLY)
		_fly_to(_wander_point(), 0.4)
		return
	read_player_aim()
	if _jink_time > 0.0:
		return
	var player := get_player()
	set_state(State.FLY)
	if player.is_shielding() or not _take_token():
		# Ждёт своей очереди (или пока опустят щит), кружа вне досягаемости удара.
		var angle := _ring_phase * 1.3 + float(get_instance_id() % 11)
		var orbit := Vector2(cos(angle) * Game.tiles(3.0), -Game.tiles(2.4) + sin(angle * 2.0) * Game.tiles(0.5))
		_fly_to(player.get_center() + orbit, 0.8)
	elif can_attack:
		_attack_cd = attack_cooldown
		set_state(State.WINDUP)
	else:
		# Заходит со спины: зависает с той стороны, куда игрок не смотрит.
		var behind := Vector2(-player.facing * Game.tiles(1.0), -Game.tiles(hover_height_tiles))
		_fly_to(player.get_center() + behind, 1.0)


## Точка для полёта «без дела»: восьмёрка вокруг места появления.
func _wander_point() -> Vector2:
	var radius := Game.tiles(patrol_radius_tiles)
	return Vector2(_spawn_x + sin(_wander_time * 0.7) * radius, _spawn_y - Game.tiles(0.5) + sin(_wander_time * 1.4) * Game.tiles(0.5))


## Умная мышь уворачивается рывком поперёк полёта снаряда.
func _dodge(threat_velocity: Vector2) -> void:
	var side := threat_velocity.orthogonal().normalized()
	if side.y > 0.0:
		side = -side  # уходим скорее вверх, чем вниз
	velocity = side * Game.tiles(fly_speed_tiles) * 1.3
	_jink_time = 0.25


func _fly_to(target: Vector2, speed_factor: float) -> void:
	# Плавно тормозим у цели, но не быстрее fly_speed_tiles.
	velocity = ((target - get_center()) * 8.0).limit_length(Game.tiles(fly_speed_tiles) * speed_factor)
	if speed_factor >= 1.0:
		face_player()
	elif absf(velocity.x) > 5.0:
		set_facing(1 if velocity.x > 0.0 else -1)


func _dive() -> void:
	_dive_hit = false
	set_state(State.DIVE)
	var to_player := predict_player(dive_time * 0.6) - get_center()
	velocity = to_player.normalized() * Game.tiles(dive_speed_tiles)


## Урон — при касании тела игрока во время пике (один раз за пике).
func _check_dive_contact() -> void:
	if _dive_hit:
		return
	var player := get_player()
	if get_body_rect().intersects(player.get_body_rect()):
		_dive_hit = true
		player.take_damage(attack_damage, get_center())


func _state_names() -> Array:
	return State.keys()


## Анимации (assets/frames/bat.tres — летучая мышь из Monsters Creatures Fantasy 2):
##   IDLE, FLY, RECOVER — fly: машет крыльями
##   WINDUP  — attack: замах перед пике (плюс тряска и красноватый оттенок)
##   DIVE    — продолжает attack: резкое пике
##   DEAD    — death: складывает крылья и падает
func _enter_state(new_state: int) -> void:
	if new_state != State.WINDUP:
		_body.position = Vector2.ZERO
	match new_state:
		State.WINDUP:
			_body.modulate = Color(1.0, 0.6, 0.6)
		State.DEAD:
			velocity = Vector2.ZERO  # дальше падает под действием гравитации
			_body.modulate = Color.WHITE
		State.DIVE:
			pass
		_:
			_body.modulate = Color.WHITE


func _state_animation(for_state: int) -> String:
	match for_state:
		State.WINDUP:
			return "attack"
		State.DIVE:
			return ""  # доигрывает attack
		State.DEAD:
			return "death"
	return "fly"


func _hurt_animation() -> String:
	return "hurt"
