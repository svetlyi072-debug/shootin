class_name Player
extends CharacterBody2D
## Игрок «Шуткин».
## Анимаций и спрайтов пока нет: вместо них цветной прямоугольник (узел Body)
## и подпись с текущим состоянием (StateLabel). Анимации подключать в _enter_state().

enum State { IDLE, RUN, JUMP, ATTACK, CHARGE, SHOOT, HURT, DEAD }

const SPHERE_SCENE := preload("res://scenes/player/energy_sphere.tscn")
const BULLET_SCENE := preload("res://scenes/player/bullet.tscn")

@export_group("Здоровье")
@export var max_health := 100

@export_group("Движение")
## Скорость бега, клеток в секунду.
@export var run_speed_tiles := 5.0
## Во сколько раз быстрее бег с зажатым Shift.
@export var sprint_multiplier := 1.3
## Высота прыжка в клетках (больше 1, чтобы запрыгивать на блок и перепрыгивать врагов).
@export var jump_height_tiles := 2.5

@export_group("Удар")
@export var attack_damage := 10
## Дальность удара перед игроком, в клетках.
@export var attack_range_tiles := 1.0
## На сколько клеток выше головы достаёт удар (чтобы можно было сбить мышь над собой).
@export var attack_reach_up_tiles := 1.0
## Перезарядка удара, сек.
@export var attack_cooldown := 1.5
## Сколько длится замах (состояние ATTACK), сек.
@export var attack_duration := 0.25

@export_group("Стрельба")
## Урон обычной пули. Слабее удара, зато бьёт на расстоянии и в любую сторону.
@export var shoot_damage := 5
## Пауза между выстрелами, сек. Кнопку можно держать зажатой.
@export var shoot_cooldown := 0.3

@export_group("Заряженная сфера")
## Сколько очков силы нужно для выстрела.
@export var max_power := 50
## Заряд: игрок стоит, вытянув руки, сек.
@export var charge_time := 0.3
## Выстрел: игрок разводит руки, после чего вылетает сфера, сек.
@export var shoot_time := 0.1
## true — сфера выпускается сама, как только шкала заполнится;
## false — по кнопке «sphere» (K / ПКМ) при полной шкале.
@export var auto_fire_sphere := false

@export_group("Получение урона")
## На сколько клеток отбрасывает при получении урона.
@export var knockback_tiles := 1.0
## За сколько секунд проходит отбрасывание.
@export var knockback_time := 0.15

@export_group("Щит")
## Энергетический щит (на лёгкой и нормальной сложности). Работает, пока зажата кнопка
## «shield» (H / средняя кнопка мыши): поглощает урон из запаса shield_max.
## Со щитом нельзя бить и стрелять, и бег медленнее.
@export var shield_max := 50
## Сколько единиц запаса тратится в секунду, пока щит поднят (50 / 8 ≈ 6 с).
@export var shield_drain_per_second := 8.0
## Скорость бега со щитом (доля от обычной).
@export var shield_move_factor := 0.6
## Сколько единиц восстанавливается в секунду, пока щит опущен…
@export var shield_regen_per_second := 20.0
## …если столько секунд его не поднимали и он не принимал урон.
@export var shield_regen_delay := 1.5

var health := 0
var power := 0
## Текущий щит (0, если на этой сложности щита нет).
var shield := 0.0
var state: State = State.IDLE
## 1 — смотрит вправо, -1 — влево.
var facing := 1

var _state_time := 0.0
var _attack_cd := 0.0
var _shoot_cd := 0.0
var _knockback_dir := 0.0
var _shield_cd := 0.0
## Щит поднят (зажата кнопка, есть запас).
var _shielding := false
## Сколько секунд прошло с последнего выстрела (умные враги смотрят, куда ты целишься).
var _since_shot := 99.0
var _shield_flash := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _body: Node2D = $Body
@onready var _sprite: AnimatedSprite2D = $Body/Sprite
@onready var _attack_area: Area2D = $AttackArea
@onready var _attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var _camera: Camera2D = $Camera2D
@onready var _state_label: Label = $StateLabel


