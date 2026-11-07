class_name AbyssEye
extends Boss
## Босс «Око бездны» (символ O). 200 HP, летает.
##   * парит над игроком, покачиваясь из стороны в сторону;
##   * выпускает веер зарядов в игрока (по 10);
##   * раз в dive_interval секунд замирает, трясётся и пикирует (20 при касании);
##   * призывает летучих мышей.
## Погибнув, падает вниз. Сбивать удобнее пулями в курсор и сферой.

enum State { HOVER, VOLLEY, WINDUP, DIVE, RECOVER, SUMMON, DEAD }

const BOLT := preload("res://assets/frames/bolt.tres")
const MINION := preload("res://scenes/enemies/bat.tscn")

@export_group("Око бездны")
## На какой высоте над игроком (клетки) держится и как сильно покачивается.
@export var hover_height_tiles := 4.5
@export var hover_speed_tiles := 3.5
@export var sway_tiles := 4.0
@export var volley_interval := 2.6
@export var bolt_count := 3
@export var bolt_damage := 10
@export var bolt_speed_tiles := 8.0
@export var bolt_spread_degrees := 14.0
@export var dive_interval := 7.0
@export var windup_time := 0.6
@export var dive_speed_tiles := 13.0
@export var dive_time := 0.5
@export var dive_damage := 20
@export var recover_time := 0.8
@export var summon_interval := 12.0
@export var summon_count := 2

var _sway_time := 0.0
var _dive_hit := false
## Резкий уход от снаряда (умный режим), сек.
var _jink := 0.0


func _ready() -> void:
	super()
	restart_timer("volley", 1.5)
	restart_timer("dive", dive_interval)
	restart_timer("summon", summon_interval)


func _uses_gravity() -> bool:
	return _dead


func _boss_ai(delta: float) -> void:
	_sway_time += delta
	match state:
		State.VOLLEY, State.SUMMON:
			_hover(0.4)
			if _state_time >= 0.6:
				set_state(State.HOVER)
			return
		State.WINDUP:
			velocity = Vector2.ZERO
			_body.position = Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))
			face_player()
			if _state_time >= windup_time:
				_dive()
			return
		State.DIVE:
			_check_dive_contact()
			if _state_time >= dive_time or is_on_floor() or is_on_wall():
				set_state(State.RECOVER)
			return
		State.RECOVER:
			velocity = Vector2(0.0, -Game.tiles(hover_speed_tiles))
			if _state_time >= recover_time:
				set_state(State.HOVER)
			return

	if _jink > 0.0:
		_jink -= delta
		return
	if smart and timer_ready("jink"):
		var threat := incoming_projectile(0.45)
		if threat != null and randf() < 0.6:
			restart_timer("jink", 1.0)
			var side: Vector2 = (threat.call("travel_velocity") as Vector2).orthogonal().normalized()
			if side.y > 0.0:
				side = -side
			velocity = side * Game.tiles(hover_speed_tiles) * 1.6
			_jink = 0.3
			return
	_hover(1.0)
	if timer_ready("summon"):
		restart_timer("summon", summon_interval)
		set_state(State.SUMMON)
		queue_action(0.3, spawn_minions.bind(MINION, summon_count))
	elif timer_ready("dive"):
		restart_timer("dive", dive_interval)
		set_state(State.WINDUP)
	elif timer_ready("volley"):
		restart_timer("volley", volley_interval)
		set_state(State.VOLLEY)
		queue_action(0.3, _fire_bolts)


func _hover(speed_factor: float) -> void:
	var player := get_player()
	var sway := sin(_sway_time * 0.8) * Game.tiles(sway_tiles)
	var target := Vector2(arena_clamp_x(player.global_position.x + sway), player.get_center().y - Game.tiles(hover_height_tiles))
	if not smart:
		# Без ИИ — парит над своим местом и не гоняется за игроком.
		target = Vector2(arena_clamp_x(_home_x + sway), _home_y - Game.tiles(0.5))
	velocity = ((target - get_center()) * 3.0).limit_length(Game.tiles(hover_speed_tiles) * speed_factor)
	face_player()


func _fire_bolts() -> void:
	var from := get_center()
	var aim := (predict_player(from.distance_to(get_player().get_center()) / Game.tiles(bolt_speed_tiles)) - from).normalized()
	for i in bolt_count:
		var angle := deg_to_rad((i - (bolt_count - 1) / 2.0) * bolt_spread_degrees)
		EnemyProjectile.launch(get_parent(), from + aim * Game.tiles(1.2), aim.rotated(angle) * Game.tiles(bolt_speed_tiles), BOLT, {
			"damage": bolt_damage,
			"scale": 1.3,
			"radius": 9.0,
			"tint": Color(1.0, 0.7, 1.0),
		})


func _dive() -> void:
	_dive_hit = false
	set_state(State.DIVE)
	velocity = (get_player().get_center() - get_center()).normalized() * Game.tiles(dive_speed_tiles)


func _check_dive_contact() -> void:
	if _dive_hit:
		return
	var player := get_player()
	if get_body_rect().intersects(player.get_body_rect()):
		_dive_hit = true
		player.take_damage(dive_damage, get_center())


func _enter_state(new_state: int) -> void:
	if new_state != State.WINDUP:
		_body.position = Vector2.ZERO
	if new_state == State.DEAD:
		velocity = Vector2.ZERO  # дальше падает под действием гравитации


func _state_names() -> Array:
	return State.keys()


## Анимации (кадры летающего глаза, увеличенные и окрашенные — см. abyss_eye.tscn).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.VOLLEY:
			return "cast"
		State.WINDUP:
			return "attack"
		State.DIVE:
			return ""
		State.SUMMON:
			return "attack2"
		State.DEAD:
			return "death"
	return "flight"


func _hurt_animation() -> String:
	return "take_hit"
