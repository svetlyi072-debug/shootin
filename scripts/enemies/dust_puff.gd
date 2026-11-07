class_name DustPuff
extends AnimatedSprite2D
## Облачко пыли: проигрывается один раз и исчезает. Ставится на землю (точка at — на полу).
## Кадры — assets/frames/dust_puff.tres (из design/source/fx_dust_rock.webp).

const FRAMES := preload("res://assets/frames/dust_puff.tres")


static func spawn(parent: Node, at: Vector2, factor := 1.6) -> DustPuff:
	var puff := DustPuff.new()
	puff.scale = Vector2.ONE * factor
	parent.add_child(puff)
	puff.global_position = at
	return puff


func _ready() -> void:
	sprite_frames = FRAMES
	offset = Vector2(0.0, -28.0)  # в кадре 64×64 пол — строка 60, центр — 32
	z_index = 1
	animation_finished.connect(queue_free)
	play("puff")
