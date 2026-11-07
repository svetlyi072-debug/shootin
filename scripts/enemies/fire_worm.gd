class_name FireWorm
extends Boss
## Босс «Огненный червь» (символ W). 230 HP (на умной сложности — в полтора раза больше,
## см. smart_health_multiplier в fire_worm.tscn).
##   * держится на расстоянии и ползёт к игроку, если тот далеко;
##   * плюётся очередью огненных шаров: на упреждение, веером и с «навесными» — прыжок
##     над первым шаром приводит прямо под второй (на лёгкой сложности — один шар);
##   * вблизи (ближе burst_range_tiles) бьёт огненным взрывом и пускает волны пламени
##     по полу в обе стороны — перепрыгни их;
##   * раз в rain_interval секунд — огненный ливень по всей арене: красные метки на полу
##     показывают, куда упадут шары, в каждой волне есть «окно» без шаров, а в следующей
##     оно уже в другом месте. Далеко не уйти: ливень накрывает всё вокруг игрока,
##     где бы он ни стоял. На половине здоровья (ярость) волн и шаров в очереди больше.

enum State { IDLE, WALK, SPIT, RAIN, BURST, DEAD }

const FIREBALL := preload("res://assets/frames/fireball.tres")

@export_group("Огненный червь")
@export var walk_speed_tiles := 2.0
## Ближе этого расстояния (клетки) не подползает — плюётся.
@export var keep_distance_tiles := 5.0
@export var spit_interval := 3.2
@export var fireball_damage := 10
@export var fireball_speed_tiles := 9.5
## Шаров в очереди (в ярости — на 2 больше) и пауза между ними, сек.
@export var volley_count := 3
@export var volley_gap := 0.4

@export_group("Огненный ливень")
@export var rain_interval := 12.0
## Сколько волн ливня (в ярости — на одну больше) и пауза между ними, сек.
@export var rain_waves := 2
@export var rain_wave_gap := 1.8
## Шары падают на расстоянии rain_spacing_tiles друг от друга в пределах
## ±rain_half_width_tiles от игрока; в каждой волне есть окно шириной ±rain_gap_half_tiles.
@export var rain_spacing_tiles := 1.7
@export var rain_half_width_tiles := 10.0
@export var rain_gap_half_tiles := 2.6
## Сколько секунд метка предупреждает, прежде чем шар начнёт падать.
@export var rain_warning_time := 0.75
## Старая версия ливня (лёгкая сложность): сколько шаров и на какую ширину.
@export var rain_count := 6
@export var rain_spread_tiles := 6.0

@export_group("Взрыв вблизи")
@export var burst_range_tiles := 3.2
@export var burst_damage := 18
@export var burst_interval := 6.5
## Замах перед взрывом, сек (червь дрожит и краснеет — успей отбежать).
@export var burst_windup := 0.7
@export var flame_wave_speed_tiles := 7.0

var _spit_duration := 0.7
var _rain_gap_x := 0.0


func _ready() -> void:
	super()
	restart_timer("spit", 1.2)
	restart_timer("rain", rain_interval)
	restart_timer("burst", 1.5)


func _boss_ai(_delta: float) -> void:
	match state:
		State.SPIT:
			velocity.x = 0.0
			if _state_time >= _spit_duration:
				set_state(State.IDLE)
			return
		State.RAIN:
			velocity.x = 0.0
			if _state_time >= 0.9:
				set_state(State.IDLE)
			return
		State.BURST:
			velocity.x = 0.0
			_body.position = Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0)) if _state_time < burst_windup else Vector2.ZERO
			if _state_time >= burst_windup + 0.35:
				set_state(State.IDLE)
			return

	face_player()
	if smart and is_player_in_range(burst_range_tiles) and timer_ready("burst"):
		restart_timer("burst", burst_interval)
		set_state(State.BURST)
		queue_action(burst_windup, _burst)
	elif timer_ready("rain"):
		restart_timer("rain", rain_interval)
		set_state(State.RAIN)
		queue_action(0.45, _rain)
	elif timer_ready("spit"):
		restart_timer("spit", spit_interval)
		_start_spit()
	elif distance_to_player_tiles() > keep_distance_tiles:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


func _enter_state(new_state: int) -> void:
	if new_state != State.BURST:
		_body.position = Vector2.ZERO
	_body.modulate = Color(1.7, 0.7, 0.45) if new_state == State.BURST else (Color(1.0, 0.7, 0.7) if _enraged else Color.WHITE)


func _mouth() -> Vector2:
	return get_center() + Vector2(facing * Game.tiles(1.3), -Game.tiles(0.6))


# --- Очередь огненных шаров -------------------------------------------------------------

func _volley_size() -> int:
	if not smart:
		return 1
	return volley_count + (1 if _enraged else 0)


func _start_spit() -> void:
	var count := _volley_size()
	_spit_duration = 0.6 + count * volley_gap
	set_state(State.SPIT)
	for i in count:
		queue_action(0.45 + i * volley_gap, _fire_shot.bind(i, count))


