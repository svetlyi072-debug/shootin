class_name ShellbackKing
extends Boss
## Босс «Царь-Панцирь» (символ K). 320 HP (на умной сложности в 1,4 раза больше).
## Гигантский Панцирник с короной из золотых кристаллов.
##   * КАТИТСЯ: дрожит и приседает (WINDUP, 0,9 с — успей забраться на платформу выше
##     трёх клеток: шар проходит под ней), затем катится через всю арену (ROLL, 25 урона
##     при касании) до стены. Пока катится, урона почти не получает;
##   * врезавшись в стену, падает на спину и оглушён на 2,6 с (DIZZY): бей, пока он
##     лежит, урон вдвое больше. На умной сложности от удара о стену с потолка сыплются камни;
##   * ТОПАЕТ (STOMP): встаёт на дыбы, бьёт передними лапами (20 вблизи) и обрушивает с
##     потолка камни (по 15) вокруг игрока; красные метки на полу показывают, куда они упадут.
##     Через раз зовёт Панцирников на помощь (на умной сложности);
##   * на половине здоровья (ярость) катается туда и обратно без передышки.
## На лёгкой сложности боссы стоят на месте, атакуют реже и не зовут помощников.
## Анимации — assets/frames/shellback_king.tres (кадры из design/source).

enum State { IDLE, WALK, WINDUP, ROLL, STOMP, DIZZY, DEAD }

const ROCK_FRAMES := preload("res://assets/frames/shellback_rock.tres")
const PANZERNIK := preload("res://scenes/enemies/panzernik.tscn")

@export_group("Царь-Панцирь")
@export var walk_speed_tiles := 1.6
## Пауза между качениями, сек.
@export var roll_interval := 6.0
@export var windup_time := 0.9
@export var roll_speed_tiles := 11.0
@export var roll_damage := 25
@export var roll_max_time := 5.0
@export var dizzy_time := 2.6
## Во сколько раз меньше урона в шаре (но не меньше 1) и во сколько раз больше — когда лежит оглушённый.
@export var armor_divisor := 3
@export var dizzy_damage_factor := 2.0
@export_subgroup("Топот")
@export var stomp_interval := 7.0
## Ближе этого (клетки) бьёт лапами по игроку вплотную.
@export var stomp_range_tiles := 3.4
@export var stomp_damage := 20
@export var rock_count := 6
@export var rock_damage := 15
## Камни падают в пределах ±rock_spread_tiles от игрока.
@export var rock_spread_tiles := 8.0
## Сколько секунд метка на полу предупреждает, прежде чем камень начнёт падать.
@export var rock_warning_time := 0.6
@export var summon_count := 2

const STANDING_SIZE := Vector2(96.0, 70.0)
const ROLLED_SIZE := Vector2(84.0, 84.0)
const DIZZY_SIZE := Vector2(96.0, 56.0)

var _roll_dir := 1
var _roll_hit_cd := 0.0
var _rolls_left := 0
var _quick_windup := false
var _recovering := false
var _stomp_count := 0


func _ready() -> void:
	super()
	_shape.shape = _shape.shape.duplicate()
	_set_hitbox(STANDING_SIZE)
	restart_timer("roll", 4.0)
	restart_timer("stomp", 2.5)


func _boss_ai(delta: float) -> void:
	_roll_hit_cd = maxf(_roll_hit_cd - delta, 0.0)
	match state:
		State.WINDUP:
			velocity.x = 0.0
			_body.position = Vector2(randf_range(-1.5, 1.5), 0.0)
			if _state_time >= windup_time * (0.5 if _quick_windup else 1.0):
				_start_roll()
			return
		State.ROLL:
			_roll_ai()
			return
		State.STOMP:
			velocity.x = 0.0
			if _state_time >= 1.0:
				set_state(State.IDLE)
			return
		State.DIZZY:
			velocity.x = 0.0
			if not _recovering and _state_time >= dizzy_time - 0.4:
				_recovering = true
				_restart_animation("recover")
			if _state_time >= dizzy_time:
				set_state(State.IDLE)
			return

	face_player()
	if smart and is_player_in_range(stomp_range_tiles) and timer_ready("stomp"):
		_start_stomp()
	elif timer_ready("roll") and is_on_floor():
		restart_timer("roll", roll_interval)
		_rolls_left = 2 if (smart and _enraged) else 1
		_quick_windup = false
		set_state(State.WINDUP)
	elif timer_ready("stomp"):
		_start_stomp()
	elif distance_to_player_tiles() > 5.0:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


# --- Качение ----------------------------------------------------------------------------------

func _start_roll() -> void:
	face_player()
	_roll_dir = facing
	_roll_hit_cd = 0.0
	set_state(State.ROLL)


func _roll_ai() -> void:
	_body.position = Vector2.ZERO
	velocity.x = _roll_dir * Game.tiles(roll_speed_tiles)
	var player := get_player()
	if _roll_hit_cd <= 0.0 and get_body_rect().intersects(player.get_body_rect()):
		_roll_hit_cd = 0.8
		player.take_damage(roll_damage, get_center())
	if _state_time < 0.2:
		return
	if is_on_wall() or at_arena_edge(_roll_dir):
		_crash()
	elif _state_time > roll_max_time:
		set_state(State.IDLE)  # докатился до середины и выдохся


