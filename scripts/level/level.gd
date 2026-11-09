extends Node2D
## Уровень, собранный из текстовой карты. Карты лежат в res://levels/level_XX.gd,
## порядок уровней — в res://levels/level_list.gd.
##
## Легенда (каждый символ — одна клетка):
##   #  твёрдый блок                 -  сквозная платформа (можно запрыгнуть снизу)
##   ^  шипы                         +  аптечка
##   Ловушки (scripts/traps/, касание ранит Шуткина):
##   o  пила (ездит по полу ±2,5 клетки)     *  шипастый шар на цепи (ставь под потолком)
##   f  огненная ловушка: твёрдый блок в полу, над ним вспыхивает пламя
##   T  батут (подбрасывает на 5 клеток; не ранит)
##   E  выход                        P  игрок «Шуткин»
##   s  слизняк    b  летучая мышь    k  скелет
##   g  гоблин (бросает бомбы)        m  грибник
##   r  крыса      c  мимик (притворяется сундуком)    p  панцирник (катится шаром)
##   z  зомби      y  могильный зомби (лежит в земле, пока не подойдёшь)   x  зомби-рыцарь
##   Боссы: M  Король-гриб    N  Костяной рыцарь    O  Око бездны
##          W  Огненный червь V  Тёмный колдун      B  Древний слизень
##          K  Царь-Панцирь  Z  Король зомби
##   .  пусто
## Персонажи и предметы появляются у нижнего края своей клетки (стоят на блоке под ней).
## По краям карты стоят невидимые стены, падение ниже карты — смерть.
## Строки могут быть разной длины — недостающие клетки считаются пустыми.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SPAWNS := {
	"s": preload("res://scenes/enemies/slime.tscn"),
	"b": preload("res://scenes/enemies/bat.tscn"),
	"k": preload("res://scenes/enemies/skeleton.tscn"),
	"g": preload("res://scenes/enemies/goblin.tscn"),
	"m": preload("res://scenes/enemies/mushroom.tscn"),
	"r": preload("res://scenes/enemies/rat.tscn"),
	"c": preload("res://scenes/enemies/mimic.tscn"),
	"p": preload("res://scenes/enemies/panzernik.tscn"),
	"z": preload("res://scenes/enemies/zombie.tscn"),
	"y": preload("res://scenes/enemies/grave_zombie.tscn"),
	"x": preload("res://scenes/enemies/zombie_knight.tscn"),
	"M": preload("res://scenes/enemies/mushroom_king.tscn"),
	"N": preload("res://scenes/enemies/bone_knight.tscn"),
	"O": preload("res://scenes/enemies/abyss_eye.tscn"),
	"W": preload("res://scenes/enemies/fire_worm.tscn"),
	"V": preload("res://scenes/enemies/dark_wizard.tscn"),
	"B": preload("res://scenes/enemies/ancient_slime.tscn"),
	"K": preload("res://scenes/enemies/shellback_king.tscn"),
	"Z": preload("res://scenes/enemies/zombie_king.tscn"),
	"o": preload("res://scenes/traps/saw.tscn"),
	"*": preload("res://scenes/traps/spiked_ball.tscn"),
	"f": preload("res://scenes/traps/fire_trap.tscn"),
	"T": preload("res://scenes/traps/trampoline.tscn"),
	"+": preload("res://scenes/level/health_pickup.tscn"),
	"E": preload("res://scenes/level/exit_door.tscn"),
}

## Урон от шипов и сила, с которой они подбрасывают игрока (клетки).
const SPIKE_DAMAGE := 20
const SPIKE_BOUNCE_TILES := 1.5
## Шипы ранят не чаще, чем раз в столько секунд.
const SPIKE_COOLDOWN := 0.5
## Толщина сквозной платформы, px.
const PLATFORM_THICKNESS := 8.0
## Пауза между «Уровень пройден!» и загрузкой следующего, сек.
const NEXT_LEVEL_DELAY := 2.0

