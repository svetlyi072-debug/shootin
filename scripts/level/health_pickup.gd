class_name HealthPickup
extends Area2D
## Аптечка (символ + на карте) — яблоко. Лечит при касании, если здоровье не полное.
## Раненые умные враги тоже бегут к яблокам и съедают их (consume_by_enemy).

@export var heal_amount := 30

var _taken := false

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("health_pickups")
	body_entered.connect(_on_body_entered)
	_sprite.animation_finished.connect(_on_animation_finished)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if _taken or player == null or not player.heal(heal_amount):
		return
	_taken = true
	remove_from_group("health_pickups")
	set_deferred("monitoring", false)
	_sprite.play("collected")


## Враг съел яблоко: лечит его. Возвращает false, если яблоко уже взято.
func consume_by_enemy(enemy: Node) -> bool:
	if _taken:
		return false
	_taken = true
	remove_from_group("health_pickups")
	set_deferred("monitoring", false)
	enemy.call("heal", heal_amount)
	_sprite.play("collected")
	return true


func is_taken() -> bool:
	return _taken


func _on_animation_finished() -> void:
	if _taken:
		queue_free()
