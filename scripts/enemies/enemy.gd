class_name Enemy
extends CharacterBody2D
## Базовый класс врагов: здоровье, получение урона, смерть, награда за убийство,
## поиск игрока и общая физика. Поведение конкретного врага — в _update_ai() наследника.
##
## Соглашение для наследников: в их enum State первым идёт IDLE (= 0)
## и обязательно есть DEAD.
##
## Два режима поведения (зависят от сложности, см. Game.smart_enemies()):
##   * без ИИ (лёгкая) — враг ходит туда-обратно у места появления (patrol) и не охотится;
##     бьёт, только если игрок оказался прямо перед ним;
##   * умный (нормальная и сложная) — враг видит игрока только напрямую (стены загораживают),
##     заметив — зовёт соседей и помнит о нём, даже потеряв из виду; обходит с фланга,
##     перепрыгивает стенки и ямы, не прыгает в пропасти и на шипы, уворачивается от пуль,
##     слабые убегают при малом здоровье, стрелки целятся на упреждение.
## Готовые «умения» — в разделе «Интеллект» ниже; наследники комбинируют их в _update_ai().

signal died(enemy: Enemy)

@export_group("Базовые параметры")
@export var max_health := 20
## Сколько очков шкалы силы получает игрок за убийство.
@export var power_reward := 10
## Сколько секунд тело остаётся на сцене после смерти.
@export var corpse_time := 1.0
## Подпрыгивать, упёршись в блок по пути к игроку.
@export var can_jump_on_blocks := false
@export var block_jump_height_tiles := 1.4

@export_group("Интеллект")
## Насколько далеко (клетки) от места появления враг ходит, патрулируя.
@export var patrol_radius_tiles := 3.0
## Шанс увернуться от летящей в него пули или сферы (умный режим).
@export_range(0.0, 1.0) var dodge_chance := 0.4
## Убегает, когда здоровье ниже этой доли (0 — никогда; умный режим).
@export_range(0.0, 1.0) var flee_below_health := 0.0
## Стенки какой высоты (клетки) умный враг перепрыгивает.
@export var smart_climb_tiles := 2.0
## Шанс, что умный враг заметит ловушку на своём пути (решает один раз за встречу с ней).
## Не заметивший идёт как ни в чём не бывало и получает урон; заметивший ждёт, пока
## пила или шар отойдут, а огонь погаснет.
@export_range(0.0, 1.0) var trap_awareness := 0.8

## Сколько секунд умный враг помнит игрока, потеряв его из виду.
## На огромных картах далёкие враги «спят»: пока игрок дальше этого расстояния (клетки),
## они ничего не считают и не двигаются (экран шире — около 40 клеток).
const SLEEP_DISTANCE_TILES := 48.0
const AWARENESS_MEMORY := 5.0
## Заметив игрока, враг зовёт соседей в этом радиусе (клетки).
const ALARM_RADIUS_TILES := 7.0
## Горизонтальная скорость прыжка через яму или шипы (клетки/с).
const LEAP_SPEED_TILES := 5.0

var health := 0
var state := 0
## 1 — смотрит вправо, -1 — влево.
var facing := -1

var _state_time := 0.0
var _attack_cd := 0.0
var _dead := false
var _hurting := false
## Отложенные действия текущего состояния: [момент _state_time, Callable].
var _queued: Array = []
var _player: Player
## Умный режим (нормальная и сложная сложность).
var smart := true
var _alerted := false
var _unseen_time := 0.0
var _spawn_x := 0.0
var _spawn_y := 0.0
var _patrol_dir := -1
var _dodge_cd := 0.0
var _considered_projectiles := {}
var _fled := false
var _flee_time := 0.0
var _flank_side := 0
var _flank_timer := 0.0
var _leaping := false
var _level: Node
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _settled := false

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _body: Node2D = $Body
@onready var _sprite: AnimatedSprite2D = get_node_or_null("Body/Sprite")
@onready var _state_label: Label = $StateLabel


func _ready() -> void:
	health = max_health
	smart = Game.smart_enemies()
	_spawn_x = global_position.x
	_spawn_y = global_position.y
	_patrol_dir = facing
	add_to_group("enemies")
	_body.scale.x = facing
	_state_label.visible = Game.SHOW_STATE_LABELS
	if _sprite:
		_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_update_label()
	_play_state_animation()


func _physics_process(delta: float) -> void:
	if _sleeping_far_away():
		return
	_state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_flee_time = maxf(_flee_time - delta, 0.0)
	_flank_timer = maxf(_flank_timer - delta, 0.0)
	_tick_brain(delta)
	if _leaping and is_on_floor() and velocity.y >= 0.0:
		_leaping = false

	if _uses_gravity() and not is_on_floor():
		velocity.y += _gravity * delta

	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, Game.tiles(20.0) * delta)
	elif has_target():
		_run_queued_actions()
		_update_ai(delta)
		_apply_trap_caution(delta)
	else:
		_on_no_target()

	move_and_slide()


