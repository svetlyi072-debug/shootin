class_name Shockwave
extends Node2D
## Ударная волна Древнего слизня. Два земляных гребня разбегаются от места приземления
## в обе стороны и поднимают пыль. Игрок получает урон, когда гребень проходит под ним,
## если он стоит на том же уровне пола, что и босс. Прыжок или блок спасают.
## Создаётся боссом (см. AncientSlime._spawn_shockwave), точка узла — место приземления.

const DUST_TEXTURE := preload("res://assets/pixel_adventure/dust.png")
const CREST_COLOR := Color(0.85, 0.66, 0.42)
const CORE_COLOR := Color(1.0, 0.93, 0.75)

## Ширина и высота гребня в клетках (высота убывает к краю радиуса).
const CREST_WIDTH_TILES := 1.25
const CREST_HEIGHT_TILES := 1.0
## Пыль: сколько живёт облачко и как часто вылетает новое из-под каждого гребня.
const DUST_LIFETIME := 0.45
const DUST_INTERVAL := 0.03
const DUST_GRAVITY := 160.0

## Радиус волны (px), скорость гребня (px/с) и урон. Задаёт босс.
var radius := 320.0
var speed := 800.0
var damage := 20
## true — игрока не ранить: босс и так приземлился прямо на него.
var spare_player := false

var _front := 0.0
var _player_hit := false
var _dust_timer := 0.0
var _dust: Array = []  # облачка пыли: {pos, vel, age}


func _ready() -> void:
	z_index = 1


func _physics_process(delta: float) -> void:
	var previous := _front
	if _front < radius:
		_front = minf(_front + speed * delta, radius)
		_check_player(previous)
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = DUST_INTERVAL
			for side in [-1.0, 1.0]:
				_dust.append({
					"pos": Vector2(side * _front, -4.0),
					"vel": Vector2(side * randf_range(10.0, 50.0), -randf_range(50.0, 110.0)),
					"age": 0.0,
				})
	for puff in _dust:
		puff["age"] += delta
		puff["vel"].y += DUST_GRAVITY * delta
		puff["pos"] += puff["vel"] * delta
	_dust = _dust.filter(func(puff: Dictionary) -> bool: return puff["age"] < DUST_LIFETIME)
	if _front >= radius and _dust.is_empty():
		queue_free()
	queue_redraw()


## Ранит игрока, если гребень за этот кадр прошёл под ним.
func _check_player(previous_front: float) -> void:
	if spare_player or _player_hit:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.is_dead():
		return
	var half_width := player.get_body_rect().size.x / 2.0
	var dx := absf(player.global_position.x - global_position.x)
	var crossed := dx + half_width > previous_front and dx - half_width <= _front
	var same_floor := absf(player.global_position.y - global_position.y) < Game.tiles(0.5)
	if crossed and same_floor and player.is_on_floor():
		_player_hit = true
		player.take_damage(damage, global_position)


func _draw() -> void:
	if _front < radius:
		var fade := 1.0 - _front / radius
		# Трещина по земле от центра до гребней.
		draw_line(Vector2(-_front, -1.0), Vector2(_front, -1.0), Color(CREST_COLOR, 0.5 * fade), 2.0)
		for side in [-1.0, 1.0]:
			_draw_crest(side, 0.4 + 0.6 * fade)
	for puff in _dust:
		var t: float = puff["age"] / DUST_LIFETIME
		var size := Vector2.ONE * lerpf(16.0, 36.0, t)
		draw_texture_rect(DUST_TEXTURE, Rect2(puff["pos"] - size / 2.0, size), false, Color(1.0, 1.0, 1.0, 1.0 - t))


## Гребень — земляной горб, крутой спереди и пологий сзади, со светлой сердцевиной.
func _draw_crest(side: float, strength: float) -> void:
	var width := Game.tiles(CREST_WIDTH_TILES)
	var height := Game.tiles(CREST_HEIGHT_TILES) * strength
	for layer in 2:
		var scale_down := 1.0 if layer == 0 else 0.55
		var points := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var t := float(i) / steps
			# t = 0 — хвост гребня, t = 1 — передний край.
			var shape := sin(PI * pow(t, 1.6))
			points.append(Vector2(side * (_front - width * (1.0 - t)), -height * scale_down * shape))
		var color := CREST_COLOR if layer == 0 else CORE_COLOR
		color.a = strength
		draw_colored_polygon(points, color)