const TERRAIN_TEXTURE := preload("res://assets/pixel_adventure/terrain.png")
const SPIKES_TEXTURE := preload("res://assets/pixel_adventure/spikes.png")
const PLATFORM_TEXTURE := preload("res://assets/pixel_adventure/platform.png")
const BACKGROUNDS_DIR := "res://assets/pixel_adventure/backgrounds/"
## Размер тайла в terrain.png (на экране он рисуется в клетку Game.TILE).
const TERRAIN_TILE := 16

## Темы оформления (константа THEME в файле уровня):
##   terrain    — левый верхний угол сетки 3×3 тайлов материала в terrain.png (в пикселях);
##   background — фон из assets/pixel_adventure/backgrounds/.
const THEMES := {
	"grass": {"terrain": Vector2i(96, 0), "background": "blue"},
	"meadow": {"terrain": Vector2i(96, 0), "background": "green"},
	"clay": {"terrain": Vector2i(96, 64), "background": "yellow"},
	"candy": {"terrain": Vector2i(96, 128), "background": "pink"},
	"stone": {"terrain": Vector2i(0, 0), "background": "gray"},
	"crypt": {"terrain": Vector2i(0, 0), "background": "purple"},
	"wood": {"terrain": Vector2i(0, 64), "background": "brown"},
	"jade": {"terrain": Vector2i(0, 128), "background": "green"},
	"brick": {"terrain": Vector2i(272, 64), "background": "purple"},
}
const DEFAULT_THEME := "grass"
## Ширина куска отрисовки (колонок карты), см. level_chunk.gd.
const CHUNK_COLUMNS := 16

var title := ""
## Огромные уровни с несколькими боссами (необязательные константы файла уровня):
##   WIN_BOSS   — символ босса, победа над которым завершает уровень (иначе — любой босс);
##   BOSS_LEASH — true: боссы не уходят дальше своей арены (BOSS_ARENA — полуширина арены
##                в клетках по символу босса, например {"N": 22});
##   ZONES      — оформление по зонам: [[с какой колонки, тема], ...], темы как в THEMES.
var win_boss: Boss = null
var _win_symbol := ""
## Какому моду принадлежит уровень ("" — встроенный): его символы врагов берутся первыми.
var _mod_id := ""
var _boss_leash := false
var _boss_arena := {}
var _zones: Array = []
var _zone_looks: Array = []
## Выход открывается только когда на уровне не осталось врагов.
var require_clear := false
## Победа над главным боссом засчитывается, только когда убиты и все остальные враги
## (включается require_clear_all — например, модом «Хардкорный режим» на финальном уровне).
var win_requires_clear := false
## Главный босс побеждён, но уровень ещё не завершён (ждём остальных врагов).
var _boss_win_pending := false
var theme_name := DEFAULT_THEME

var _terrain_origin := Vector2i.ZERO
var _background: Texture2D
var _solid_set := {}
var _platform_set := {}
var _spike_set := {}
var _solid_cells: Array[Vector2i] = []
var _platform_cells: Array[Vector2i] = []
var _spike_cells: Array[Vector2i] = []
## Клетки, разложенные по кускам отрисовки: номер куска → клетки.
var _chunk_solid := {}
var _chunk_platform := {}
var _chunk_spike := {}
var _exits: Array[ExitDoor] = []
var _map_size := Vector2i.ZERO
var _player: Player
var _spike_cd := 0.0

## Граф проходимости для умных врагов (см. scripts/ai/nav_grid.gd).
var nav: NavGrid