## Враг далеко от игрока и уже стоит на месте — можно не считать (экономит время на огромных картах).
func _sleeping_far_away() -> bool:
	if _dead or not has_target():
		return false
	if not _settled:
		_settled = is_on_floor() or not _uses_gravity()
		return false
	var limit := Game.tiles(SLEEP_DISTANCE_TILES)
	return global_position.distance_squared_to(get_player().global_position) > limit * limit


## Выполнить action через delay секунд, если враг к тому времени всё ещё в этом
## состоянии (смена состояния или смерть отменяют). Так удар или бросок срабатывают
## в нужный момент анимации, а не в начале замаха.
func queue_action(delay: float, action: Callable) -> void:
	_queued.append([_state_time + delay, action])


func _run_queued_actions() -> void:
	var due := _queued.filter(func(item: Array) -> bool: return item[0] <= _state_time)
	if due.is_empty():
		return
	_queued = _queued.filter(func(item: Array) -> bool: return item[0] > _state_time)
	for item in due:
		(item[1] as Callable).call()


## Удар вблизи: ранит игрока, если он в radius_tiles (дистанция из концепта).
func strike_player(radius_tiles: float, damage: int) -> void:
	if has_target() and is_player_in_range(radius_tiles):
		get_player().take_damage(damage, get_center())


# --- Переопределяется в наследниках ------------------------------------------

## Поведение врага. Вызывается каждый физический кадр, пока враг жив и игрок доступен.
func _update_ai(_delta: float) -> void:
	pass


## Имена состояний (обычно State.keys()) — для отладочной подписи.
func _state_names() -> Array:
	return ["IDLE", "DEAD"]


## Вызывается при входе в новое состояние (анимация запускается сама, см. _state_animation).
func _enter_state(_new_state: int) -> void:
	pass


## Какую анимацию из SpriteFrames играть в состоянии. "" — не менять текущую.
func _state_animation(_for_state: int) -> String:
	return ""


## Скорость анимации в состоянии (1 — как в SpriteFrames).
func _animation_speed(_for_state: int) -> float:
	return 1.0


## Анимация получения урона ("" — нет).
func _hurt_animation() -> String:
	return ""


## Вызывается после получения урона (уже после уменьшения health).
func _on_damaged(_amount: int) -> void:
	pass


func _uses_gravity() -> bool:
	return true


# --- Здоровье и смерть -------------------------------------------------------

func take_damage(amount: int, _source_position: Vector2 = Vector2.ZERO) -> void:
	if _dead:
		return
	health = maxi(health - amount, 0)
	_on_damaged(amount)
	_update_label()
	if health == 0:
		die()
	elif _sprite and _hurt_animation() != "":
		_hurting = true
		_restart_animation(_hurt_animation())


func die() -> void:
	if _dead:
		return
	_dead = true
	_hurting = false
	_queued.clear()
	_drop_token()
	# По «трупу» больше нельзя попасть, но он по-прежнему лежит на блоках.
	set_deferred("collision_layer", 0)
	remove_from_group("enemies")
	set_state(_state_names().find("DEAD"))
	Game.enemy_killed.emit(self, power_reward)
	died.emit(self)
	get_tree().create_timer(corpse_time, false).timeout.connect(queue_free)


func is_dead() -> bool:
	return _dead


# --- Состояния ---------------------------------------------------------------

## Состояния, в которых враг атакует (по именам из enum State наследников): при входе
## в такое состояние звучит звук атаки. Защита, призыв, ходьба и т. п. не считаются.
const ATTACK_STATES := ["ATTACK", "SLASH", "THROW", "SPIT", "RAIN", "SLAM", "SPORES", "CAST", "DIVE", "LAND", "LEAP", "BURST", "ROLL", "STOMP", "ATTACK1", "ATTACK2", "ATTACK3"]


func _is_attack_state(new_state: int) -> bool:
	var names := _state_names()
	return new_state >= 0 and new_state < names.size() and names[new_state] in ATTACK_STATES


## Какое событие Sound играть при атаке (боссы переопределяют — звук ниже и громче).
func _attack_sound() -> String:
	return "enemy_attack"


func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	_state_time = 0.0
	_queued.clear()
	_enter_state(new_state)
	if _is_attack_state(new_state):
		Sound.play(_attack_sound(), global_position)
	_play_state_animation()
	_update_label()


# --- Анимации -----------------------------------------------------------------

