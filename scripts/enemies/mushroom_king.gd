class_name MushroomKing
extends Boss
## Босс «Король-гриб» (символ M). 160 HP.
##   * медленно идёт к игроку;
##   * вблизи бьёт шляпой (15);
##   * издалека бросает веер спор по дуге (по 10, взрыв задевает рядом);
##   * раз в summon_interval секунд призывает грибников.

enum State { IDLE, WALK, SLAM, SPORES, SUMMON, DEAD }

const MINION := preload("res://scenes/enemies/mushroom.tscn")
const SPORE := preload("res://assets/frames/spore.tres")

@export_group("Король-гриб")
@export var walk_speed_tiles := 1.8
@export var slam_range_tiles := 2.0
@export var slam_damage := 15
@export var slam_cooldown := 2.0
@export var spore_interval := 3.5
@export var spore_count := 3
@export var spore_damage := 10
@export var summon_interval := 12.0
@export var summon_count := 2


func _ready() -> void:
	super()
	restart_timer("spores", 2.0)
	restart_timer("summon", summon_interval)


func _boss_ai(_delta: float) -> void:
	match state:
		State.SLAM, State.SPORES, State.SUMMON:
			velocity.x = 0.0
			if _state_time >= 0.65:
				set_state(State.IDLE)
			return

	face_player()
	var distance := distance_to_player_tiles()
	if is_player_in_range(slam_range_tiles) and timer_ready("slam"):
		restart_timer("slam", slam_cooldown)
		set_state(State.SLAM)
		queue_action(0.3, strike_player.bind(slam_range_tiles + 0.4, slam_damage))
	elif timer_ready("summon"):
		restart_timer("summon", summon_interval)
		set_state(State.SUMMON)
		queue_action(0.3, spawn_minions.bind(MINION, summon_count))
	elif timer_ready("spores") and distance > slam_range_tiles + 1.0:
		restart_timer("spores", spore_interval)
		set_state(State.SPORES)
		queue_action(0.35, _throw_spores)
	elif distance > slam_range_tiles:
		set_state(State.WALK)
		boss_walk(walk_speed_tiles)
	else:
		set_state(State.IDLE)
		velocity.x = 0.0


func _throw_spores() -> void:
	var from := get_center() + Vector2(facing * Game.tiles(0.8), -Game.tiles(1.0))
	var player_feet := Vector2(predict_player(0.9).x, get_player().global_position.y)
	for i in spore_count:
		# Веер: споры падают с шагом 1,5 клетки вокруг игрока, по разным дугам.
		var target := player_feet + Vector2((i - (spore_count - 1) / 2.0) * Game.tiles(1.5), -Game.tiles(0.3))
		var flight_time := 0.8 + 0.15 * i
		EnemyProjectile.launch(get_parent(), from, EnemyProjectile.lob_velocity(from, target, flight_time, _gravity), SPORE, {
			"gravity": _gravity,
			"damage": spore_damage,
			"explode_radius": Game.tiles(0.9),
			"scale": 1.6,
			"radius": 9.0,
		})


func _state_names() -> Array:
	return State.keys()


## Анимации (кадры грибника, увеличенные и окрашенные — см. mushroom_king.tscn).
func _state_animation(for_state: int) -> String:
	match for_state:
		State.WALK:
			return "run"
		State.SLAM:
			return "attack"
		State.SPORES:
			return "throw"
		State.SUMMON:
			return "summon"
		State.DEAD:
			return "death"
	return "idle"


func _hurt_animation() -> String:
	return "take_hit"
