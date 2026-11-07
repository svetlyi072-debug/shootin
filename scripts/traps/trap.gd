class_name Trap
extends Area2D
## Общая основа ловушек (пила, шипастый шар, огонь, батут): Area2D, которая каждый
## физический кадр ищет у себя в области Шуткина (слой 2) и врагов (слой 3). Касание ранит:
## игрока — урон (его принимает щит, если поднят), отбрасывание и подброс вверх, как у шипов;
## врага — enemy_damage (у каждого врага своя пауза между ударами). Боссы ловушек не боятся.
## Умные враги ловушек остерегаются (см. раздел «Ловушки» в enemy.gd): для этого ловушка
## умеет сказать, где будет опасна через t секунд — zone_at(t).
## Размеры хитбоксов согласованы с tools/validate_levels.js (там зоны ловушек считаются
## смертельными для игрока, чтобы маршрут по уровню их обходил).
## Все ловушки состоят в группе «traps».

@export var damage := 20
## Урон врагу при касании (у слизняка 20 HP, у скелета 40).
@export var enemy_damage := 15
## На сколько клеток ловушка подбрасывает игрока при касании.
@export var bounce_tiles := 1.5

## Ловушка ранит не чаще, чем раз в столько секунд (игрока — и каждого врага отдельно).
const COOLDOWN := 0.6
const FRAMES_DIR := "res://assets/frames/"

var _cooldown := 0.0
## Время ловушки (сек), для пауз между ударами по врагам.
var _clock_s := 0.0
var _enemy_cooldowns := {}
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _ready() -> void:
	add_to_group("traps")
	collision_layer = 0
	collision_mask = 2 | 4  # игрок и враги


func _physics_process(delta: float) -> void:
	_clock_s += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_animate(delta)
	if not is_dangerous():
		return
	for body in get_overlapping_bodies():
		var player := body as Player
		if player:
			if _cooldown <= 0.0 and not player.is_dead():
				_hit(player)
			continue
		var enemy := body as Enemy
		if enemy and threatens_enemies() and not enemy.is_trap_immune() and not enemy.is_dead():
			_hit_enemy(enemy)


## Движение и анимация ловушки (переопределяется).
func _animate(_delta: float) -> void:
	pass


## Опасна ли ловушка прямо сейчас (огонь опасен только пока горит).
func is_dangerous() -> bool:
	return true


## Ранит ли ловушка врагов (батут — нет).
func threatens_enemies() -> bool:
	return true


## Где ловушка будет опасна через t секунд — прямоугольник в мировых координатах
## (нулевого размера — нигде). Умные враги по нему рассчитывают, когда можно пройти.
func zone_at(_t: float) -> Rect2:
	return Rect2()


## Весь участок, где ловушка бывает опасна (мировые координаты), — чтобы быстро отсеять
## далёкие ловушки.
func reach_rect() -> Rect2:
	return Rect2()


## Откуда летит удар (для направления отбрасывания): у подвижных ловушек — место зубьев.
func _hit_origin() -> Vector2:
	return global_position


func _hit(player: Player) -> void:
	_cooldown = COOLDOWN
	player.take_damage(damage, _hit_origin())
	player.velocity.y = -sqrt(2.0 * _gravity * Game.tiles(bounce_tiles))


func _hit_enemy(enemy: Enemy) -> void:
	var id := enemy.get_instance_id()
	if _enemy_cooldowns.get(id, 0.0) > _clock_s:
		return
	_enemy_cooldowns[id] = _clock_s + COOLDOWN
	enemy.take_damage(enemy_damage, _hit_origin())
	enemy.on_trap_hit(self)


# --- Помощники для построения ловушки в коде ----------------------------------------

func _add_sprite(frames_name: String, animation: String, factor: float) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = load(FRAMES_DIR + frames_name + ".tres")
	sprite.scale = Vector2.ONE * factor
	add_child(sprite)
	sprite.play(animation)
	return sprite


func _add_circle(radius: float) -> CollisionShape2D:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	return collision


func _add_box(size: Vector2) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	return collision
