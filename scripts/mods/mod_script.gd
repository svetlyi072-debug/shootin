class_name ModScript
extends Node
## Основа скриптов модов: скрипт мода начинается со строки «extends ModScript» (без class_name!).
## Переопределите нужные хуки (названия начинаются с «_») и пользуйтесь помощниками ниже.
## Это обычный узел: _process() и _physics_process() тоже работают. Полное описание — MODDING.md.
##
##   extends ModScript
##
##   func _enemy_killed(enemy, power_reward):
##       hint("Убит враг! +%d" % power_reward)

## Мод, которому принадлежит скрипт (id, title, files, …). Заполняется игрой.
var mod: ModInfo


# --- Хуки: вызываются игрой, переопределите нужные ---------------------------------------------

## Мод подключён (один раз при запуске игры или включении мода).
func _mod_ready() -> void:
	pass


## Уровень собран, игрок и враги уже на местах.
func _level_started(_level: Node) -> void:
	pass


## Уровень пройден (или выиграна вся игра).
func _level_completed() -> void:
	pass


## Появился враг или босс (в том числе встроенный); symbol — символ на карте, у призванных пусто.
func _enemy_spawned(_enemy: Node, _symbol: String) -> void:
	pass


func _enemy_killed(_enemy: Node, _power_reward: int) -> void:
	pass


func _boss_defeated() -> void:
	pass


func _player_spawned(_player: Node) -> void:
	pass


func _player_died() -> void:
	pass


# --- Помощники ---------------------------------------------------------------------------------

## Игрок на текущем уровне (null в меню).
func get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


## Узел текущего уровня (null в меню). У него есть nav, map_width(), map_height(), title и т. д.
func get_level() -> Node:
	return get_tree().get_first_node_in_group("level")


## Ставит врага/босса по символу карты (свой или встроенный) в клетку (tile_x, tile_y):
## персонаж встаёт на нижний край клетки. Возвращает узел или null.
func spawn(symbol: String, tile_x: float, tile_y: float) -> Node2D:
	var level := get_level()
	if level == null:
		return null
	var node := Mods.create_any(symbol, mod.id)
	if node == null:
		return null
	node.position = Vector2((tile_x + 0.5) * Game.TILE, (tile_y + 1.0) * Game.TILE)
	level.get_node("Entities").add_child(node)
	return node


## Сообщение игроку вверху экрана.
func hint(text: String) -> void:
	Game.hint.emit(text)


## Читает файл мода как текст (путь относительно папки мода).
func read_text(rel: String) -> String:
	return mod.files.read_text(rel)


func load_texture(rel: String) -> Texture2D:
	return mod.files.load_texture(rel)


func load_audio(rel: String) -> AudioStream:
	return mod.files.load_audio(rel)


## Собирает SpriteFrames из описания (тот же формат, что "sprite" в JSON врага — см. MODDING.md).
func load_frames(spec: Dictionary) -> SpriteFrames:
	var problems: Array = []
	var frames := ModSprites.build_frames(mod, spec, problems)
	for problem in problems:
		log_message(problem)
	return frames


## Добавляет свой символ карты: factory() должна вернуть Node2D (например, врага из своей сцены).
func register_symbol(symbol: String, factory: Callable) -> bool:
	return Mods.register_script_symbol(mod, symbol, factory)


## Сохраняет данные мода (словарь с числами, строками, списками) — переживёт перезапуск игры.
func save_data(data: Dictionary) -> void:
	Mods.save_mod_data(mod, data)


func load_data() -> Dictionary:
	return Mods.load_mod_data(mod)


## Строка в журнал игры (вывод консоли) с пометкой мода.
func log_message(text: String) -> void:
	print("[мод %s] %s" % [mod.id, text])