## Один шар очереди. Нечётные в длинной очереди — «навесные»: падают по дуге на то место,
## куда игрок придёт, остальные летят прямо с упреждением и чуть расходятся веером.
func _fire_shot(index: int, count: int) -> void:
	var from := _mouth()
	var player := get_player()
	if smart and count >= 3 and index % 2 == 1:
		var landing := Vector2(arena_clamp_x(predict_player(1.0).x), player.global_position.y)
		_launch_fireball(from, EnemyProjectile.lob_velocity(from, landing, 1.0, _gravity), _gravity)
		return
	var speed := Game.tiles(fireball_speed_tiles)
	var flight := from.distance_to(player.get_center()) / speed
	var aim := (predict_player(flight) - from).normalized()
	if smart and count > 1:
		aim = aim.rotated(deg_to_rad(8.0) * (index - (count - 1) / 2.0))
	_launch_fireball(from, aim * speed, 0.0)


# --- Огненный ливень ----------------------------------------------------------------------

## Ливень начинается, когда червь отрыгивает (0,45 с после входа в RAIN).
func _rain() -> void:
	if not smart:
		_rain_simple()
		return
	_rain_gap_x = INF
	var waves := rain_waves + (1 if _enraged else 0)
	for wave in waves:
		get_tree().create_timer(rain_wave_gap * wave, false).timeout.connect(_rain_wave)


## Одна волна: ряд шаров над игроком и вокруг него, кроме «окна». Окно каждой следующей
## волны — минимум в 3 клетках от предыдущего: нужно перебегать.
func _rain_wave() -> void:
	if _dead or not has_target():
		return
	var player := get_player()
	var tile := float(Game.TILE)
	var centre := player.global_position.x
	var left := tile * 1.2
	var right := _map_width_px() - tile * 1.2
	var gap := centre
	for attempt in 8:
		gap = centre + Game.tiles(randf_range(2.5, 6.0)) * (1.0 if randf() < 0.5 else -1.0)
		gap = clampf(gap, left + tile * 2.0, right - tile * 2.0)
		if _rain_gap_x == INF or absf(gap - _rain_gap_x) >= Game.tiles(3.0):
			break
	_rain_gap_x = gap
	var top := maxf(_home_y - Game.tiles(14.0), tile)
	var drop := _home_y - top
	var fall_time := sqrt(2.0 * drop / _gravity)
	var spacing := Game.tiles(rain_spacing_tiles)
	var x := maxf(left, centre - Game.tiles(rain_half_width_tiles))
	var end := minf(right, centre + Game.tiles(rain_half_width_tiles))
	while x <= end:
		if absf(x - gap) >= Game.tiles(rain_gap_half_tiles):
			GroundWarning.spawn(get_parent(), Vector2(x, _home_y), rain_warning_time + fall_time + randf_range(0.0, 0.2), 22.0)
			get_tree().create_timer(rain_warning_time + randf_range(0.0, 0.2), false).timeout.connect(_drop_fireball.bind(Vector2(x, top)))
		x += spacing


func _drop_fireball(at: Vector2) -> void:
	if _dead:
		return
	_launch_fireball(at, Vector2.ZERO, _gravity)


func _map_width_px() -> float:
	var lv := level()
	return float(lv.map_width()) * Game.TILE if lv else _home_x + Game.tiles(arena_half_width_tiles)


## Старый ливень (лёгкая сложность): шары по дугам падают вокруг игрока.
func _rain_simple() -> void:
	var from := _mouth()
	var player_x := predict_player(1.2).x
	for i in rain_count:
		var offset := lerpf(-rain_spread_tiles, rain_spread_tiles, float(i) / maxf(rain_count - 1, 1))
		var target := Vector2(arena_clamp_x(player_x + Game.tiles(offset)), _home_y)
		var flight_time := randf_range(1.1, 1.5)
		_launch_fireball(from, EnemyProjectile.lob_velocity(from, target, flight_time, _gravity), _gravity)


# --- Взрыв вблизи -----------------------------------------------------------------------------

## Огненный взрыв вокруг червя и две волны пламени по полу в обе стороны.
func _burst() -> void:
	strike_player(burst_range_tiles + 0.3, burst_damage)
	for dir in [-1, 1]:
		var from := Vector2(global_position.x + dir * Game.tiles(1.6), global_position.y - 14.0)
		_launch_fireball(from, Vector2(dir * Game.tiles(flame_wave_speed_tiles), 0.0), 0.0)


func _launch_fireball(from: Vector2, launch_velocity: Vector2, fall: float) -> void:
	EnemyProjectile.launch(get_parent(), from, launch_velocity, FIREBALL, {
		"gravity": fall,
		"damage": fireball_damage,
		"explode_radius": Game.tiles(1.0),
		"scale": 1.6,
		"radius": 10.0,
		"face_velocity": true,
	})


func _state_names() -> Array:
	return State.keys()


## Анимации (Fire Worm, увеличенный — см. fire_worm.tscn).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "walk"
		State.SPIT, State.RAIN, State.BURST:
			return "attack"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "hit"
