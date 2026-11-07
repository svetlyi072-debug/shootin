class_name DarkWizard
extends Boss
## Босс «Тёмный колдун» (символ V). 260 HP.
##   * стоит и колдует: веер магических зарядов в игрока (по 12);
##   * вблизи бьёт посохом (20);
##   * раз в teleport_interval секунд растворяется и появляется в другом месте арены,
##     подальше от игрока;
##   * призывает скелетов.

enum State { IDLE, CAST, SLASH, VANISH, APPEAR, SUMMON, DEAD }

const BOLT := preload("res://assets/frames/bolt.tres")
const MINION := preload("res://scenes/enemies/skeleton.tscn")

@export_group("Тёмный колдун")
@export var cast_interval := 2.4
@export var bolt_count := 3
@export var bolt_damage := 12
@export var bolt_speed_tiles := 8.5
@export var bolt_spread_degrees := 12.0
@export var slash_range_tiles := 2.0
@export var slash_damage := 20
@export var slash_cooldown := 1.5
@export var teleport_interval := 6.0
## Сколько длится растворение и появление, сек.
@export var teleport_time := 0.35
## Появляется не ближе этого к игроку (клетки).
@export var teleport_min_distance_tiles := 6.0
@export var summon_interval := 13.0
@export var summon_count := 2


func _ready() -> void:
	super()
	restart_timer("cast", 1.5)
	restart_timer("teleport", teleport_interval)
	restart_timer("summon", summon_interval)


func _boss_ai(_delta: float) -> void:
	velocity.x = 0.0
	match state:
		State.CAST, State.SLASH, State.SUMMON:
			if _state_time >= 0.6:
				set_state(State.IDLE)
			return
		State.VANISH:
			_body.modulate.a = 1.0 - clampf(_state_time / teleport_time, 0.0, 1.0)
			if _state_time >= teleport_time:
				global_position = Vector2(_pick_teleport_x(), _home_y)
				set_state(State.APPEAR)
			return
		State.APPEAR:
			_body.modulate.a = clampf(_state_time / teleport_time, 0.0, 1.0)
			if _state_time >= teleport_time:
				set_state(State.IDLE)
			return

	face_player()
	if is_player_in_range(slash_range_tiles) and timer_ready("slash"):
		restart_timer("slash", slash_cooldown)
		set_state(State.SLASH)
		queue_action(0.35, strike_player.bind(slash_range_tiles + 0.5, slash_damage))
	elif timer_ready("teleport") or (smart and incoming_projectile(0.6, true) != null):
		# Умный колдун ещё и исчезает, когда в него летит заряженная сфера.
		restart_timer("teleport", teleport_interval)
		set_state(State.VANISH)
	elif timer_ready("summon"):
		restart_timer("summon", summon_interval)
		set_state(State.SUMMON)
		queue_action(0.35, spawn_minions.bind(MINION, summon_count))
	elif timer_ready("cast"):
		restart_timer("cast", cast_interval)
		set_state(State.CAST)
		queue_action(0.35, _fire_bolts)
	else:
		set_state(State.IDLE)


## Новое место — на полу арены, не ближе teleport_min_distance_tiles к игроку.
func _pick_teleport_x() -> float:
	var player_x := get_player().global_position.x
	var reach := Game.tiles(arena_half_width_tiles)
	var best := _home_x
	var best_distance := -1.0
	for i in 8:
		var x := _home_x + randf_range(-reach, reach)
		var away := absf(x - player_x)
		if away >= Game.tiles(teleport_min_distance_tiles):
			return x
		if away > best_distance:
			best = x
			best_distance = away
	return best


func _fire_bolts() -> void:
	var from := get_center() + Vector2(facing * Game.tiles(1.0), -Game.tiles(0.5))
	var aim := (predict_player(from.distance_to(get_player().get_center()) / Game.tiles(bolt_speed_tiles)) - from).normalized()
	for i in bolt_count:
		var angle := deg_to_rad((i - (bolt_count - 1) / 2.0) * bolt_spread_degrees)
		EnemyProjectile.launch(get_parent(), from, aim.rotated(angle) * Game.tiles(bolt_speed_tiles), BOLT, {
			"damage": bolt_damage,
			"scale": 1.2,
			"radius": 9.0,
			"tint": Color(0.75, 0.45, 1.0),
		})


func _enter_state(new_state: int) -> void:
	if new_state != State.VANISH and new_state != State.APPEAR:
		_body.modulate.a = 1.0


func _state_names() -> Array:
	return State.keys()


## Анимации (Evil Wizard 2 — см. dark_wizard.tscn).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.CAST, State.SUMMON:
			return "cast"
		State.SLASH:
			return "slash"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "take_hit"