func _ready() -> void:
	health = max_health
	shield = float(shield_max) if has_shield() else 0.0
	_setup_attack_shape()
	Game.enemy_killed.connect(_on_enemy_killed)
	_state_label.visible = Game.SHOW_STATE_LABELS
	_update_label()
	# HUD может быть ещё не готов — отправляем стартовые значения в конце кадра.
	_emit_stats.call_deferred()


func _physics_process(delta: float) -> void:
	_state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_shoot_cd = maxf(_shoot_cd - delta, 0.0)
	_update_shield(delta)

	if not is_on_floor():
		velocity.y += _gravity * delta

	match state:
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, Game.tiles(20.0) * delta)
		State.HURT:
			velocity.x = _knockback_dir * Game.tiles(knockback_tiles) / knockback_time
			if _state_time >= knockback_time:
				velocity.x = 0.0
				_set_state(State.IDLE)
		State.CHARGE:
			velocity.x = 0.0
			_face_aim()
			if _state_time >= charge_time:
				_set_state(State.SHOOT)
		State.SHOOT:
			velocity.x = 0.0
			_face_aim()
			if _state_time >= shoot_time:
				_fire_sphere()
				_set_state(State.IDLE)
		_:
			_handle_input()

	move_and_slide()
	_update_movement_state()
	_update_animation()
	if state in [State.ATTACK, State.CHARGE, State.SHOOT]:
		queue_redraw()  # взмах и растущая сфера рисуются в _draw()


# --- Публичные методы --------------------------------------------------------

func take_damage(amount: int, source_position: Vector2) -> void:
	if state == State.DEAD or Game.is_game_over:
		return
	amount = _absorb_with_shield(amount)
	if amount <= 0:
		return  # щит принял удар целиком — ни урона, ни отбрасывания
	health = maxi(health - amount, 0)
	Game.player_health_changed.emit(health, max_health)
	if health == 0:
		_die()
		return
	# Отбрасывание на knockback_tiles клеток в сторону от источника урона.
	_knockback_dir = signf(global_position.x - source_position.x)
	if _knockback_dir == 0.0:
		_knockback_dir = -facing
	velocity.y = -Game.tiles(4.0)  # небольшой подскок
	_set_state(State.HURT)
	_state_time = 0.0  # повторный удар во время HURT продлевает отбрасывание


func has_shield() -> bool:
	return Game.player_has_shield() and shield_max > 0


## Щит поднят прямо сейчас.
func is_shielding() -> bool:
	return _shielding and state != State.DEAD


## Поднять или опустить щит не кнопкой, а из кода (для тестов и подсказок).
func set_shielding(on: bool) -> void:
	_shielding = on and has_shield() and shield > 0.0


## Куда целится игрок (к курсору) и стрелял ли он только что — по этому умные враги
## заранее уходят с линии огня.
func aim_direction() -> Vector2:
	var to_cursor := get_global_mouse_position() - get_muzzle()
	return to_cursor.normalized() if to_cursor.length_squared() > 1.0 else Vector2(facing, 0.0)


func seconds_since_shot() -> float:
	return _since_shot


## Игрок открыт для удара: только что замахнулся (удар на перезарядке), его отбросило
## или щит пуст.
func is_vulnerable() -> bool:
	return state == State.HURT or state == State.CHARGE or state == State.SHOOT or _attack_cd > attack_cooldown - 0.9


## Щит забирает себе сколько может; возвращает урон, который дошёл до здоровья.
## Любой урон, даже поглощённый, откладывает восстановление щита.
func _absorb_with_shield(amount: int) -> int:
	if not is_shielding():
		return amount
	_shield_cd = shield_regen_delay
	if shield <= 0.0:
		return amount
	var absorbed := minf(shield, float(amount))
	shield -= absorbed
	if shield <= 0.0:
		_shielding = false  # щит пробит — опущен
	_shield_flash = 0.25
	Game.player_shield_changed.emit(roundi(shield), shield_max)
	queue_redraw()
	return amount - roundi(absorbed)