func _play_state_animation() -> void:
	if _sprite == null or _hurting:
		return
	_sprite.speed_scale = _animation_speed(state)
	var anim := _state_animation(state)
	if anim != "":
		_restart_animation(anim)


func _restart_animation(anim: String) -> void:
	if not _sprite.sprite_frames.has_animation(anim):
		push_warning("%s: нет анимации «%s»" % [name, anim])
		return
	_sprite.stop()
	_sprite.play(anim)


func _on_sprite_animation_finished() -> void:
	if _hurting:
		_hurting = false
		if not _dead:
			_play_state_animation()


func _on_no_target() -> void:
	velocity.x = 0.0
	if not _uses_gravity():
		velocity.y = 0.0
	set_state(0)


func _update_label() -> void:
	_state_label.text = "%s %d/%d" % [_state_names()[state], health, max_health]


# --- Интеллект -----------------------------------------------------------------

func level() -> Node:
	if not is_instance_valid(_level):
		_level = get_tree().get_first_node_in_group("level")
	return _level


## Видит ли враг игрока: между ними нет блоков (сквозные платформы не мешают).
func can_see_player() -> bool:
	var query := PhysicsRayQueryParameters2D.create(get_center(), get_player().get_center(), 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Умный враг замечает игрока, если тот ближе range_tiles и виден. Заметив — зовёт
## соседей; потеряв из виду — помнит ещё AWARENESS_MEMORY секунд. Возвращает «охотится ли».
func update_awareness(range_tiles: float, delta: float) -> bool:
	var distance := distance_to_player_tiles()
	if distance <= range_tiles and can_see_player():
		_unseen_time = 0.0
		_last_seen = get_player().global_position
		if not _alerted:
			_alerted = true
			_alert_allies()
	elif _alerted:
		_unseen_time += delta
		if _unseen_time > AWARENESS_MEMORY or distance > range_tiles * 2.5:
			_alerted = false
	return _alerted


## Сосед поднял тревогу — начинаем охоту, даже если сами игрока не видим.
func hear_alarm() -> void:
	if smart and not _dead and not _alerted:
		_alerted = true
		_unseen_time = 0.0
		_last_seen = get_player().global_position


func is_alerted() -> bool:
	return _alerted


func _alert_allies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as Enemy
		if ally != self and ally.get_center().distance_to(get_center()) <= Game.tiles(ALARM_RADIUS_TILES):
			ally.hear_alarm()


## Игрок прямо перед врагом (по направлению взгляда).
func player_in_front() -> bool:
	var dx := get_player().global_position.x - global_position.x
	return absf(dx) < 8.0 or signf(dx) == facing


## Что впереди по направлению dir:
##   wall — высота стенки (клетки), ground — есть ли пол, spikes — ширина шипов,
##   drop — глубина обрыва (0 — пропасть без дна поблизости),
##   gap — ширина ямы, landing — есть ли куда допрыгнуть.
func probe_ahead(dir: int) -> Dictionary:
	var info := {"wall": 0, "ground": true, "spikes": 0, "drop": 0, "gap": 0, "landing": false}
	var lv := level()
	if lv == null or dir == 0:
		return info
	var half := get_body_rect().size.x / 2.0
	var cx := floori((global_position.x + dir * (half + 4.0)) / Game.TILE)
	var floor_row := roundi(global_position.y / Game.TILE)
	for h in range(1, 4):
		if not lv.is_solid_cell(Vector2i(cx, floor_row - h)):
			break
		info["wall"] = h
	var sx := cx
	while info["spikes"] < 4 and lv.is_spike_cell(Vector2i(sx, floor_row - 1)):
		info["spikes"] += 1
		sx += dir
	info["ground"] = lv.is_floor_cell(Vector2i(cx, floor_row))
	if not info["ground"]:
		for depth in range(1, 8):
			if lv.is_floor_cell(Vector2i(cx, floor_row + depth)):
				info["drop"] = depth
				break
		for g in range(1, 4):
			var gx := cx + dir * g
			for dy in [0, -1, 1]:
				var landing := Vector2i(gx, floor_row + dy)
				if lv.is_floor_cell(landing) and not lv.is_spike_cell(landing + Vector2i.UP):
					info["gap"] = g
					info["landing"] = true
					break
			if info["landing"]:
				break
	return info


## Ходит туда-обратно у места появления, разворачиваясь у стен, обрывов и шипов.
func patrol(speed_tiles: float) -> void:
	if not is_on_floor():
		return
	var ahead := probe_ahead(_patrol_dir)
	var too_far := absf(global_position.x + _patrol_dir * Game.TILE - _spawn_x) > Game.tiles(patrol_radius_tiles)
	if ahead["wall"] > 0 or not ahead["ground"] or ahead["spikes"] > 0 or too_far:
		_patrol_dir = -_patrol_dir
		var back := probe_ahead(_patrol_dir)
		if back["wall"] > 0 or not back["ground"] or back["spikes"] > 0:
			velocity.x = 0.0  # зажат с обеих сторон — стоит
			return
	velocity.x = _patrol_dir * Game.tiles(speed_tiles)
	set_facing(_patrol_dir)


## Умное движение к точке target_x: перепрыгивает стенки (до smart_climb_tiles), ямы
## (до 2 клеток) и шипы (до 2 клеток), спрыгивает вниз за игроком, но не прыгает
## в пропасть. Возвращает false, если дальше не пройти (стоит у края).
func move_smart(target_x: float, speed_tiles: float) -> bool:
	var dx := target_x - global_position.x
	var dir := 0
	if absf(dx) >= Game.tiles(0.4):
		dir = 1 if dx > 0.0 else -1
	var speed := Game.tiles(speed_tiles)
	if not is_on_floor():
		if not _leaping:
			velocity.x = dir * speed
		return true
	if dir == 0:
		velocity.x = 0.0
		return true
	set_facing(dir)
	var ahead := probe_ahead(dir)
	if ahead["spikes"] > 0:
		if ahead["spikes"] <= 2:
			_leap(dir, 1.6)
			return true
		velocity.x = 0.0
		return false
	if ahead["wall"] > 0:
		if ahead["wall"] <= smart_climb_tiles:
			velocity = Vector2(dir * speed, -_jump_speed(ahead["wall"] + 0.5))
			return true
		velocity.x = 0.0
		return false
	if not ahead["ground"]:
		var target_below := get_player().global_position.y > global_position.y + Game.TILE * 0.5
		if ahead["drop"] > 0 and ahead["drop"] <= 4 and (target_below or ahead["drop"] <= 1):
			velocity.x = dir * speed  # спрыгиваем вниз
			return true
		if ahead["landing"] and ahead["gap"] <= 2:
			_leap(dir, 1.3)
			return true
		velocity.x = 0.0  # пропасть — ждём у края
		return false
	velocity.x = dir * speed
	return true


func _jump_speed(height_tiles: float) -> float:
	return sqrt(2.0 * _gravity * Game.tiles(height_tiles))


## Прыжок с разбега через яму или шипы.
func _leap(dir: int, height_tiles: float) -> void:
	velocity = Vector2(dir * Game.tiles(LEAP_SPEED_TILES), -_jump_speed(height_tiles))
	_leaping = true


## Точка, куда встать для удара: сбоку от игрока. Если с этой стороны уже кто-то есть,
## а с другой никого — обойти игрока и встать с другой (окружают).
func flank_target_x(offset_tiles: float) -> float:
	var player := get_player()
	var px := player.global_position.x
	if _flank_timer <= 0.0:
		_flank_timer = 1.0
		var my_side := 1 if global_position.x > px else -1
		var crowd := {1: 0, -1: 0}
		for node in get_tree().get_nodes_in_group("enemies"):
			var ally := node as Enemy
			if ally == self or not ally.is_alerted():
				continue
			var near_x := absf(ally.global_position.x - px) < Game.tiles(4.0)
			var near_y := absf(ally.global_position.y - player.global_position.y) < Game.tiles(2.0)
			if near_x and near_y:
				crowd[1 if ally.global_position.x > px else -1] += 1
		_flank_side = my_side
		if crowd[my_side] >= 1 and crowd[-my_side] == 0:
			_flank_side = -my_side
	return px + _flank_side * Game.tiles(offset_tiles)


## Слабый умный враг при малом здоровье на время убегает (один раз за жизнь).
func should_flee() -> bool:
	if not smart or flee_below_health <= 0.0:
		return false
	if not _fled and health < max_health * flee_below_health:
		_fled = true
		_flee_time = 2.5
	return _flee_time > 0.0


func flee(speed_tiles: float) -> void:
	var away := 1 if global_position.x > get_player().global_position.x else -1
	if not move_smart(global_position.x + away * Game.tiles(4.0), speed_tiles):
		_flee_time = 0.0  # загнали в угол — дерётся


## Где будет центр игрока через seconds секунд: умные враги стреляют на упреждение.
func predict_player(seconds: float) -> Vector2:
	var player := get_player()
	var at := player.get_center()
	if smart:
		at.x += player.velocity.x * seconds * 0.85
	return at


## Летит ли во врага пуля или сфера игрока: столкнётся в ближайшие horizon секунд.
## only_sphere — реагировать только на заряженную сферу.
func incoming_projectile(horizon: float, only_sphere := false) -> Node2D:
	for node in get_tree().get_nodes_in_group("player_projectiles"):
		var projectile := node as Node2D
		if only_sphere and not projectile is EnergySphere:
			continue
		var travel: Vector2 = projectile.call("travel_velocity")
		var rel := get_center() - projectile.global_position
		if rel.length() > Game.tiles(5.0) or travel.length_squared() < 1.0:
			continue
		var t := rel.dot(travel) / travel.length_squared()
		if t <= 0.0 or t > horizon:
			continue
		if (rel - travel * t).length() <= get_body_rect().size.y / 2.0 + 12.0:
			return projectile
	return null


## Умный враг пытается увернуться от летящей в него пули или сферы.
## Решает один раз на каждый снаряд (с шансом dodge_chance).
func try_dodge() -> bool:
	if not smart or not _alerted or _dodge_cd > 0.0:
		return false
	var threat := incoming_projectile(0.45)
	if threat == null:
		return false
	var id := threat.get_instance_id()
	if _considered_projectiles.has(id):
		return false
	if _considered_projectiles.size() > 64:
		_considered_projectiles.clear()
	_considered_projectiles[id] = true
	if randf() >= effective_dodge_chance():
		return false
	_dodge_cd = 1.2
	_dodge(threat.call("travel_velocity"))
	return true


## Как уворачиваться (по умолчанию — подпрыгнуть). Летающие и щитоносцы переопределяют.
func _dodge(_threat_velocity: Vector2) -> void:
	if is_on_floor():
		velocity.y = -_jump_speed(1.7)


# --- Мега-мозг: путь, тактика стаи, чтение игрока --------------------------------------

## Путь по графу проходимости (клетки) и куда он ведёт.
var _path: Array = []
var _path_goal := Vector2i(-9999, -9999)
var _path_timer := 0.0
## Где игрок был, когда его видели в последний раз (умный враг идёт туда искать).
var _last_seen := Vector2.ZERO
var _feint_time := 0.0
var _feint_decided := false
var _preempt_cd := 0.0
var _ring_phase := 0.0
var _has_token := false
var _heal_time := 0.0
var _heal_give_up := false


func _tick_brain(delta: float) -> void:
	_brain_clock += delta
	_path_timer = maxf(_path_timer - delta, 0.0)
	_feint_time = maxf(_feint_time - delta, 0.0)
	_preempt_cd = maxf(_preempt_cd - delta, 0.0)
	_ring_phase += delta


## Враг сейчас идёт (для выбора анимации ходьбы или стойки).
func moving() -> bool:
	return absf(velocity.x) > 1.0 or not is_on_floor()


func my_cell() -> Vector2i:
	return Vector2i(floori(global_position.x / Game.TILE), floori((global_position.y - 1.0) / Game.TILE))


## Идти к точке мира по графу проходимости: забираться на блоки и платформы, прыгать через
## ямы, спускаться. Если пути нет — по прямой с обходом ловушек (move_smart).
func navigate_to(world: Vector2, speed_tiles: float) -> void:
	var lv := level()
	if lv == null or lv.nav == null:
		move_smart(world.x, speed_tiles)
		return
	if not is_on_floor():
		if not _leaping:
			var dx := world.x - global_position.x
			velocity.x = (0.0 if absf(dx) < 3.0 else signf(dx)) * Game.tiles(speed_tiles)
		return
	var nav: NavGrid = lv.nav
	var here := nav.nearest_standable(my_cell())
	var goal := nav.nearest_standable(Vector2i(floori(world.x / Game.TILE), floori((world.y - 1.0) / Game.TILE)))
	if absi(goal.x - here.x) > 40:
		move_smart(world.x, speed_tiles)  # цель слишком далеко — путь не ищем
		return
	if (goal != _path_goal or _path_timer <= 0.0) and nav.can_search():
		_path = nav.find_path(here, goal)
		_path_goal = goal
		_path_timer = 0.5 if not _path.is_empty() else 1.2
	var at := _path.find(here)
	if at >= 0:
		_path = _path.slice(at + 1)
	if _path.is_empty():
		move_smart(world.x, speed_tiles)
		return
	_step_to(here, _path[0], speed_tiles)


## Один переход пути: шаг, спуск, прыжок вверх или через яму.
func _step_to(here: Vector2i, next: Vector2i, speed_tiles: float) -> void:
	var speed := Game.tiles(speed_tiles)
	var dx := (next.x + 0.5) * Game.TILE - global_position.x
	var dir := 0
	if absf(dx) >= 3.0:
		dir = 1 if dx > 0.0 else -1
		set_facing(dir)
	var up := here.y - next.y
	var across := absi(next.x - here.x)
	if up > 0 or across >= 2:
		# Прыжок: высота — чтобы перелететь уступ, скорость — чтобы долететь точно до клетки.
		var height := up + 0.7 if up > 0 else maxf(1.2, 0.8 - up)
		var fall := height - up  # от вершины прыжка до места приземления, клеток
		var air := sqrt(2.0 * Game.tiles(height) / _gravity) + sqrt(2.0 * Game.tiles(maxf(fall, 0.1)) / _gravity)
		velocity = Vector2(dir * maxf(speed * 0.6, absf(dx) / air), -_jump_speed(height))
		_leaping = true
	else:
		velocity.x = dir * speed


## Тактика умного бойца ближнего боя. Сама двигает врага; возвращает true, когда пора бить.
##   * увернуться от снаряда; раненый — убегает или идёт лечиться к яблоку;
##   * не видит игрока — идёт туда, где видел его в последний раз;
##   * игрок за щитом — кружит рядом и ждёт, пока щит опустится;
##   * нападают по двое (право на атаку раздаёт уровень), остальные держат кольцо;
##   * у цели: иногда обманный отскок, чтобы выманить удар, а после промаха игрока — бьёт.
func melee_tactics(delta: float, sight_tiles: float, attack_range_tiles: float, speed_tiles: float) -> bool:
	if try_dodge():
		return false
	var player := get_player()
	if _feint_time > 0.0:
		var away := 1 if global_position.x > player.global_position.x else -1
		move_smart(global_position.x + away * Game.tiles(2.0), speed_tiles * 1.2)
		set_facing(-away)
		return false
	if should_flee() or _wants_healing():
		_retreat_or_heal(speed_tiles)
		return false
	if not update_awareness(sight_tiles, delta):
		_drop_token()
		patrol(speed_tiles * 0.4)
		return false
	if not can_see_player():
		navigate_to(_last_seen, speed_tiles)
		return false
	read_player_aim()
	if player.is_shielding():
		_hold_ring(2.4, speed_tiles)
		return false
	if not _take_token():
		_hold_ring(3.4, speed_tiles)
		return false
	if is_player_in_range(attack_range_tiles) and _attack_cd <= 0.0:
		velocity.x = 0.0
		face_player()
		if _maybe_feint():
			return false
		_feint_decided = false
		return true
	# Подходит (или, пока удар перезаряжается, обходит игрока с фланга).
	navigate_to(Vector2(flank_target_x(attack_range_tiles * 0.6), player.global_position.y), speed_tiles)
	return false


## Держаться на distance_tiles от игрока, покачиваясь вперёд-назад, лицом к нему.
func _hold_ring(distance_tiles: float, speed_tiles: float) -> void:
	var player := get_player()
	var side := 1 if global_position.x > player.global_position.x else -1
	var sway := sin(_ring_phase * 1.7 + float(get_instance_id() % 7)) * 0.7
	navigate_to(Vector2(player.global_position.x + side * Game.tiles(distance_tiles + sway), player.global_position.y), speed_tiles * 0.8)
	if is_on_floor() and absf(velocity.x) < 1.0:
		face_player()


## Обманный отскок: если игрок смотрит на врага и его удар готов, враг иногда отпрыгивает,
## чтобы игрок промахнулся. Решается один раз за подход. После промаха игрок открыт.
func _maybe_feint() -> bool:
	if _feint_decided:
		return false
	_feint_decided = true
	var player := get_player()
	var facing_me := signf(global_position.x - player.global_position.x) == player.facing
	if facing_me and player.melee_ready() and not player.is_vulnerable() and randf() < 0.4:
		_feint_time = 0.45
		return true
	return false


func _take_token() -> bool:
	var lv := level()
	_has_token = lv != null and lv.request_attack_token(self)
	return _has_token


func _drop_token() -> void:
	if _has_token and level():
		level().release_attack_token(self)
	_has_token = false


## Умный враг видит, куда целится игрок: если ствол смотрит на него и игрок только что
## стрелял — уходит с линии огня заранее, не дожидаясь пули.
func read_player_aim() -> void:
	if _preempt_cd > 0.0 or _dodge_cd > 0.0:
		return
	var player := get_player()
	if player.seconds_since_shot() > 0.5:
		return
	var to_me := (get_center() - player.get_muzzle()).normalized()
	if player.aim_direction().angle_to(to_me) > deg_to_rad(12.0) or player.aim_direction().angle_to(to_me) < -deg_to_rad(12.0):
		return
	_preempt_cd = 0.8
	if randf() < effective_dodge_chance():
		_dodge_cd = 1.0
		_dodge(player.aim_direction() * 500.0)


## Шанс уворота с поправкой на стиль игрока: кто много стреляет — от того чаще уворачиваются.
func effective_dodge_chance() -> float:
	if dodge_chance <= 0.0:
		return 0.0
	var lv := level()
	var shooter: float = lv.player_style_share("bullet") + lv.player_style_share("sphere") if lv else 0.0
	return clampf(dodge_chance + 0.35 * shooter, 0.0, 0.9)


## Раненый (меньше половины здоровья) умный враг хочет к яблоку, если оно недалеко.
func _wants_healing() -> bool:
	if not smart or _heal_give_up or health >= max_health * 0.5 or level() == null:
		return false
	var pickup: Node2D = level().nearest_pickup(global_position)
	if pickup == null or pickup.global_position.distance_to(global_position) > Game.tiles(12.0):
		return false
	_heal_time += get_physics_process_delta_time()
	if _heal_time > 6.0:
		_heal_give_up = true  # не дойти до яблока — хватит, дерётся
	return not _heal_give_up


## Отступить к ближайшему яблоку и съесть его, а если яблок нет — просто убегать.
func _retreat_or_heal(speed_tiles: float) -> void:
	var pickup: Node2D = level().nearest_pickup(global_position) if level() else null
	if pickup == null:
		flee(speed_tiles * 1.2)
		return
	if pickup.global_position.distance_to(global_position) < Game.tiles(0.8):
		pickup.call("consume_by_enemy", self)
		_flee_time = 0.0
		return
	navigate_to(pickup.global_position, speed_tiles * 1.2)


## Лечение (враг съел яблоко).
func heal(amount: int) -> void:
	health = mini(health + amount, max_health)
	_on_damaged(0)
	_update_label()


# --- Ловушки: осторожность умных врагов -----------------------------------------------------
# Враг не боится ловушек «по расписанию»: он решает, заметил ли ловушку, и только тогда
# соразмеряет шаг с её движением. Забывчивость — часть характера:
#   * шанс заметить — trap_awareness; в пылу боя (игрок ближе 3 клеток) он вдвое ниже;
#   * решение принимается один раз за «встречу» (ловушка в пределах 5 клеток по ходу
#     движения); отойдя или передумав, враг потом решает заново;
#   * обжёгшийся о ловушку помнит её 10 секунд и замечает наверняка;
#   * если ждать надоело (больше 4 секунд), враг на 2,5 с рискует и идёт напролом.

const TRAP_LOOKAHEAD_TILES := 5.0
## Подойдя к ловушке на столько клеток, враг останавливается, если пройти небезопасно.
const TRAP_STOP_TILES := 2.0
const TRAP_RECHECK := 0.12
const TRAP_PATIENCE := 4.0
const TRAP_RECKLESS_TIME := 2.5
const TRAP_REMEMBER := 10.0
## Боссы ловушек не боятся и ран от них не получают (Boss переопределяет).
func is_trap_immune() -> bool:
	return false

var _trap_notes := {}
var _trap_learned := {}
var _trap_dir := 0.0
var _trap_blocked := false
var _trap_retreat := false
var _trap_check_cd := 0.0
var _trap_wait := 0.0
var _trap_reckless_until := 0.0


## Время врага (сек) — копится по физическим кадрам, а не по часам.
var _brain_clock := 0.0


func _now() -> float:
	return _brain_clock


## Ловушка ранила врага: он её запомнил.
func on_trap_hit(trap: Node) -> void:
	_trap_learned[trap.get_instance_id()] = _now() + TRAP_REMEMBER
	_trap_notes[trap.get_instance_id()] = {"aware": true, "seen": _now()}


## Заметил ли враг эту ловушку (решает один раз за встречу и запоминает решение).
func notices_trap(trap: Node) -> bool:
	var id := trap.get_instance_id()
	var now := _now()
	var note: Dictionary = _trap_notes.get(id, {})
	if note.is_empty() or now - float(note["seen"]) > 2.0:
		var chance := trap_awareness
		if _trap_learned.get(id, 0.0) > now:
			chance = 1.0
		elif _alerted and has_target() and distance_to_player_tiles() < 3.0:
			chance *= 0.5  # увлёкся боем
		note = {"aware": randf() < chance, "seen": now}
	note["seen"] = now
	_trap_notes[id] = note
	return note["aware"]


## Вызывается после решения ИИ о шаге и до движения: если враг заметил ловушку, которая
## зацепит его на этом шаге, он стоит, а если ловушка уже рядом — пятится.
func _apply_trap_caution(delta: float) -> void:
	if not smart or _dead or _leaping or not is_on_floor() or absf(velocity.x) < 1.0 or is_trap_immune():
		_trap_blocked = false
		_trap_wait = 0.0
		return
	if _now() < _trap_reckless_until:
		return
	_trap_check_cd -= delta
	if _trap_check_cd <= 0.0:
		_trap_check_cd = TRAP_RECHECK
		_evaluate_traps()
	if _trap_blocked and signf(velocity.x) == _trap_dir:
		_trap_wait += delta
		velocity.x = -velocity.x * 0.7 if _trap_retreat else 0.0
		if _trap_wait > TRAP_PATIENCE:
			_trap_wait = 0.0
			_trap_blocked = false
			_trap_reckless_until = _now() + TRAP_RECKLESS_TIME
	elif not _trap_blocked:
		_trap_wait = 0.0


func _evaluate_traps() -> void:
	_trap_dir = signf(velocity.x)
	_trap_blocked = false
	_trap_retreat = false
	var speed := absf(velocity.x)
	var body := get_body_rect()
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as Trap
		if not trap.threatens_enemies():
			continue
		var reach := trap.reach_rect()
		if reach.size == Vector2.ZERO:
			continue
		# На одной высоте с врагом и впереди по ходу движения, не дальше TRAP_LOOKAHEAD_TILES.
		if reach.end.y < body.position.y - 8.0 or reach.position.y > body.end.y + 8.0:
			continue
		var gap: float
		if _trap_dir > 0.0:
			gap = reach.position.x - body.end.x
			if reach.end.x < body.position.x:
				continue
		else:
			gap = body.position.x - reach.end.x
			if reach.position.x > body.end.x:
				continue
		if gap > Game.tiles(TRAP_LOOKAHEAD_TILES):
			continue
		if not notices_trap(trap):
			continue
		# Хватит ли времени пройти мимо, пока ловушка не вернулась? Прикидываем шаги вперёд.
		var finish := (reach.end.x + body.size.x) if _trap_dir > 0.0 else (reach.position.x - body.size.x)
		var travel := absf(finish - (body.end.x if _trap_dir > 0.0 else body.position.x))
		var horizon := minf(travel / speed + 0.2, 3.5)
		var t := 0.0
		var unsafe := false
		var imminent := false
		while t <= horizon:
			var moved := body
			moved.position.x += _trap_dir * speed * t
			var zone := trap.zone_at(t)
			if zone.size != Vector2.ZERO and moved.grow(4.0).intersects(zone):
				unsafe = true
				imminent = imminent or t < 0.3
				break
			t += 0.1
		# Издали просто идёт дальше: подойдя на 2 клетки, ещё раз смотрит и тогда ждёт.
		if unsafe and (gap <= Game.tiles(TRAP_STOP_TILES) or imminent):
			_trap_blocked = true
			_trap_retreat = _trap_retreat or imminent
	if not _trap_blocked:
		_trap_wait = 0.0


# --- Помощники для ИИ ---------------------------------------------------------

func get_player() -> Player:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


## Есть ли живой игрок, на которого можно реагировать.
func has_target() -> bool:
	var player := get_player()
	return player != null and not player.is_dead() and not Game.is_game_over


## Центр тела (точка отсчёта самого узла — у ног).
func get_center() -> Vector2:
	return _shape.global_position


func get_body_rect() -> Rect2:
	var size := (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.global_position - size / 2.0, size)


## Расстояние до игрока в клетках (между центрами тел).
func distance_to_player_tiles() -> float:
	return get_center().distance_to(get_player().get_center()) / Game.TILE


## Игрок на дистанции атаки. radius_tiles — дистанция из концепта (в клетках),
## к ней добавляется запас на размеры тел.
func is_player_in_range(radius_tiles: float) -> bool:
	return distance_to_player_tiles() <= radius_tiles + Game.CONTACT_MARGIN


func set_facing(dir: int) -> void:
	if dir == 0 or dir == facing:
		return
	facing = dir
	_body.scale.x = facing


func face_player() -> void:
	set_facing(int(signf(get_player().global_position.x - global_position.x)))


## Идёт по земле к игроку. Упёршись в блок — подпрыгивает (если can_jump_on_blocks).
func walk_towards_player(speed_tiles: float) -> void:
	var dx := get_player().global_position.x - global_position.x
	var dir := 0
	if absf(dx) > Game.tiles(0.5):
		dir = 1 if dx > 0.0 else -1
	velocity.x = dir * Game.tiles(speed_tiles)
	set_facing(dir)

	var blocked := is_on_wall() and get_wall_normal().x * dir < 0.0
	if can_jump_on_blocks and dir != 0 and is_on_floor() and blocked:
		velocity.y = -sqrt(2.0 * _gravity * Game.tiles(block_jump_height_tiles))
