class_name ZombieKing
extends Boss
## Босс «Король зомби» (символ Z). 220 HP (на умной сложности в 1,5 раза больше).
## Мёртвый король в рваном плаще с ржавой короной (тот же художник, что скелет и гоблин).
##   * идёт к игроку и рубит мечом (16) — удары чередуются слева направо;
##   * ПОДНИМАЕТ МЁРТВЫХ (на умной сложности): поднимает меч — и рядом с игроком из земли
##     вылезают могильные зомби (в ярости на одного больше; больше четырёх одновременно нет);
##   * БЬЁТ ПО ЗЕМЛЕ: широкий замах мечом пускает по полу ударную волну (18) в обе стороны —
##     перепрыгни её; в ярости за первой волной идёт вторая;
##   * ТАРАН (умная сложность): дрожит и краснеет (0,7 с — отойди в сторону или встань на
##     платформу), затем несётся через арену и сбивает всё на пути (20).
## На лёгкой сложности стоит на месте, рубит и бьёт по земле реже, мёртвых не поднимает.
## Анимации — assets/frames/zombie_king.tres (кадры из design/source/luizmelo).

enum State { IDLE, WALK, SLASH, SMASH, SUMMON, WINDUP, CHARGE, DEAD }

const GRAVE_ZOMBIE := preload("res://scenes/enemies/grave_zombie.tscn")

@export_group("Король зомби")
@export var walk_speed_tiles := 2.2
@export var slash_range_tiles := 2.3
@export var slash_damage := 16
@export var slash_cooldown := 1.4
@export_subgroup("Удар по земле")
@export var smash_interval := 8.0
@export var smash_damage := 18
@export var smash_radius_tiles := 9.0
@export var smash_speed_tiles := 9.0
@export_subgroup("Мёртвые встают")
@export var summon_interval := 15.0
@export var summon_count := 2
@export var max_minions := 4
@export_subgroup("Таран")
@export var charge_interval := 9.0
@export var charge_windup := 0.7
@export var charge_speed_tiles := 10.0
@export var charge_damage := 20
@export var charge_max_time := 1.5

var _slash_index := 0
var _charge_dir := 1
var _hit_cd := 0.0
var _minions: Array = []


func _ready() -> void:
	super()
	restart_timer("slash", 1.0)
	restart_timer("smash", 4.0)
	restart_timer("summon", 5.0)
	restart_timer("charge", 8.0)


func _boss_ai(delta: float) -> void:
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	match state:
		State.SLASH:
			velocity.x = 0.0
			if _state_time >= 0.5:
				set_state(State.IDLE)
			return
		State.SMASH:
			velocity.x = 0.0
			if _state_time >= 0.9:
				set_state(State.IDLE)
			return
		State.SUMMON:
			velocity.x = 0.0
			if _state_time >= 1.3:
				set_state(State.IDLE)
			return
		State.WINDUP:
			velocity.x = 0.0
			_body.position = Vector2(randf_range(-2.0, 2.0), 0.0)
			if _state_time >= charge_windup:
				_start_charge()
			return
		State.CHARGE:
			_charge_ai()
			return

	face_player()
	var distance := distance_to_player_tiles()
	if is_player_in_range(slash_range_tiles) and timer_ready("slash"):
		restart_timer("slash", slash_cooldown)
		_slash_index += 1
		set_state(State.SLASH)
		queue_action(0.22, strike_player.bind(slash_range_tiles + 0.4, slash_damage))
	elif smart and distance > 4.5 and timer_ready("charge") and is_on_floor():
		restart_timer("charge", charge_interval)
		set_state(State.WINDUP)
	elif timer_ready("smash"):
		restart_timer("smash", smash_interval)
		set_state(State.SMASH)
		queue_action(0.28, _smash)
	elif smart and timer_ready("summon") and _live_minions() < max_minions:
		restart_timer("summon", summon_interval)
		set_state(State.SUMMON)
		queue_action(0.55, _raise_zombies)
	elif smart and distance > slash_range_tiles:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


