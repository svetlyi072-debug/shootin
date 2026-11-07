class_name ExitDoor
extends Area2D
## Выход с уровня (символ E на карте): флаг-финиш высотой 2 клетки.
## Закрыт (красноватый, надпись «ЗАКРЫТО»), пока на уровне с REQUIRE_CLEAR остаются враги.
## Сам выход только сообщает о касании — завершает уровень level.gd.

signal player_touched

const LOCKED_TINT := Color(1.0, 0.4, 0.4)

var locked := false:
	set(value):
		locked = value
		if is_node_ready():
			_apply_look()

@onready var _label: Label = $Label
@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_look()


## Уровень пройден через этот выход — флаг машет.
func celebrate() -> void:
	_sprite.play("pressed")


func _apply_look() -> void:
	_label.text = "ЗАКРЫТО" if locked else "ВЫХОД"
	_sprite.modulate = LOCKED_TINT if locked else Color.WHITE


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_touched.emit()