func _update_shield(delta: float) -> void:
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_since_shot += delta
	if not has_shield() or state == State.DEAD:
		_shielding = false
		return
	if state != State.IDLE and state != State.RUN and state != State.JUMP:
		_shielding = false  # в замахе, при заряде и отбрасывании щит опущен
	if _shielding:
		var before_drain := roundi(shield)
		shield = maxf(shield - shield_drain_per_second * delta, 0.0)
		_shield_cd = shield_regen_delay
		if shield <= 0.0:
			_shielding = false
		if roundi(shield) != before_drain:
			Game.player_shield_changed.emit(roundi(shield), shield_max)
	elif _shield_cd > 0.0:
		_shield_cd -= delta
	elif shield < shield_max:
		var before := roundi(shield)
		shield = minf(shield + shield_regen_per_second * delta, shield_max)
		if roundi(shield) != before:
			Game.player_shield_changed.emit(roundi(shield), shield_max)
	queue_redraw()


## Лечит игрока. Возвращает false, если лечить нечего (здоровье полное или игрок мёртв).
func heal(amount: int) -> bool:
	if state == State.DEAD or health >= max_health:
		return false
	health = mini(health + amount, max_health)
	Game.player_health_changed.emit(health, max_health)
	return true


## Мгновенная смерть (падение в пропасть).
func kill() -> void:
	if state == State.DEAD or Game.is_game_over:
		return
	health = 0
	Game.player_health_changed.emit(health, max_health)
	_die()


func add_power(amount: int) -> void:
	if state == State.DEAD:
		return
	power = mini(power + amount, max_power)
	Game.player_power_changed.emit(power, max_power)


func is_dead() -> bool:
	return state == State.DEAD


## Центр тела (точка отсчёта самого узла — у ног).
func get_center() -> Vector2:
	return _shape.global_position


func get_body_rect() -> Rect2:
	var size := (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.global_position - size / 2.0, size)


func set_camera_limits(bounds: Rect2) -> void:
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.reset_smoothing()


# --- Управление и состояния ---------------------------------------------------

func _handle_input() -> void:
	_shielding = has_shield() and shield > 0.0 and Input.is_action_pressed("shield")
	var dir := Input.get_axis("move_left", "move_right")
	var speed := Game.tiles(run_speed_tiles)
	if _shielding:
		speed *= shield_move_factor
	elif Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier
	velocity.x = dir * speed
	if dir != 0.0:
		_set_facing(1 if dir > 0.0 else -1)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -sqrt(2.0 * _gravity * Game.tiles(jump_height_tiles))

	if _shielding:
		return  # за щитом не бьют и не стреляют

	if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
		_attack()

	# Стрельба: ЛКМ — в сторону курсора, L — вперёд. Кнопку можно держать зажатой.
	if _shoot_cd <= 0.0:
		if Input.is_action_pressed("shoot"):
			shoot(get_global_mouse_position() - get_muzzle())
		elif Input.is_action_pressed("shoot_forward"):
			shoot(Vector2(facing, 0.0))

	if power >= max_power and (auto_fire_sphere or Input.is_action_just_pressed("sphere")):
		_set_state(State.CHARGE)


## Переключает IDLE / RUN / JUMP, если игрок не занят другим действием.
func _update_movement_state() -> void:
	match state:
		State.IDLE, State.RUN, State.JUMP:
			pass
		State.ATTACK:
			if _state_time < attack_duration:
				return
		_:
			return

	if not is_on_floor():
		_set_state(State.JUMP)
	elif absf(velocity.x) > 1.0:
		_set_state(State.RUN)
	else:
		_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	_state_time = 0.0
	_enter_state(new_state)
	_update_label()


