extends Node
## Глобальный синглтон (автозагрузка «Game»).
## Хранит общие константы, сигналы, через которые общаются игрок, враги, уровень и HUD,
## и прогресс по уровням (он переживает перезагрузку сцены).

## Размер одной клетки (блока) в пикселях.
## Все скорости и дистанции в концепте заданы в клетках — переводим через tiles().
const TILE := 32.0

## Запас на размеры тел при проверке «дистанции атаки» (в клетках).
## Дистанции меряются между центрами тел, поэтому к радиусу атаки добавляется
## примерно половина ширины тел.
const CONTACT_MARGIN := 0.5

## Показывать над персонажами подписи с текущим состоянием и HP (для отладки).
const SHOW_STATE_LABELS := false

## PageDown / PageUp — перейти на следующий / предыдущий уровень (для проверки уровней).
const DEBUG_LEVEL_KEYS := true

## Список уровней по порядку.
const LEVEL_LIST := preload("res://levels/level_list.gd")

# Шина событий: сигналы испускают одни узлы, слушают другие,
# поэтому внутри этого файла они «не используются» — глушим предупреждение.
@warning_ignore("unused_signal")
signal player_health_changed(current: int, maximum: int)
@warning_ignore("unused_signal")
signal player_power_changed(current: int, maximum: int)
@warning_ignore("unused_signal")
signal player_shield_changed(current: int, maximum: int)
@warning_ignore("unused_signal")
signal player_died
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Node, power_reward: int)
@warning_ignore("unused_signal")
signal boss_activated(boss_name: String, current: int, maximum: int)
@warning_ignore("unused_signal")
signal boss_health_changed(current: int, maximum: int)
@warning_ignore("unused_signal")
signal boss_defeated
@warning_ignore("unused_signal")
signal level_started(number: int, total: int, title: String, require_clear: bool)
@warning_ignore("unused_signal")
signal enemies_left_changed(count: int)
@warning_ignore("unused_signal")
signal hint(text: String)
signal level_completed(next_title: String)
signal game_won
## Уровню включили или выключили условие «победить всех врагов» (Level.require_clear_all, API модов 2).
@warning_ignore("unused_signal")
signal require_clear_changed(on: bool)

## true после смерти игрока, прохождения уровня или победы.
## Уровни сложности:
##   EASY   — у игрока есть щит, враги без ИИ: ходят по своему маршруту и не охотятся;
##   NORMAL — у игрока есть щит, враги умные (см. «Интеллект» в enemy.gd);
##   HARD   — враги умные, щита нет.
enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := ["Лёгкая", "Нормальная", "Сложная"]

const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Здесь запоминается, до какого уровня дошёл игрок (для «Продолжить» в меню).
const SAVE_PATH := "user://progress.cfg"
## Прогресс кампаний модов (по одному разделу на кампанию).
const MOD_SAVE_PATH := "user://mod_progress.cfg"

var difficulty: Difficulty = Difficulty.NORMAL
var is_game_over := false
## Босс, чья полоска здоровья сейчас на экране (боссов на уровне может быть несколько).
var bar_boss: Node = null
## Кампания мода: пока она задана, уровни берутся из неё, а не из встроенного списка.
var campaign_id := ""
var campaign_title := ""
var campaign_levels: Array = []
## Номер текущего уровня (с нуля).
var level_index := 0
## Очки силы, с которыми игрок начинает уровень (переносятся с прошлого уровня).
var carried_power := 0
## Пройдена ли вся игра (после этого R начинает игру заново).
var game_completed := false


func _ready() -> void:
	player_died.connect(_on_player_died)


## Мод включил правило «смерть — конец забега»: сохранение стирается, чтобы нельзя было
## вернуться на уровень, где погиб, кнопкой «Продолжить».
func _on_player_died() -> void:
	if Mods.permadeath_active():
		clear_progress()


## Сбрасывает состояние партии. Вызывается при (пере)запуске главной сцены.
func reset() -> void:
	is_game_over = false


## Переводит клетки в пиксели.
func tiles(amount: float) -> float:
	return amount * TILE


func in_campaign() -> bool:
	return campaign_id != ""


func level_count() -> int:
	return campaign_levels.size() if in_campaign() else LEVEL_LIST.LEVELS.size()


## Данные уровня: словарь констант его файла (TITLE, REQUIRE_CLEAR, MAP).
## index < 0 — текущий уровень.
func level_data(index: int = -1) -> Dictionary:
	if index < 0:
		index = level_index
	if in_campaign():
		return campaign_levels[index]
	var script: GDScript = LEVEL_LIST.LEVELS[index]
	return script.get_script_constant_map()


func is_last_level() -> bool:
	return level_index >= level_count() - 1


