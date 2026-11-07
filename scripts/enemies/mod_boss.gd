class_name ModBoss
extends Boss
## Босс, описанный в JSON (мод): набор атак и несколько чисел, писать код не нужно.
## Фабрика модов (mods.gd) заполняет поля из файла bosses/*.json; формат — в MODDING.md.
##
## Атаки (поле attacks, перебираются по порядку, берётся первая готовая):
##   melee      — удар вблизи (range, damage);
##   projectile — снаряды (count, speed, damage, spread, pattern: aimed | fan | lob | rain);
##   shockwave  — ударная волна по земле (radius, speed, damage);
##   summon     — призыв помощников (enemy: символ врага, count);
##   charge     — таран через арену (speed, damage, max_time).
## У каждой есть interval (пауза, с), windup (замах, с), recover (пауза после), animation,
## min_range / max_range (на каком расстоянии до игрока годится, клетки), smart_only (true —
## только на нормальной и сложной сложности).

enum State { IDLE, WALK, ATTACK, WINDUP, CHARGE, DEAD }

## Ходьба: скорость и на каком расстоянии от игрока босс останавливается (клетки).
var walk_speed_tiles := 2.0
var stop_distance_tiles := 2.0
## Названия анимаций (у каждого мода свои).
var anim_idle := "idle"
var anim_walk := "walk"
var anim_run := "run"
var anim_hurt := "hit"
var anim_death := "death"
## Нормализованные атаки (см. Mods.normalize_attack).
var attacks: Array = []
## Как создать помощника по символу: func(symbol: String) -> Node2D. Задаёт фабрика модов.
var summon_factory := Callable()
## Сколько помощников может быть живыми одновременно.
var max_minions := 4

var _current := {}
var _charge_dir := 1
var _hit_cd := 0.0
var _minions: Array = []


func _ready() -> void:
	super()
	for i in attacks.size():
		var interval := float(attacks[i].get("interval", 4.0))
		restart_timer(_key(i), float(attacks[i].get("first_delay", interval * 0.5)))


func _key(index: int) -> String:
	return "attack%d" % index


func _boss_ai(delta: float) -> void:
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	match state:
		State.ATTACK:
			velocity.x = 0.0
			if _state_time >= _attack_duration(_current):
				set_state(State.IDLE)
			return
		State.WINDUP:
			velocity.x = 0.0
			_body.position = Vector2(randf_range(-2.0, 2.0), 0.0)
			if _state_time >= float(_current.get("windup", 0.6)):
				_start_charge()
			return
		State.CHARGE:
			_charge_ai()
			return

	face_player()
	var distance := distance_to_player_tiles()
	for i in attacks.size():
		var attack: Dictionary = attacks[i]
		if not timer_ready(_key(i)):
			continue
		if attack.get("smart_only", false) and not smart:
			continue
		if distance < float(attack.get("min_range", 0.0)) or distance > float(attack.get("max_range", 999.0)):
			continue
		if attack["type"] == "summon" and (not smart or _live_minions() >= max_minions):
			continue
		if attack["type"] == "charge" and not is_on_floor():
			continue
		_begin(i)
		return
	if smart and distance > stop_distance_tiles:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


## Сколько секунд длится состояние атаки: замах + очередь снарядов + пауза после.
func _attack_duration(attack: Dictionary) -> float:
	var duration := float(attack.get("windup", 0.3)) + float(attack.get("recover", 0.4))
	if attack.get("type", "") == "projectile":
		duration += maxi(_count_for(attack) - 1, 0) * float(attack.get("gap", 0.3))
		if attack.get("pattern", "aimed") == "rain":
			duration += float(attack.get("waves", 2)) * float(attack.get("wave_gap", 1.2))
	return duration


func _begin(index: int) -> void:
	var attack: Dictionary = attacks[index]
	restart_timer(_key(index), float(attack.get("interval", 4.0)))
	_current = attack
	if attack["type"] == "charge":
		set_state(State.WINDUP)
		return
	set_state(State.ATTACK)
	match attack["type"]:
		"melee":
			queue_action(float(attack.get("windup", 0.3)), strike_player.bind(float(attack.get("range", 2.0)) + 0.4, int(attack.get("damage", 10))))
		"projectile":
			_queue_projectiles(attack)
		"shockwave":
			queue_action(float(attack.get("windup", 0.3)), _wave.bind(attack))
		"summon":
			queue_action(float(attack.get("windup", 0.5)), _summon.bind(attack))