# --- Общий «мозг» стаи (умные враги) ---
## Сколько врагов одновременно может нападать вплотную; остальные кружат и ждут очереди.
const ATTACK_TOKENS := 2
## Сколько секунд враг держит право на атаку, и сколько потом ждёт следующего раза.
const TOKEN_HOLD := 3.5
const TOKEN_REST := 1.5
var _ai_time := 0.0
var _tokens := {}
var _token_rest := {}
## Кто недавно просил право на атаку (время запроса).
var _contenders := {}
## Чем игрок атакует (затухающие счётчики): умные враги подстраиваются.
var _player_style := {"bullet": 0.0, "melee": 0.0, "sphere": 0.0}
var _enemies_left := -1

@onready var _blocks: StaticBody2D = $Blocks
@onready var _platforms: StaticBody2D = $Platforms
@onready var _spikes: Area2D = $Spikes
@onready var _entities: Node2D = $Entities


func _ready() -> void:
	add_to_group("level")
	var data := Game.level_data()
	title = data.get("TITLE", "")
	require_clear = data.get("REQUIRE_CLEAR", false)
	_apply_theme(data.get("THEME", DEFAULT_THEME))
	_win_symbol = data.get("WIN_BOSS", "")
	_mod_id = data.get("MOD_ID", "")
	_boss_leash = data.get("BOSS_LEASH", false)
	_boss_arena = data.get("BOSS_ARENA", {})
	_zones = data.get("ZONES", [])
	_build_zone_looks()
	_build(data.get("MAP", []))
	_add_side_walls()
	_make_chunks()
	nav = NavGrid.new(self, _map_size.y)

	if _player:
		_player.set_camera_limits(Rect2(Vector2.ZERO, Vector2(_map_size) * Game.TILE))
		_player.add_power(Game.carried_power)
	else:
		push_error("На карте нет игрока (символ P).")

	Sound.set_music_override(Mods.level_music(data))
	Game.boss_defeated.connect(_on_boss_defeated)
	Game.level_completed.connect(_on_level_completed)
	_announce.call_deferred()
	if _player:
		Mods.notify_player_spawned(_player)
	Mods.notify_level_started.call_deferred(self)
	Game.save_progress()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_spike_cd = maxf(_spike_cd - delta, 0.0)
	_ai_time += delta
	for kind in _player_style:
		_player_style[kind] *= exp(-delta / 20.0)  # память о стиле игрока ~20 с
	_check_fall()
	_check_spikes()
	_update_enemy_count()
	_check_exits()


# --- Построение уровня --------------------------------------------------------

func _build(map: Array) -> void:
	for y in map.size():
		var row: String = map[y]
		_map_size.x = maxi(_map_size.x, row.length())
		var solid_start := -1
		var platform_start := -1
		# Идём на одну клетку дальше конца строки, чтобы закрыть последние ряды блоков.
		for x in row.length() + 1:
			var cell: String = row[x] if x < row.length() else "."

			# «f» — основание огненной ловушки: для столкновений и ИИ это такой же блок,
			# но рисует его сама ловушка.
			if cell == "#" or cell == "f":
				if cell == "#":
					_solid_cells.append(Vector2i(x, y))
					_bucket(_chunk_solid, Vector2i(x, y))
				_solid_set[Vector2i(x, y)] = true
				if solid_start < 0:
					solid_start = x
			elif solid_start >= 0:
				_add_block_run(solid_start, x - 1, y)
				solid_start = -1

			if cell == "-":
				_platform_cells.append(Vector2i(x, y))
				_bucket(_chunk_platform, Vector2i(x, y))
				_platform_set[Vector2i(x, y)] = true
				if platform_start < 0:
					platform_start = x
			elif platform_start >= 0:
				_add_platform_run(platform_start, x - 1, y)
				platform_start = -1

			if cell == "^":
				_add_spike(x, y)
			elif cell == "P":
				_player = _spawn(PLAYER_SCENE, x, y) as Player
			elif SPAWNS.has(cell):
				_place(_spawn(SPAWNS[cell], x, y), cell)
			elif Mods.has_symbol(cell, _mod_id):
				var custom := Mods.create_entity(cell, _mod_id)
				if custom:
					_place(_spawn_node(custom, x, y), cell)
	_map_size.y = map.size()