# --- Удар по земле --------------------------------------------------------------------------

func _smash() -> void:
	_spawn_wave()
	DustPuff.spawn(get_parent(), Vector2(global_position.x + facing * Game.tiles(1.8), global_position.y), 1.8)
	if smart and _enraged:
		get_tree().create_timer(0.55, false).timeout.connect(_spawn_wave)


## Волна идёт по земле в обе стороны и ранит игрока, когда гребень проходит под ним (см. shockwave.gd).
func _spawn_wave() -> void:
	if _dead or not is_inside_tree():
		return
	var wave := Shockwave.new()
	wave.radius = Game.tiles(smash_radius_tiles)
	wave.speed = Game.tiles(smash_speed_tiles)
	wave.damage = smash_damage
	get_parent().add_child(wave)
	wave.global_position = global_position


# --- Мёртвые встают ---------------------------------------------------------------------------

func _live_minions() -> int:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m._dead)
	return _minions.size()


## Могильные зомби вылезают из земли по обе стороны от игрока (но не вплотную к королю).
func _raise_zombies() -> void:
	var count := mini(summon_count + (1 if _enraged else 0), max_minions - _live_minions())
	var player_x := get_player().global_position.x
	for i in count:
		var side := -1 if i % 2 == 0 else 1
		var x := arena_clamp_x(player_x + side * Game.tiles(2.5 + 1.8 * floori(i / 2.0)))
		if absf(x - global_position.x) < Game.tiles(2.0):
			x = arena_clamp_x(global_position.x - side * Game.tiles(3.0))
		var zombie := GRAVE_ZOMBIE.instantiate() as WalkerEnemy
		get_parent().add_child(zombie)
		zombie.global_position = Vector2(x, _home_y - 2.0)
		zombie.set_state(WalkerEnemy.State.WAKE)  # вылезает из земли сразу, не дожидаясь игрока
		DustPuff.spawn(get_parent(), Vector2(x, _home_y), 1.3)
		_minions.append(zombie)


# --- Таран ------------------------------------------------------------------------------------------

func _start_charge() -> void:
	face_player()
	_charge_dir = facing
	_hit_cd = 0.0
	set_state(State.CHARGE)


func _charge_ai() -> void:
	_body.position = Vector2.ZERO
	velocity.x = _charge_dir * Game.tiles(charge_speed_tiles)
	var player := get_player()
	if _hit_cd <= 0.0 and get_body_rect().intersects(player.get_body_rect()):
		_hit_cd = 0.8
		player.take_damage(charge_damage, get_center())
	if _state_time < 0.2:
		return
	var reach := Game.tiles(arena_half_width_tiles)
	var out_of_arena := (_charge_dir < 0 and global_position.x <= _home_x - reach) \
		or (_charge_dir > 0 and global_position.x >= _home_x + reach)
	if is_on_wall() or out_of_arena or _state_time > charge_max_time:
		DustPuff.spawn(get_parent(), Vector2(global_position.x + _charge_dir * Game.tiles(1.5), global_position.y), 1.6)
		set_state(State.IDLE)


# --- Состояния и анимации ---------------------------------------------------------------------

func _enter_state(new_state: int) -> void:
	_body.position = Vector2.ZERO
	if new_state == State.WINDUP:
		_body.modulate = Color(1.5, 0.75, 0.75)
	elif new_state == State.SUMMON:
		_body.modulate = Color(0.8, 1.35, 0.9)
	else:
		_body.modulate = Color(1.0, 0.7, 0.7) if _enraged else Color.WHITE


func _state_names() -> Array:
	return State.keys()


func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK, State.CHARGE:
			return "run"
		State.SLASH:
			return "attack" if _slash_index % 2 == 1 else "attack2"
		State.SMASH:
			return "smash"
		State.SUMMON, State.WINDUP:
			return "summon"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "hit"
