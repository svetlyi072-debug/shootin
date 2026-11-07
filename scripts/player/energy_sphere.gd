class_name EnergySphere
extends Area2D
## Заряженная сфера. Летит по прямой в сторону, куда целился игрок (на курсор мыши),
## проходит сквозь врагов (каждому наносит урон один раз) и исчезает через lifetime секунд.

## Скорость полёта, клеток в секунду.
@export var speed_tiles := 10.0
## Время жизни, сек.
@export var lifetime := 3.0
@export var damage := 50
## Радиус сферы в клетках.
@export var radius_tiles := 0.4
@export var color := Color(0.45, 0.85, 1.0)

## Направление полёта (единичный вектор). Задаёт игрок при выстреле.
var direction := Vector2.RIGHT

var _already_hit: Array[Node] = []

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var circle := CircleShape2D.new()
	circle.radius = Game.tiles(radius_tiles)
	_collision.shape = circle
	body_entered.connect(_on_body_entered)
	add_to_group("player_projectiles")  # умные враги видят летящие в них снаряды
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * Game.tiles(speed_tiles) * delta


func _on_body_entered(body: Node2D) -> void:
	var enemy := body as Enemy
	if enemy and not _already_hit.has(enemy):
		_already_hit.append(enemy)
		enemy.take_damage(damage, global_position)


## Заглушка вместо спрайта.
func _draw() -> void:
	draw_circle(Vector2.ZERO, Game.tiles(radius_tiles), color)


## Скорость полёта, px/с (по ней умные враги решают, уворачиваться ли).
func travel_velocity() -> Vector2:
	return direction * Game.tiles(speed_tiles)