## Один горизонтальный ряд блоков = одна коллизия (меньше фигур и нет «стыков» на полу).
func _add_block_run(x_from: int, x_to: int, y: int) -> void:
	var size := Vector2((x_to - x_from + 1) * Game.TILE, Game.TILE)
	var center := Vector2((x_from + x_to + 1) * 0.5 * Game.TILE, (y + 0.5) * Game.TILE)
	_add_rect(_blocks, center, size, false)


## Сквозная платформа: тонкая полоса по верху клетки, пропускает снизу.
func _add_platform_run(x_from: int, x_to: int, y: int) -> void:
	var size := Vector2((x_to - x_from + 1) * Game.TILE, PLATFORM_THICKNESS)
	var center := Vector2((x_from + x_to + 1) * 0.5 * Game.TILE, y * Game.TILE + PLATFORM_THICKNESS / 2.0)
	_add_rect(_platforms, center, size, true)


## Шипы занимают нижнюю половину клетки.
func _add_spike(x: int, y: int) -> void:
	_spike_cells.append(Vector2i(x, y))
	_bucket(_chunk_spike, Vector2i(x, y))
	_spike_set[Vector2i(x, y)] = true
	var size := Vector2(Game.TILE - 8.0, Game.TILE / 2.0)
	_add_rect(_spikes, Vector2((x + 0.5) * Game.TILE, (y + 0.75) * Game.TILE), size, false)


## Невидимые стены слева и справа, чтобы нельзя было уйти за край карты.
func _add_side_walls() -> void:
	var height := (_map_size.y + 20) * Game.TILE
	var center_y := _map_size.y * Game.TILE / 2.0
	_add_rect(_blocks, Vector2(-Game.TILE / 2.0, center_y), Vector2(Game.TILE, height), false)
	_add_rect(_blocks, Vector2((_map_size.x + 0.5) * Game.TILE, center_y), Vector2(Game.TILE, height), false)


func _add_rect(parent: CollisionObject2D, center: Vector2, size: Vector2, one_way: bool) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = center
	collision.one_way_collision = one_way
	parent.add_child(collision)


func _spawn(scene: PackedScene, x: int, y: int) -> Node2D:
	return _spawn_node(scene.instantiate() as Node2D, x, y)


func _spawn_node(node: Node2D, x: int, y: int) -> Node2D:
	# Позицию ставим до add_child, чтобы в _ready() она уже была правильной.
	node.position = Vector2((x + 0.5) * Game.TILE, (y + 1) * Game.TILE)
	_entities.add_child(node)
	return node


## Что делать с только что поставленным на карту узлом: выход, босс, враг (для скриптов модов).
func _place(spawned: Node2D, symbol: String) -> void:
	if spawned is ExitDoor:
		var door := spawned as ExitDoor
		_exits.append(door)
		door.player_touched.connect(_on_exit_touched.bind(door))
	elif spawned is Boss:
		_setup_boss(spawned as Boss, symbol)
	if spawned is Enemy:
		Mods.notify_enemy_spawned(spawned, symbol)


# --- Ход уровня ---------------------------------------------------------------

func _announce() -> void:
	Game.level_started.emit(Game.level_index + 1, Game.level_count(), title, require_clear)
	_update_enemy_count()


## Падение ниже карты: игрок погибает, враги исчезают.
func _check_fall() -> void:
	var fall_limit := (_map_size.y + 2) * Game.TILE
	if is_instance_valid(_player) and not _player.is_dead() and _player.global_position.y > fall_limit:
		_player.kill()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy.global_position.y > fall_limit:
			enemy.die()