## Врезался в стену: в ярости разворачивается и катится назад, иначе падает на спину.
func _crash() -> void:
	Sound.play("sphere", global_position)
	DustPuff.spawn(get_parent(), Vector2(global_position.x + _roll_dir * Game.tiles(1.8), global_position.y), 2.2)
	_rolls_left -= 1
	if _rolls_left > 0:
		_quick_windup = true
		set_state(State.WINDUP)  # в ярости: сразу назад, без передышки
		return
	hint_once("Царь-Панцирь на спине — бей, пока он не поднялся!")
	if smart:
		_drop_rocks(global_position.x - _roll_dir * Game.tiles(3.0), 3, 3.0)  # от удара трясёт потолок
	set_state(State.DIZZY)


# --- Топот ---------------------------------------------------------------------------------------

func _start_stomp() -> void:
	restart_timer("stomp", stomp_interval)
	_stomp_count += 1
	set_state(State.STOMP)
	queue_action(0.45, _slam)


## Передние лапы бьют о землю: урон вплотную, пыль, камни с потолка; через раз — помощники.
func _slam() -> void:
	DustPuff.spawn(get_parent(), Vector2(global_position.x + facing * Game.tiles(2.0), global_position.y), 2.0)
	strike_player(stomp_range_tiles + 0.4, stomp_damage)
	var count := rock_count + (3 if _enraged else 0) if smart else maxi(roundi(rock_count * 0.5), 2)
	_drop_rocks(predict_player(0.6).x, count, rock_spread_tiles)
	if smart and _stomp_count % 2 == 0:
		spawn_minions(PANZERNIK, summon_count + (1 if _enraged else 0))


## Камни падают с потолка в случайные места рядом с центром centre_x (метки на полу — сразу).
func _drop_rocks(centre_x: float, count: int, spread_tiles: float) -> void:
	var tile := float(Game.TILE)
	var top := maxf(_home_y - Game.tiles(12.0), tile)
	var fall_time := sqrt(2.0 * (_home_y - top) / _gravity)
	var left := tile * 1.5
	var right := map_width_px() - tile * 1.5
	for i in count:
		var x := clampf(centre_x + Game.tiles(randf_range(-spread_tiles, spread_tiles)), left, right)
		var delay := randf_range(0.0, 0.5)
		GroundWarning.spawn(get_parent(), Vector2(x, _home_y), rock_warning_time + delay + fall_time, 20.0)
		get_tree().create_timer(rock_warning_time + delay, false).timeout.connect(_launch_rock.bind(Vector2(x, top)))
		get_tree().create_timer(rock_warning_time + delay + fall_time, false).timeout.connect(_rock_landed.bind(Vector2(x, _home_y)))


func _launch_rock(at: Vector2) -> void:
	if _dead:
		return
	EnemyProjectile.launch(get_parent(), at, Vector2.ZERO, ROCK_FRAMES, {
		"gravity": _gravity,
		"damage": rock_damage,
		"explode_radius": Game.tiles(0.8),
		"scale": 1.6,
		"radius": 9.0,
	})


func _rock_landed(at: Vector2) -> void:
	if is_instance_valid(self) and is_inside_tree():
		DustPuff.spawn(get_parent(), at, 1.4)


# --- Состояния, урон, анимации ------------------------------------------------------------------

func _enter_state(new_state: int) -> void:
	_body.position = Vector2.ZERO
	_body.modulate = Color(1.0, 0.7, 0.7) if _enraged else Color.WHITE
	_recovering = false
	match new_state:
		State.ROLL:
			_set_hitbox(ROLLED_SIZE)
		State.DIZZY:
			_set_hitbox(DIZZY_SIZE)
		_:
			_set_hitbox(STANDING_SIZE)


func _set_hitbox(size: Vector2) -> void:
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = Vector2(0.0, -size.y / 2.0)


## В шаре и пока готовится катиться почти неуязвим, на спине получает вдвое больше урона.
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	var dealt := amount
	if state == State.ROLL or state == State.WINDUP:
		dealt = maxi(roundi(amount / float(armor_divisor)), 1)
		_body.modulate = Color(1.8, 1.8, 1.8)
		get_tree().create_timer(0.08, false).timeout.connect(_restore_color)
	elif state == State.DIZZY:
		dealt = roundi(amount * dizzy_damage_factor)
	super(dealt, source_position)


func _restore_color() -> void:
	if not _dead:
		_body.modulate = Color(1.0, 0.7, 0.7) if _enraged else Color.WHITE


func _state_names() -> Array:
	return State.keys()


## Анимации (assets/frames/shellback_king.tres):
##   IDLE — idle, WALK — walk, WINDUP — windup (приседает, кристаллы сияют),
##   ROLL — roll, STOMP — stomp (на дыбы, удар), DIZZY — dizzy (на спине) и recover (встаёт),
##   DEAD — death (кристаллы лопаются, панцирь раскалывается).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "walk"
		State.WINDUP:
			return "windup"
		State.ROLL:
			return "roll"
		State.STOMP:
			return "stomp"
		State.DIZZY:
			return "dizzy"
		State.DEAD:
			return "death"
	return "idle"


## В шаре, при замахе и на спине не «морщится» от попаданий.
func _hurt_animation() -> String:
	if state == State.ROLL or state == State.WINDUP or state == State.DIZZY or state == State.STOMP:
		return ""
	return "hurt"
