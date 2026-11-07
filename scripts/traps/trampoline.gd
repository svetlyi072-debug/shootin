class_name Trampoline
extends Trap
## Батут (символ T): стоит на полу и подбрасывает Шуткина на launch_tiles вверх (обычный
## прыжок — 2,5). Срабатывает от любого касания, в том числе когда на него наступают
## сбоку, — ставьте его там, где нужен высокий уступ. Не ранит.

@export var launch_tiles := 5.4

var _sprite: AnimatedSprite2D


func _ready() -> void:
	super()
	damage = 0
	_add_box(Vector2(34.0, 22.0)).position = Vector2(0.0, -11.0)
	_sprite = _add_sprite("trampoline", "idle", 1.4)
	_sprite.position = Vector2(0.0, -19.6)
	_sprite.animation_finished.connect(_sprite.play.bind("idle"))


func threatens_enemies() -> bool:
	return false  # батут не ранит и врагов не подбрасывает


func _hit(player: Player) -> void:
	_cooldown = 0.4
	player.velocity.y = -sqrt(2.0 * _gravity * Game.tiles(launch_tiles))
	_sprite.play("jump")
	Sound.play("bounce", global_position)