## Анимации (assets/frames/player.tres) выбирает _update_animation():
##   IDLE, CHARGE, SHOOT — idle (покачивание); при заряде между руками растёт сфера (_draw)
##   RUN    — run
##   JUMP   — jump при взлёте, fall при падении
##   ATTACK — анимация движения + взмах-дуга перед игроком (_draw)
##   HURT, DEAD — hit; при смерти герой ещё и «ложится»
func _update_animation() -> void:
	var anim := "idle"
	match state:
		State.RUN:
			anim = "run"
		State.JUMP:
			anim = "jump" if velocity.y < 0.0 else "fall"
		State.ATTACK:
			if not is_on_floor():
				anim = "jump" if velocity.y < 0.0 else "fall"
			elif absf(velocity.x) > 1.0:
				anim = "run"
		State.HURT, State.DEAD:
			anim = "hit"
	if _sprite.animation != anim:
		_sprite.play(anim)


func _enter_state(new_state: State) -> void:
	if new_state == State.DEAD:
		# Заглушка вместо анимации падения: «кладём» прямоугольник на землю.
		_body.rotation_degrees = 90.0
		_body.position.y = -(_shape.shape as RectangleShape2D).size.x / 2.0
	queue_redraw()


func _die() -> void:
	_set_state(State.DEAD)
	Game.is_game_over = true
	Game.player_died.emit()


# --- Удар ---------------------------------------------------------------------

## Зона удара: от оси игрока вперёд на attack_range_tiles за границу тела,
## по высоте — от ног до attack_reach_up_tiles выше головы.
func _setup_attack_shape() -> void:
	var body_size := (_shape.shape as RectangleShape2D).size
	var rect := RectangleShape2D.new()
	rect.size = Vector2(
		body_size.x / 2.0 + Game.tiles(attack_range_tiles),
		body_size.y + Game.tiles(attack_reach_up_tiles))
	_attack_shape.shape = rect
	_update_attack_shape_position()


func _update_attack_shape_position() -> void:
	var size := (_attack_shape.shape as RectangleShape2D).size
	_attack_shape.position = Vector2(facing * size.x / 2.0, -size.y / 2.0)


func _attack() -> void:
	_attack_cd = attack_cooldown
	_note_attack("melee")
	Sound.play("punch", global_position)
	_set_state(State.ATTACK)
	# Мгновенная проверка зоны удара перед игроком.
	# TODO: когда появится анимация, наносить урон в нужном кадре замаха.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _attack_shape.shape
	query.transform = _attack_shape.global_transform
	query.collision_mask = _attack_area.collision_mask
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var enemy := hit["collider"] as Enemy
		if enemy:
			enemy.take_damage(attack_damage, global_position)


func _set_facing(dir: int) -> void:
	if dir == facing:
		return
	facing = dir
	_body.scale.x = facing
	_update_attack_shape_position()


# --- Обычная стрельба ---------------------------------------------------------

## Выстрел обычной пулей в сторону direction (длина не важна).
## Шкалу силы не тратит — она нужна только для заряженной сферы.
func shoot(direction: Vector2) -> void:
	if state == State.DEAD or Game.is_game_over:
		return
	if direction.length_squared() < 1.0:
		direction = Vector2(facing, 0.0)
	direction = direction.normalized()
	_shoot_cd = shoot_cooldown
	_since_shot = 0.0
	_note_attack("bullet")
	Sound.play("shot", global_position)
	if absf(direction.x) > 0.1:
		_set_facing(1 if direction.x > 0.0 else -1)
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.direction = direction
	bullet.damage = shoot_damage
	get_parent().add_child(bullet)
	bullet.global_position = get_muzzle() + direction * Game.tiles(0.6)


