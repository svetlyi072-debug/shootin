class_name EnemyProjectile
extends Area2D
## Снаряд врага: бомба гоблина, споры гриба, меч рыцаря, заряд глаза, огненный шар червя.
## Летит по прямой или по дуге (если задана гравитация), ранит игрока при попадании
## и взрывается о блоки (сквозные платформы пролетает). С радиусом взрыва ранит и того,
## кто стоял рядом с местом взрыва. Анимации берутся из SpriteFrames: fly — полёт,
## explode — попадание (если её нет, снаряд просто исчезает).
## Создаётся кодом: EnemyProjectile.launch(parent, from, velocity, frames, {параметры}).

var velocity := Vector2.ZERO
## Ускорение вниз, px/с² (0 — летит по прямой).
var fall_acceleration := 0.0
var damage := 10
## Радиус взрыва, px (0 — ранит только прямым попаданием).
var explode_radius := 0.0
var lifetime := 4.0
## Поворачивать спрайт по направлению полёта (огненный шар).
var face_velocity := false
## Отражать спрайт, когда снаряд летит влево (меч).
var flip_with_velocity := false

var _exploded := false
var _hit_player := false
var _sprite: AnimatedSprite2D


## Создаёт и запускает снаряд. options: gravity, damage, explode_radius, lifetime,
## radius (радиус попадания, px), scale (масштаб спрайта), tint (цвет),
## face_velocity, flip_with_velocity, offset (сдвиг спрайта относительно точки попадания).
static func launch(parent: Node, from: Vector2, launch_velocity: Vector2, frames: SpriteFrames, options := {}) -> EnemyProjectile:
	var projectile := EnemyProjectile.new()
	projectile.velocity = launch_velocity
	projectile.fall_acceleration = options.get("gravity", 0.0)
	projectile.damage = options.get("damage", 10)
	projectile.explode_radius = options.get("explode_radius", 0.0)
	projectile.lifetime = options.get("lifetime", 4.0)
	projectile.face_velocity = options.get("face_velocity", false)
	projectile.flip_with_velocity = options.get("flip_with_velocity", false)
	projectile.collision_layer = 0
	projectile.collision_mask = 1 | 2  # блоки и игрок

	var circle := CircleShape2D.new()
	circle.radius = options.get("radius", 8.0)
	var collision := CollisionShape2D.new()
	collision.shape = circle
	projectile.add_child(collision)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.scale = Vector2.ONE * float(options.get("scale", 1.0))
	sprite.modulate = options.get("tint", Color.WHITE)
	sprite.offset = options.get("offset", Vector2.ZERO)
	projectile.add_child(sprite)
	projectile._sprite = sprite

	parent.add_child(projectile)
	projectile.global_position = from
	return projectile


## Начальная скорость, чтобы за time секунд долететь из from в to при ускорении g вниз.
static func lob_velocity(from: Vector2, to: Vector2, time: float, g: float) -> Vector2:
	return Vector2((to.x - from.x) / time, (to.y - from.y) / time - 0.5 * g * time)


func _ready() -> void:
	z_index = 1
	body_entered.connect(_on_body_entered)
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.play("fly")
	_update_sprite_direction()
	get_tree().create_timer(lifetime, false).timeout.connect(_explode)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	velocity.y += fall_acceleration * delta
	position += velocity * delta
	_update_sprite_direction()


func _update_sprite_direction() -> void:
	if face_velocity and velocity.length_squared() > 1.0:
		_sprite.rotation = velocity.angle()
	if flip_with_velocity:
		_sprite.flip_h = velocity.x < 0.0


func _on_body_entered(body: Node2D) -> void:
	if _exploded:
		return
	var player := body as Player
	if player:
		_hit_player = true
		player.take_damage(damage, global_position)
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	set_deferred("monitoring", false)
	if explode_radius > 0.0 and not _hit_player:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player and player.get_center().distance_to(global_position) <= explode_radius + 12.0:
			player.take_damage(damage, global_position)
	if _sprite.sprite_frames.has_animation("explode"):
		_sprite.rotation = 0.0
		_sprite.play("explode")
	else:
		queue_free()


func _on_animation_finished() -> void:
	if _exploded:
		queue_free()