func _count_for(attack: Dictionary) -> int:
	var count := int(attack.get("count", 1))
	if smart and _enraged and attack.has("enraged_count"):
		count = int(attack["enraged_count"])
	return 1 if not smart and attack.get("type", "") == "projectile" and attack.get("pattern", "aimed") != "rain" else count


# --- Снаряды ---------------------------------------------------------------------------------------

func _queue_projectiles(attack: Dictionary) -> void:
	var windup := float(attack.get("windup", 0.3))
	var pattern: String = attack.get("pattern", "aimed")
	if pattern == "rain":
		var waves := int(attack.get("waves", 2)) + (1 if smart and _enraged else 0)
		for wave in waves:
			queue_action(windup + wave * float(attack.get("wave_gap", 1.2)), _rain_wave.bind(attack))
		return
	var count := _count_for(attack)
	for k in count:
		queue_action(windup + k * float(attack.get("gap", 0.3)), _shot.bind(attack, k, count))


func _mouth(attack: Dictionary) -> Vector2:
	var mouth = attack.get("mouth", [1.2, -0.8])
	return get_center() + Vector2(facing * Game.tiles(float(mouth[0])), Game.tiles(float(mouth[1])))


func _projectile_options(attack: Dictionary, gravity: float) -> Dictionary:
	return {
		"gravity": gravity,
		"damage": int(attack.get("damage", 10)),
		"explode_radius": Game.tiles(float(attack.get("explode_radius", 0.8))),
		"scale": float(attack.get("scale", 1.0)),
		"radius": float(attack.get("radius", 9.0)),
		"face_velocity": true,
	}


func _projectile_frames(attack: Dictionary) -> SpriteFrames:
	return attack.get("frames") as SpriteFrames


func _shot(attack: Dictionary, index: int, count: int) -> void:
	if _dead or not has_target():
		return
	var from := _mouth(attack)
	var player := get_player()
	var speed := Game.tiles(float(attack.get("speed", 8.0)))
	var pattern: String = attack.get("pattern", "aimed")
	if pattern == "lob":
		var landing := Vector2(arena_clamp_x(predict_player(1.0).x if smart else player.global_position.x), player.global_position.y)
		landing.x += (index - (count - 1) / 2.0) * Game.tiles(float(attack.get("spread_tiles", 1.5)))
		var flight := float(attack.get("flight_time", 1.0))
		EnemyProjectile.launch(get_parent(), from, EnemyProjectile.lob_velocity(from, landing, flight, _gravity), _projectile_frames(attack), _projectile_options(attack, _gravity))
		return
	var flight_time := from.distance_to(player.get_center()) / maxf(speed, 1.0)
	var target := predict_player(flight_time) if smart and pattern == "aimed" else player.get_center()
	var aim := (target - from).normalized()
	if count > 1:
		aim = aim.rotated(deg_to_rad(float(attack.get("spread", 10.0))) * (index - (count - 1) / 2.0))
	EnemyProjectile.launch(get_parent(), from, aim * speed, _projectile_frames(attack), _projectile_options(attack, float(attack.get("gravity", 0.0))))


## Дождь: красные метки на полу, затем шары падают сверху на ±width клеток вокруг игрока.
func _rain_wave(attack: Dictionary) -> void:
	if _dead or not has_target():
		return
	var tile := float(Game.TILE)
	var centre := get_player().global_position.x
	var width := Game.tiles(float(attack.get("width", 8.0)))
	var spacing := Game.tiles(float(attack.get("spacing", 1.8)))
	var gap := centre + Game.tiles(randf_range(2.0, 5.0)) * (1.0 if randf() < 0.5 else -1.0)
	var top := maxf(_home_y - Game.tiles(float(attack.get("height", 12.0))), tile)
	var fall_time := sqrt(2.0 * (_home_y - top) / _gravity)
	var warning := float(attack.get("warning", 0.8))
	var left := tile * 1.2
	var right := map_width_px() - tile * 1.2
	var x := maxf(left, centre - width)
	while x <= minf(right, centre + width):
		if absf(x - gap) >= Game.tiles(float(attack.get("window", 2.5))):
			GroundWarning.spawn(get_parent(), Vector2(x, _home_y), warning + fall_time, 22.0)
			get_tree().create_timer(warning, false).timeout.connect(_drop.bind(attack, Vector2(x, top)))
		x += spacing