## Точка вылета пуль и начало прицеливания: на уровне груди, чуть ниже центра тела,
## чтобы пули, летящие вперёд, попадали и в низких врагов (слизняк ростом 20 px).
func get_muzzle() -> Vector2:
	return get_center() + Vector2(0.0, Game.tiles(0.25))


# --- Заряженная сфера ---------------------------------------------------------

func _fire_sphere() -> void:
	_note_attack("sphere")
	Sound.play("sphere", global_position)
	power = 0
	Game.player_power_changed.emit(power, max_power)
	var aim := sphere_aim()
	var sphere := SPHERE_SCENE.instantiate() as EnergySphere
	sphere.direction = aim
	get_parent().add_child(sphere)
	sphere.global_position = get_muzzle() + aim * Game.tiles(0.75)


## Куда полетит заряженная сфера: в сторону курсора мыши (единичный вектор).
## Курсор читается в момент выстрела, так что целиться можно и во время заряда.
func sphere_aim() -> Vector2:
	var to_cursor := get_global_mouse_position() - get_muzzle()
	if to_cursor.length_squared() < 1.0:
		return Vector2(facing, 0.0)
	return to_cursor.normalized()


## Во время заряда герой поворачивается к курсору.
func _face_aim() -> void:
	var aim := sphere_aim()
	if absf(aim.x) > 0.1:
		_set_facing(1 if aim.x > 0.0 else -1)


## Сообщаем уровню, чем игрок атакует, — умные враги подстраиваются под его стиль.
func _note_attack(kind: String) -> void:
	var lv := get_tree().get_first_node_in_group("level")
	if lv:
		lv.note_player_attack(kind)


func _on_enemy_killed(_enemy: Node, reward: int) -> void:
	add_power(reward)


# --- Отладка ------------------------------------------------------------------

func _emit_stats() -> void:
	Game.player_health_changed.emit(health, max_health)
	Game.player_power_changed.emit(power, max_power)
	Game.player_shield_changed.emit(roundi(shield), shield_max if has_shield() else 0)


func _update_label() -> void:
	_state_label.text = State.keys()[state]


## Эффекты, которых нет в наборе графики: пузырь щита, взмах при ударе и растущая сфера.
func _draw() -> void:
	if is_shielding():
		# Пузырь щита: чем больше щит, тем заметнее; вспыхивает, когда принимает удар.
		var strength := shield / shield_max
		var flash := _shield_flash / 0.25
		var bubble_center := _shape.position + Vector2(0.0, 2.0)
		var color := Color(0.55, 0.85, 1.0).lerp(Color.WHITE, flash)
		draw_circle(bubble_center, 34.0, Color(color, 0.08 + 0.1 * strength + 0.25 * flash))
		draw_arc(bubble_center, 34.0, 0.0, TAU, 40, Color(color, 0.25 + 0.45 * strength + 0.3 * flash), 2.0)
	if state == State.ATTACK:
		var fade := 1.0 - clampf(_state_time / attack_duration, 0.0, 1.0)
		var center := Vector2(facing * 6.0, _shape.position.y - 6.0)
		var from := -PI / 2.4 if facing > 0 else PI - PI / 2.4
		var to := PI / 3.0 if facing > 0 else PI + PI / 3.0
		draw_arc(center, Game.tiles(1.0), from, to, 16, Color(1.0, 1.0, 1.0, 0.8 * fade), 4.0)
	elif state == State.CHARGE or state == State.SHOOT:
		# Сфера растёт там, откуда вылетит, — со стороны курсора.
		var grow := clampf(_state_time / charge_time, 0.0, 1.0) if state == State.CHARGE else 1.0
		var at := get_muzzle() - global_position + sphere_aim() * Game.tiles(0.75)
		draw_circle(at, lerpf(2.0, Game.tiles(0.4), grow), Color(0.45, 0.85, 1.0, 0.9))


## Удар игрока готов (не на перезарядке) — умные враги не лезут под готовый удар.
func melee_ready() -> bool:
	return _attack_cd <= 0.0
