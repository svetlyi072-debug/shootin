class_name GroundWarning
extends Node2D
## Красная метка на полу: сюда через мгновение упадёт огненный шар. Пульсирует
## всё чаще и гаснет, когда время вышло. Ничем не ранит — только предупреждает.

var duration := 1.0
var half_width := 24.0
var _time := 0.0


## Ставит метку в точку at (центр — на полу) на seconds секунд.
static func spawn(parent: Node, at: Vector2, seconds: float, width := 24.0) -> GroundWarning:
	var mark := GroundWarning.new()
	mark.duration = seconds
	mark.half_width = width
	mark.z_index = 0
	parent.add_child(mark)
	mark.global_position = at
	return mark


func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_time / duration, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * (10.0 + 18.0 * progress))
	var alpha := (0.25 + 0.45 * pulse) * (0.4 + 0.6 * progress)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, half_width, Color(1.0, 0.25, 0.1, alpha))
	draw_arc(Vector2.ZERO, half_width, 0.0, TAU, 24, Color(1.0, 0.75, 0.2, minf(alpha + 0.2, 1.0)), 3.0)
