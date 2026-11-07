class_name Bullet
extends Area2D
## Обычная пуля Шуткина. Летит по прямой, исчезает при попадании во врага или в блок.

## Скорость полёта, клеток в секунду.
@export var speed_tiles := 16.0
## Время жизни, сек.
@export var lifetime := 1.0
@export var damage := 5
## Размер пули в пикселях (длина по направлению полёта, толщина).
@export var size := Vector2(12.0, 5.0)
@export var color := Color(1.0, 0.9, 0.4)

## Направление полёта (единичный вектор). Задаёт игрок до add_child().
var direction := Vector2.RIGHT

var _spent := false

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	_collision.shape = rect
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	add_to_group("player_projectiles")  # умные враги видят летящие в них снаряды
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * Game.tiles(speed_tiles) * delta


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	_spent = true
	var enemy := body as Enemy
	if enemy:
		enemy.take_damage(damage, global_position)
	queue_free()  # и во врага, и в блок


## Заглушка вместо спрайта.
func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), color)


## Скорость полёта, px/с (по ней умные враги решают, уворачиваться ли).
func travel_velocity() -> Vector2:
	return direction * Game.tiles(speed_tiles)