func _check_spikes() -> void:
	if _spike_cd > 0.0 or not is_instance_valid(_player) or _player.is_dead():
		return
	if _spikes.get_overlapping_bodies().has(_player):
		_spike_cd = SPIKE_COOLDOWN
		_player.take_damage(SPIKE_DAMAGE, _player.global_position)
		var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
		_player.velocity.y = -sqrt(2.0 * gravity * Game.tiles(SPIKE_BOUNCE_TILES))


func _update_enemy_count() -> void:
	var count := get_tree().get_nodes_in_group("enemies").size()
	if count == _enemies_left:
		return
	_enemies_left = count
	Game.enemies_left_changed.emit(count)
	for door in _exits:
		door.locked = require_clear and count > 0
	_check_boss_win()


func _check_exits() -> void:
	if Game.is_game_over or not is_instance_valid(_player) or _player.is_dead():
		return
	for door in _exits:
		if not door.locked and door.get_overlapping_bodies().has(_player):
			door.celebrate()
			Game.complete_level(_player.power)
			return


func _on_exit_touched(door: ExitDoor) -> void:
	if door.locked:
		Game.hint.emit("Выход закрыт: победи всех врагов (осталось %d)" % _enemies_left)


## На уровне без выхода победа над боссом завершает уровень (а если задан WIN_BOSS —
## победа над этим боссом; остальные на таком уровне необязательные).
func _on_boss_defeated() -> void:
	if _win_symbol == "" and _exits.is_empty():
		_boss_win_pending = true
		_check_boss_win()


func _on_win_boss_died(_boss: Enemy) -> void:
	_boss_win_pending = true
	if win_requires_clear:
		var left := get_tree().get_nodes_in_group("enemies").size()
		if left > 0:
			Game.hint.emit("Главный босс повержен! Чтобы закончить, добей остальных врагов (осталось %d)" % left)
	_check_boss_win()


## Завершает уровень победой над главным боссом — сразу или, если нужно убить всех, когда врагов не осталось.
func _check_boss_win() -> void:
	if not _boss_win_pending or Game.is_game_over:
		return
	if win_requires_clear and not get_tree().get_nodes_in_group("enemies").is_empty():
		return
	if is_instance_valid(_player) and not _player.is_dead():
		Game.complete_level(_player.power)


## Для скриптов модов (API 2): включает условие «победить всех врагов» — выходы закрыты, пока враги
## есть, а победа над главным боссом (WIN_BOSS или единственный босс без выхода) засчитывается, только когда
## не остался ни один враг. HUD показывает счётчик «Врагов осталось».
func require_clear_all(on: bool = true) -> void:
	require_clear = on
	win_requires_clear = on
	_enemies_left = -1
	_update_enemy_count()
	Game.require_clear_changed.emit(on)


## Настройки босса на огромной карте: поводок, ширина арены, главный босс.
func _setup_boss(boss: Boss, symbol: String) -> void:
	if _boss_leash:
		boss.leash_to_arena = true
	if _boss_arena.has(symbol):
		boss.arena_half_width_tiles = float(_boss_arena[symbol])
	if symbol == _win_symbol:
		win_boss = boss
		boss.died.connect(_on_win_boss_died)


func _on_level_completed(_next_title: String) -> void:
	get_tree().create_timer(NEXT_LEVEL_DELAY).timeout.connect(_go_to_next_level)


func _go_to_next_level() -> void:
	Game.go_to_level(Game.level_index + 1)


# --- Отрисовка ------------------------------------------------------------------

func _apply_theme(requested: String) -> void:
	theme_name = requested if THEMES.has(requested) else DEFAULT_THEME
	if theme_name != requested:
		push_warning("Неизвестная тема «%s», беру «%s». Доступны: %s" % [requested, theme_name, ", ".join(THEMES.keys())])
	var look: Dictionary = THEMES[theme_name]
	_terrain_origin = look["terrain"]
	_background = load(BACKGROUNDS_DIR + look["background"] + ".png")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # фон рисуется плиткой


# --- Стая: право на атаку и стиль игрока -------------------------------------------

