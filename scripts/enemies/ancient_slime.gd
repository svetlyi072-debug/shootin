class_name AncientSlime
extends Boss
## Босс «Древний слизень». 200 HP (значения базовых параметров — в ancient_slime.tscn).
## По таймерам: прыжок на игрока раз в jump_interval секунд (приземление на игрока — 25,
## ударная волна по земле — 20) и призыв слизняков раз в summon_interval секунд.

enum State { IDLE, PREPARE, JUMP, LAND, SUMMON, DEAD }

const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")

@export_group("Древний слизень")
@export_subgroup("Прыжок")
@export var jump_interval := 4.0
## За сколько секунд до прыжка пульсация ускоряется (состояние PREPARE).
@export var prepare_time := 1.0
@export var jump_height_tiles := 4.0
## Урон, если босс приземлился прямо на игрока.
@export var land_on_player_damage := 25
## Ударная волна по земле при приземлении.
@export var shockwave_radius_tiles := 10.0
@export var shockwave_damage := 20
## Скорость гребня волны, клеток/с (10 клеток при 25 — за 0,4 с).
@export var shockwave_speed_tiles := 25.0
## Сколько длится приземление (состояние LAND), сек.
@export var land_time := 0.4

@export_subgroup("Призыв")
@export var summon_interval := 10.0
@export var summon_count := 3
## Сколько длится призыв (состояние SUMMON), сек.
@export var summon_time := 0.6


func _ready() -> void:
	super()
	restart_timer("jump", jump_interval)
	restart_timer("summon", summon_interval)


func _boss_ai(_delta: float) -> void:
	# Таймеры тикают всегда (в Boss), а срабатывают, только когда босс свободен.
	match state:
		State.JUMP:
			if _state_time > 0.1 and is_on_floor():
				_land()
			return
		State.LAND:
			velocity.x = 0.0
			if _state_time >= land_time:
				set_state(State.IDLE)
			return
		State.SUMMON:
			if _state_time >= summon_time:
				set_state(State.IDLE)
			return

	# IDLE / PREPARE: стоим между атаками.
	velocity.x = 0.0
	face_player()
	if timer_ready("summon"):
		_summon()
	elif timer_ready("jump"):
		_jump_at_player()
	elif _timers["jump"] <= prepare_time:
		set_state(State.PREPARE)
	else:
		set_state(State.IDLE)


# --- Прыжок и приземление -----------------------------------------------------

func _jump_at_player() -> void:
	restart_timer("jump", jump_interval)
	var target_x := arena_clamp_x(predict_player(1.0).x)
	# Баллистика: подбираем горизонтальную скорость так, чтобы приземлиться в target_x.
	var jump_speed := sqrt(2.0 * _gravity * Game.tiles(jump_height_tiles))
	var flight_time := 2.0 * jump_speed / _gravity
	velocity = Vector2((target_x - global_position.x) / flight_time, -jump_speed)
	set_state(State.JUMP)


func _land() -> void:
	velocity.x = 0.0
	set_state(State.LAND)
	var player := get_player()
	var landed_on_player := get_body_rect().grow(4.0).intersects(player.get_body_rect())
	if landed_on_player:
		player.take_damage(land_on_player_damage, get_center())
	_spawn_shockwave(landed_on_player)


## Волна идёт по земле и ранит игрока, когда гребень проходит под ним (см. shockwave.gd).
func _spawn_shockwave(spare_player: bool) -> void:
	var wave := Shockwave.new()
	wave.radius = Game.tiles(shockwave_radius_tiles)
	wave.speed = Game.tiles(shockwave_speed_tiles)
	wave.damage = shockwave_damage
	wave.spare_player = spare_player
	get_parent().add_child(wave)
	wave.global_position = global_position


# --- Призыв -------------------------------------------------------------------

func _summon() -> void:
	restart_timer("summon", summon_interval)
	set_state(State.SUMMON)
	spawn_minions(SLIME_SCENE, summon_count)


func _state_names() -> Array:
	return State.keys()


## Анимации (те же кадры слизняка, увеличенные и перекрашенные — см. ancient_slime.tscn):
##   IDLE    — idle медленно: медленное пульсирование
##   PREPARE — idle быстро: пульсирует быстрее перед прыжком
##   JUMP    — attack: прыжок на игрока
##   LAND    — hurt: шлепок при приземлении (ударная волна — отдельный узел Shockwave)
##   SUMMON  — attack: призыв слизняков
##   DEAD    — die: разваливается
func _state_animation(for_state: int) -> String:
	match for_state:
		State.JUMP, State.SUMMON:
			return "attack"
		State.LAND:
			return "hurt"
		State.DEAD:
			return "die"
	return "idle"


func _animation_speed(for_state: int) -> float:
	match for_state:
		State.IDLE:
			return 0.6
		State.PREPARE:
			return 2.2
	return 1.0


func _hurt_animation() -> String:
	return "hurt"
