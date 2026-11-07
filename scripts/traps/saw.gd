class_name Saw
extends Trap
## Пила (символ o): ездит по цепной дорожке туда-обратно по ровному полу.
## Точка на карте — середина пути; дорожка тянется на range_tiles в обе стороны.
## Прыгай над ней: пила невысокая (≈1,6 клетки), а прыжок Шуткина — 2,5.

## Половина длины пути, клеток.
@export var range_tiles := 2.5
## Скорость в середине пути, клеток в секунду (на краях пила замедляется и разворачивается).
@export var speed_tiles := 3.0

## Радиус зубьев (хитбокса), px; центр пилы над полом.
const RADIUS := 23.0
const CENTER_Y := -26.0
const SCALE := 1.5
const CHAIN := preload("res://assets/pixel_adventure/traps/saw_chain.png")

var _time := 0.0
var _shape: CollisionShape2D
var _sprite: AnimatedSprite2D


func _ready() -> void:
	super()
	_shape = _add_circle(RADIUS)
	_sprite = _add_sprite("saw", "spin", SCALE)
	_time = float(int(position.x / Game.TILE) % 7) * 0.9  # соседние пилы идут не в такт
	_place()


func _animate(delta: float) -> void:
	_time += delta
	_place()


func _place() -> void:
	_shape.position = _local_at(0.0)
	_sprite.position = _shape.position


## Где будет центр пилы (в координатах ловушки) через t секунд.
func _local_at(t: float) -> Vector2:
	return Vector2(sin((_time + t) * speed_tiles / range_tiles) * Game.tiles(range_tiles), CENTER_Y)


func zone_at(t: float) -> Rect2:
	var centre := to_global(_local_at(t))
	return Rect2(centre - Vector2(RADIUS, RADIUS), Vector2(RADIUS, RADIUS) * 2.0)


func reach_rect() -> Rect2:
	var reach := Game.tiles(range_tiles) + RADIUS
	return Rect2(to_global(Vector2(-reach, CENTER_Y - RADIUS)), Vector2(reach * 2.0, RADIUS * 2.0))


func _hit_origin() -> Vector2:
	return to_global(_shape.position)


## Дорожка: цепь вдоль пути пилы.
func _draw() -> void:
	var reach := Game.tiles(range_tiles)
	var x := -reach
	while x <= reach:
		draw_texture(CHAIN, Vector2(x - 4.0, CENTER_Y - 4.0))
		x += 8.0
