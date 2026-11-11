class_name Boss
extends Enemy
## Общее для всех боссов:
##   * «спит», пока игрок не подойдёт ближе activation_range_tiles (или не ударит его);
##   * при пробуждении показывает в HUD полоску здоровья с именем;
##   * таймеры атак: restart_timer("имя", сек) / timer_ready("имя");
##   * призыв помощников рядом с собой, в пределах арены;
##   * победа над боссом завершает уровень без выхода (см. level.gd).
## Поведение конкретного босса — в _boss_ai() наследника.
##
## Сложность:
##   * без ИИ (лёгкая) — атакует в 1,6 раза реже, не ходит за игроком (boss_walk стоит
##     на месте), не зовёт помощников, стреляет туда, где игрок сейчас;
##   * умный — стреляет на упреждение (predict_player), а на половине здоровья впадает
##     в ярость: атакует на четверть чаще.

@export_group("Босс")
@export var boss_name := "Босс"
## Босс просыпается, когда игрок ближе этого расстояния (клетки).
@export var activation_range_tiles := 14.0
## Насколько далеко от точки появления (клетки) босс может уходить, прыгать
## и призывать помощников — чтобы не покидал арену.
@export var arena_half_width_tiles := 12.0
## Поводок: босс не уходит от точки появления дальше arena_half_width_tiles. Нужен на огромных
## картах с несколькими боссами (уровень включает его сам, см. BOSS_LEASH в level.gd).
@export var leash_to_arena := false
## Во сколько раз больше здоровья у босса на умной сложности (нормальная и сложная).
## На лёгкой остаётся max_health из сцены.
@export var smart_health_multiplier := 1.0
## При какой доле здоровья умный босс звереет (0,5 — на половине).
@export var enrage_ratio := 0.5

var _active := false
var _home_x := 0.0
var _home_y := 0.0
var _timers := {}
var _block_hint_shown := false
var _enraged := false


func _ready() -> void:
	super()
	if smart and smart_health_multiplier != 1.0:
		max_health = roundi(max_health * smart_health_multiplier)
		health = max_health
		_update_label()
	_home_x = global_position.x
	_home_y = global_position.y


func _update_ai(delta: float) -> void:
	if not _active:
		if distance_to_player_tiles() > activation_range_tiles:
			velocity.x = 0.0
			return
		_activate()
	for timer_name in _timers:
		_timers[timer_name] -= delta
	_boss_ai(delta)
	if leash_to_arena:
		if at_arena_edge(-1) and velocity.x < 0.0:
			velocity.x = 0.0
		elif at_arena_edge(1) and velocity.x > 0.0:
			velocity.x = 0.0


## Босс дошёл до края своей арены в этом направлении (только при включённом поводке).
func at_arena_edge(dir: int) -> bool:
	if not leash_to_arena:
		return false
	var reach := Game.tiles(arena_half_width_tiles)
	return (dir < 0 and global_position.x <= _home_x - reach) or (dir > 0 and global_position.x >= _home_x + reach)


## Поведение босса после пробуждения.
func _boss_ai(_delta: float) -> void:
	pass


func timer_ready(timer_name: String) -> bool:
	return _timers.get(timer_name, 0.0) <= 0.0


func restart_timer(timer_name: String, seconds: float) -> void:
	_timers[timer_name] = seconds * _timer_scale()


## Боссы ловушек не боятся (и они их не ранят).
func is_trap_immune() -> bool:
	return true


## Атаки боссов звучат ниже и громче, чем у обычных врагов.
func _attack_sound() -> String:
	return "boss_attack"


## Во сколько раз растянуть паузы между атаками: лёгкая — реже, ярость — чаще.
func _timer_scale() -> float:
	if not smart:
		return 1.6
	return 0.75 if _enraged else 1.0


## Ходьба босса к игроку: умный обходит препятствия, без ИИ — стоит на месте.
func boss_walk(speed_tiles: float) -> void:
	if smart:
		move_smart(get_player().global_position.x, speed_tiles)
	else:
		velocity.x = 0.0


func is_enraged() -> bool:
	return _enraged


## Босс проснулся (игрок подошёл или ударил его) и ещё жив. По этому признаку включается музыка боя.
func is_awake() -> bool:
	return _active and not _dead


func _activate() -> void:
	if _active:
		return
	_active = true
	_show_bar()


## Полоска здоровья в HUD теперь показывает этого босса.
func _show_bar() -> void:
	Game.bar_boss = self
	Game.boss_activated.emit(boss_name, health, max_health)


func _on_damaged(_amount: int) -> void:
	_activate()
	if Game.bar_boss != self:
		_show_bar()  # на уровне несколько боссов: полоска следует за тем, кого бьют
	else:
		Game.boss_health_changed.emit(health, max_health)
	if smart and not _enraged and health > 0 and health <= max_health * enrage_ratio:
		_enraged = true
		Game.hint.emit("%s в ярости!" % boss_name)
		_body.modulate = Color(1.0, 0.7, 0.7)


## Победа над боссом: уровень без выхода на этом завершается (см. level.gd).
func die() -> void:
	if _dead:
		return
	super()
	if Game.bar_boss == self:
		Game.bar_boss = null
	Game.boss_defeated.emit()


## Ширина карты в пикселях (чтобы падающие сверху снаряды не вылетали за стены).
func map_width_px() -> float:
	var lv := level()
	return float(lv.map_width()) * Game.TILE if lv else _home_x + Game.tiles(arena_half_width_tiles)


## Босс на сквозной платформе, а игрок прямо под ним: спрыгивает вниз (на время отключает
## слой платформ), чтобы не стоять над игроком, до которого не дотянуться.
func drop_through_platform_if_needed() -> void:
	if not is_on_floor() or not get_collision_mask_value(5):
		return
	var player := get_player()
	var below := player.global_position.y - global_position.y
	if below < Game.tiles(1.2) or absf(player.global_position.x - global_position.x) > Game.tiles(3.0):
		return
	set_collision_mask_value(5, false)
	get_tree().create_timer(0.4, false).timeout.connect(_end_platform_drop)


func _end_platform_drop() -> void:
	if is_instance_valid(self) and not _dead:
		set_collision_mask_value(5, true)


func arena_clamp_x(x: float) -> float:
	var reach := Game.tiles(arena_half_width_tiles)
	return clampf(x, _home_x - reach, _home_x + reach)


## Призывает count помощников поочерёдно слева и справа от себя, в пределах арены.
## На лёгкой сложности боссы помощников не зовут.
func spawn_minions(scene: PackedScene, count: int) -> void:
	if not smart:
		return
	var half_width := get_body_rect().size.x / 2.0
	for i in count:
		var side := -1 if i % 2 == 0 else 1
		var distance := half_width + Game.tiles(1.0 + 1.5 * floori(i / 2.0))
		var minion := scene.instantiate() as Node2D
		get_parent().add_child(minion)
		minion.global_position = Vector2(arena_clamp_x(global_position.x + side * distance), _home_y - 2.0)


## Подсказка игроку, показывается один раз за бой (например, «зайди со спины»).
func hint_once(text: String) -> void:
	if not _block_hint_shown:
		_block_hint_shown = true
		Game.hint.emit(text)