## Враг просит право напасть вплотную. Одновременно — не больше ATTACK_TOKENS врагов;
## подержав право TOKEN_HOLD секунд, враг уступает очередь другим.
func request_attack_token(enemy: Node) -> bool:
	var id := enemy.get_instance_id()
	for holder in _tokens.keys():
		if not is_instance_valid(instance_from_id(holder)) or _tokens[holder] < _ai_time:
			_tokens.erase(holder)
			_token_rest[holder] = _ai_time + TOKEN_REST
	_contenders[id] = _ai_time
	if _tokens.has(id):
		return true
	var crowd := 0
	for other in _contenders.keys():
		if _contenders[other] > _ai_time - 0.5 and is_instance_valid(instance_from_id(other)):
			crowd += 1
		elif _contenders[other] <= _ai_time - 0.5:
			_contenders.erase(other)
	if crowd <= ATTACK_TOKENS:
		_tokens[id] = _ai_time + TOKEN_HOLD  # нападающих мало — очередь не нужна
		return true
	if _token_rest.get(id, 0.0) > _ai_time or _tokens.size() >= ATTACK_TOKENS:
		return false
	_tokens[id] = _ai_time + TOKEN_HOLD
	return true


func release_attack_token(enemy: Node) -> void:
	var id := enemy.get_instance_id()
	if _tokens.erase(id):
		_token_rest[id] = _ai_time + TOKEN_REST


func note_player_attack(kind: String) -> void:
	_player_style[kind] = _player_style.get(kind, 0.0) + 1.0


## Доля атак данного вида среди недавних (0..1).
func player_style_share(kind: String) -> float:
	var total := 0.0
	for k in _player_style:
		total += _player_style[k]
	return _player_style.get(kind, 0.0) / total if total > 0.5 else 0.0


## Ближайшая аптечка к точке (или null).
func nearest_pickup(world: Vector2) -> Node2D:
	var best: Node2D = null
	for node in get_tree().get_nodes_in_group("health_pickups"):
		var pickup := node as Node2D
		if best == null or pickup.global_position.distance_to(world) < best.global_position.distance_to(world):
			best = pickup
	return best


# --- Вопросы о рельефе (для ИИ врагов) ----------------------------------------------

## Клетка по точке мира.
func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / Game.TILE), floori(world.y / Game.TILE))


## Твёрдый блок (за левым/правым краем — невидимая стена, ниже карты — пустота).
func is_solid_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= _map_size.x:
		return true
	return _solid_set.has(cell)


## На этой клетке можно стоять сверху (блок или сквозная платформа).
func is_floor_cell(cell: Vector2i) -> bool:
	return is_solid_cell(cell) or _platform_set.has(cell)


func is_spike_cell(cell: Vector2i) -> bool:
	return _spike_set.has(cell)


func map_height() -> int:
	return _map_size.y


func map_width() -> int:
	return _map_size.x