## Уровень пройден: запоминаем силу игрока, дальше — следующий уровень или победа.
func complete_level(player_power: int) -> void:
	if is_game_over:
		return
	is_game_over = true
	carried_power = player_power
	if is_last_level():
		game_completed = true
		clear_progress()
		game_won.emit()
	else:
		level_completed.emit(level_data(level_index + 1).get("TITLE", ""))


func go_to_level(index: int) -> void:
	level_index = clampi(index, 0, level_count() - 1)
	# Мод может зафиксировать сложность (ModScript.lock_difficulty) — любой вход на уровень
	# (новая игра, «Продолжить», следующий уровень) проходит через эту функцию.
	var forced := Mods.forced_difficulty()
	if forced >= 0:
		difficulty = clampi(forced, 0, DIFFICULTY_NAMES.size() - 1) as Difficulty
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE)


## Забег заново с первого уровня (встроенной игры или текущей кампании мода) на той же сложности.
## Так начинает игру после смерти хардкорный режим.
func restart_run() -> void:
	if in_campaign():
		start_campaign(campaign_id, campaign_title, campaign_levels, difficulty)
	else:
		start_new_game(difficulty)


func start_new_game(new_difficulty: Difficulty = difficulty) -> void:
	difficulty = new_difficulty
	carried_power = 0
	game_completed = false
	go_to_level(0)


## Запускает кампанию мода с первого уровня (levels — словари из Mods.campaign_levels).
func start_campaign(id: String, title: String, levels: Array, new_difficulty: Difficulty = difficulty) -> void:
	campaign_id = id
	campaign_title = title
	campaign_levels = levels
	start_new_game(new_difficulty)


## Продолжает кампанию мода с сохранённого уровня.
func continue_campaign(id: String, title: String, levels: Array) -> void:
	var saved := saved_campaign(id)
	campaign_id = id
	campaign_title = title
	campaign_levels = levels
	if saved.is_empty() or saved["level_index"] >= levels.size():
		start_new_game()
		return
	difficulty = saved["difficulty"]
	carried_power = saved["carried_power"]
	game_completed = false
	go_to_level(saved["level_index"])


## Возвращает игру к встроенной кампании.
func leave_campaign() -> void:
	campaign_id = ""
	campaign_title = ""
	campaign_levels = []


func go_to_menu() -> void:
	leave_campaign()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Сложность ------------------------------------------------------------------

func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func player_has_shield() -> bool:
	return difficulty != Difficulty.HARD


## Умные враги — на нормальной и сложной сложности.
func smart_enemies() -> bool:
	return difficulty != Difficulty.EASY


# --- Сохранение прогресса -----------------------------------------------------------

## Запоминает начало текущего уровня. Вызывается уровнем при загрузке.
func save_progress() -> void:
	if in_campaign():
		var mod_config := ConfigFile.new()
		mod_config.load(MOD_SAVE_PATH)
		mod_config.set_value(campaign_id, "difficulty", difficulty)
		mod_config.set_value(campaign_id, "level_index", level_index)
		mod_config.set_value(campaign_id, "carried_power", carried_power)
		mod_config.save(MOD_SAVE_PATH)
		return
	var config := ConfigFile.new()
	config.set_value("progress", "difficulty", difficulty)
	config.set_value("progress", "level_index", level_index)
	config.set_value("progress", "carried_power", carried_power)
	config.save(SAVE_PATH)


func clear_progress() -> void:
	if in_campaign():
		var mod_config := ConfigFile.new()
		if mod_config.load(MOD_SAVE_PATH) == OK:
			mod_config.erase_section(campaign_id)
			mod_config.save(MOD_SAVE_PATH)
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Что сохранено: {difficulty, level_index, carried_power} или пустой словарь.
func saved_progress() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}
	var index: int = config.get_value("progress", "level_index", 0)
	if index < 0 or index >= level_count():
		return {}
	return {
		"difficulty": config.get_value("progress", "difficulty", Difficulty.NORMAL),
		"level_index": index,
		"carried_power": config.get_value("progress", "carried_power", 0),
	}


## Сохранение кампании мода: {difficulty, level_index, carried_power} или пустой словарь.
func saved_campaign(id: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(MOD_SAVE_PATH) != OK or not config.has_section(id):
		return {}
	return {
		"difficulty": config.get_value(id, "difficulty", Difficulty.NORMAL),
		"level_index": config.get_value(id, "level_index", 0),
		"carried_power": config.get_value(id, "carried_power", 0),
	}


func continue_game() -> void:
	leave_campaign()
	var saved := saved_progress()
	if saved.is_empty():
		start_new_game()
		return
	difficulty = saved["difficulty"]
	carried_power = saved["carried_power"]
	game_completed = false
	go_to_level(saved["level_index"])
