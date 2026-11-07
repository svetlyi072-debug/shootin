class_name SpikedBall
extends Trap
## Шипастый шар на цепи (символ *): качается маятником. Точка на карте — место крепления
## цепи: верх клетки, поэтому ставьте символ в клетку прямо под потолком.
## Шар проходит над полом на chain_tiles ниже крепления — перебегай, когда он ушёл в сторону.

@export var chain_tiles := 3.0
## Размах от вертикали в каждую сторону, градусы.
@export var swing_degrees := 65.0
## Период полного качания, сек.
@export var period := 3.6

const RADIUS := 15.0
const SCALE := 1.1
const BALL := preload("res://assets/pixel_adventure/traps/spiked_ball.png")
const CHAIN := preload("res://assets/pixel_adventure/traps/spiked_ball_chain.png")

var _time := 0.0
var _shape: CollisionShape2D
var _ball: Sprite2D


func _ready() -> void:
	super()
	position.y -= Game.TILE  # игра ставит предметы у низа клетки, а цепь крепится к верху
	_shape = _add_circle(RADIUS)
	_ball = Sprite2D.new()
	_ball.texture = BALL
	_ball.scale = Vector2.ONE * SCALE
	add_child(_ball)
	_time = float(int(position.x / Game.TILE) % 5) * 0.7
	_swing()


func _animate(delta: float) -> void:
	_time += delta
	_swing()
	queue_redraw()


## Угол цепи от вертикали, радианы.
func angle() -> float:
	return deg_to_rad(swing_degrees) * sin(TAU * _time / period)


func _swing() -> void:
	var at := _local_at(0.0)
	var a := angle()
	_shape.position = at
	_ball.position = at
	_ball.rotation = a * 2.0


## Где будет центр шара (в координатах ловушки) через t секунд.
func _local_at(t: float) -> Vector2:
	var a := deg_to_rad(swing_degrees) * sin(TAU * (_time + t) / period)
	return Vector2(sin(a), cos(a)) * Game.tiles(chain_tiles)


func zone_at(t: float) -> Rect2:
	var centre := to_global(_local_at(t))
	return Rect2(centre - Vector2(RADIUS, RADIUS), Vector2(RADIUS, RADIUS) * 2.0)


func reach_rect() -> Rect2:
	var reach := Game.tiles(chain_tiles) * sin(deg_to_rad(swing_degrees)) + RADIUS
	var low := Game.tiles(chain_tiles) + RADIUS
	var high := Game.tiles(chain_tiles) * cos(deg_to_rad(swing_degrees)) - RADIUS
	return Rect2(to_global(Vector2(-reach, high)), Vector2(reach * 2.0, low - high))


func _hit_origin() -> Vector2:
	return to_global(_shape.position)


## Цепь от крепления до шара.
func _draw() -> void:
	if _shape == null:
		return
	var end := _shape.position
	var links := maxi(int(end.length() / 8.0), 1)
	for i in range(0, links):
		draw_texture(CHAIN, end * (float(i) / float(links)) - Vector2(4.0, 4.0))