func _drop(attack: Dictionary, at: Vector2) -> void:
	if _dead:
		return
	EnemyProjectile.launch(get_parent(), at, Vector2.ZERO, _projectile_frames(attack), _projectile_options(attack, _gravity))


# --- Волна, призыв, таран ---------------------------------------------------------------------

func _wave(attack: Dictionary) -> void:
	if _dead or not is_inside_tree():
		return
	var wave := Shockwave.new()
	wave.radius = Game.tiles(float(attack.get("radius", 8.0)))
	wave.speed = Game.tiles(float(attack.get("speed", 9.0)))
	wave.damage = int(attack.get("damage", 15))
	get_parent().add_child(wave)
	wave.global_position = global_position
	DustPuff.spawn(get_parent(), Vector2(global_position.x + facing * Game.tiles(1.8), global_position.y), 1.8)


func _live_minions() -> int:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m.is_dead())
	return _minions.size()


func _summon(attack: Dictionary) -> void:
	if not smart or not summon_factory.is_valid():
		return
	var count := mini(_count_for(attack), max_minions - _live_minions())
	var player_x := get_player().global_position.x
	var near_player: bool = attack.get("near_player", false)
	for i in count:
		var side := -1 if i % 2 == 0 else 1
		var x: float
		if near_player:
			x = arena_clamp_x(player_x + side * Game.tiles(2.5 + 1.8 * floori(i / 2.0)))
			if absf(x - global_position.x) < Game.tiles(2.0):
				x = arena_clamp_x(global_position.x - side * Game.tiles(3.0))
		else:
			x = arena_clamp_x(global_position.x + side * (get_body_rect().size.x / 2.0 + Game.tiles(1.0 + 1.5 * floori(i / 2.0))))
		var minion = summon_factory.call(str(attack.get("enemy", "")))
		if minion == null:
			return
		get_parent().add_child(minion)
		minion.global_position = Vector2(x, _home_y - 2.0)
		DustPuff.spawn(get_parent(), Vector2(x, _home_y), 1.3)
		if minion is WalkerEnemy and minion.starts_dormant:
			minion.set_state(WalkerEnemy.State.WAKE)  # сразу выбирается из земли
		_minions.append(minion)


func _start_charge() -> void:
	face_player()
	_charge_dir = facing
	_hit_cd = 0.0
	set_state(State.CHARGE)


func _charge_ai() -> void:
	_body.position = Vector2.ZERO
	velocity.x = _charge_dir * Game.tiles(float(_current.get("speed", 10.0)))
	var player := get_player()
	if _hit_cd <= 0.0 and get_body_rect().intersects(player.get_body_rect()):
		_hit_cd = 0.8
		player.take_damage(int(_current.get("damage", 20)), get_center())
	if _state_time < 0.2:
		return
	var reach := Game.tiles(arena_half_width_tiles)
	var out_of_arena := (_charge_dir < 0 and global_position.x <= _home_x - reach) \
		or (_charge_dir > 0 and global_position.x >= _home_x + reach)
	if is_on_wall() or out_of_arena or _state_time > float(_current.get("max_time", 1.5)):
		DustPuff.spawn(get_parent(), Vector2(global_position.x + _charge_dir * Game.tiles(1.5), global_position.y), 1.6)
		set_state(State.IDLE)


# --- Состояния и анимации ---------------------------------------------------------------------

func _enter_state(new_state: int) -> void:
	_body.position = Vector2.ZERO
	if new_state == State.WINDUP:
		_body.modulate = Color(1.5, 0.75, 0.75)
	else:
		_body.modulate = Color(1.0, 0.7, 0.7) if _enraged else Color.WHITE


func _state_names() -> Array:
	return State.keys()


func _state_animation(for_state: int) -> String:
	var wanted := anim_idle
	match for_state:
		State.WALK:
			wanted = anim_walk
		State.CHARGE:
			wanted = _current.get("animation", anim_run)
		State.WINDUP:
			wanted = _current.get("windup_animation", anim_idle)
		State.ATTACK:
			wanted = _current.get("animation", "attack")
		State.DEAD:
			wanted = anim_death
	return _existing(wanted)


func _hurt_animation() -> String:
	return _existing(anim_hurt)


## Название анимации, а если такой нет — idle (мод может не рисовать все анимации).
func _existing(wanted: String) -> String:
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(wanted):
		return wanted
	return anim_idle