## За краем карты считаем, что блоки продолжаются — так стены и пол не получают лишних кромок.
func _is_solid(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _map_size.x or cell.y >= _map_size.y:
		return true
	return _solid_set.has(cell)


## Оформление зон: с какой колонки, терраин и фон. Без ZONES — одна зона на всю карту.
func _build_zone_looks() -> void:
	_zone_looks.clear()
	if _zones.is_empty():
		_zone_looks.append({"from": 0, "terrain": _terrain_origin, "background": _background})
		return
	for zone in _zones:
		var zone_theme: String = zone[1]
		if not THEMES.has(zone_theme):
			push_warning("Неизвестная тема зоны «%s»" % zone_theme)
			zone_theme = DEFAULT_THEME
		var look: Dictionary = THEMES[zone_theme]
		_zone_looks.append({"from": int(zone[0]), "terrain": look["terrain"], "background": load(BACKGROUNDS_DIR + look["background"] + ".png")})


## Номер зоны оформления для колонки карты.
func _zone_index(column: int) -> int:
	var found := 0
	for i in _zone_looks.size():
		if column >= _zone_looks[i]["from"]:
			found = i
	return found


func _bucket(buckets: Dictionary, cell: Vector2i) -> void:
	var chunk := cell.x / CHUNK_COLUMNS
	if not buckets.has(chunk):
		buckets[chunk] = []
	buckets[chunk].append(cell)


func _make_chunks() -> void:
	var count := (_map_size.x + CHUNK_COLUMNS - 1) / CHUNK_COLUMNS
	for i in count:
		var chunk := LevelChunk.new()
		chunk.level = self
		chunk.first_column = i * CHUNK_COLUMNS
		chunk.last_column = mini((i + 1) * CHUNK_COLUMNS, _map_size.x) - 1
		add_child(chunk)
		move_child(chunk, i)  # куски рисуются под персонажами и ловушками


func _draw() -> void:
	# Фон: плитка 64×64 из набора, увеличенная вдвое; у каждой зоны свой.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
	for i in _zone_looks.size():
		var from_x: float = _zone_looks[i]["from"] * Game.TILE / 2.0
		var to_x: float = (_zone_looks[i + 1]["from"] if i + 1 < _zone_looks.size() else _map_size.x) * Game.TILE / 2.0
		draw_texture_rect(_zone_looks[i]["background"], Rect2(Vector2(from_x, 0.0), Vector2(to_x - from_x, _map_size.y * Game.TILE / 2.0)), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Рисует блоки, платформы и шипы одного куска карты (вызывается из LevelChunk._draw).
func paint_chunk(canvas: CanvasItem, first_column: int, _last_column: int) -> void:
	var index := first_column / CHUNK_COLUMNS
	for cell in _chunk_solid.get(index, []):
		_draw_block(canvas, cell)
	for cell in _chunk_platform.get(index, []):
		canvas.draw_texture_rect(PLATFORM_TEXTURE, Rect2(Vector2(cell) * Game.TILE, Vector2(Game.TILE, PLATFORM_THICKNESS)), false)
	for cell in _chunk_spike.get(index, []):
		canvas.draw_texture_rect(SPIKES_TEXTURE, Rect2(Vector2(cell) * Game.TILE, Vector2.ONE * Game.TILE), false)


## Блок собирается из четырёх четвертинок тайлов сетки 3×3 материала: для каждой
## четвертинки смотрим, есть ли сосед сверху/снизу и слева/справа. Так правильно
## выглядят и полы, и стены, и одиночные столбы.
func _draw_block(canvas: CanvasItem, cell: Vector2i) -> void:
	var open_up := not _is_solid(cell + Vector2i.UP)
	var open_down := not _is_solid(cell + Vector2i.DOWN)
	var open_left := not _is_solid(cell + Vector2i.LEFT)
	var open_right := not _is_solid(cell + Vector2i.RIGHT)
	var origin: Vector2i = _zone_looks[_zone_index(cell.x)]["terrain"]
	var half_src := TERRAIN_TILE * 0.5
	var half_dst := Game.TILE / 2.0
	var base := Vector2(cell) * Game.TILE
	for qy in 2:
		for qx in 2:
			var vertical_open := open_up if qy == 0 else open_down
			var horizontal_open := open_left if qx == 0 else open_right
			var col := (0 if qx == 0 else 2) if horizontal_open else 1
			var row := (0 if qy == 0 else 2) if vertical_open else 1
			var src := Rect2(
				origin.x + col * TERRAIN_TILE + qx * half_src,
				origin.y + row * TERRAIN_TILE + qy * half_src,
				half_src, half_src)
			var dst := Rect2(base + Vector2(qx, qy) * half_dst, Vector2.ONE * half_dst)
			canvas.draw_texture_rect_region(TERRAIN_TEXTURE, dst, src)
