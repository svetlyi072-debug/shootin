extends Node
## Окно и подсказки (автозагрузка «Display»).
##   F11 — игра на весь экран без рамки (как F11 в браузере: закрывает панель задач и всё
##         остальное), повторное нажатие возвращает обычное окно;
##   P   — скрыть или показать подсказки с кнопками (строка внизу HUD и в главном меню).
## Выбор подсказок запоминается между запусками (user://settings.cfg), полноэкранный режим
## — нет: игра всегда стартует в окне.
## Работает и на паузе, и в меню (process_mode = Always).

signal hints_changed(visible: bool)

const SETTINGS_PATH := "user://settings.cfg"

## Показаны ли подсказки с кнопками.
var hints_visible := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		hints_visible = config.get_value("ui", "hints_visible", true)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_hints"):
		set_hints_visible(not hints_visible)
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_FULLSCREEN


## Во весь экран без рамки / обратно в окно.
func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


func set_fullscreen(on: bool) -> void:
	# Эксклюзивный режим: окно ровно во весь экран, без рамки и без полоски в 1 px по краю
	# (обычный FULLSCREEN в Godot на Windows оставляет её), панель задач закрыта.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func set_hints_visible(on: bool) -> void:
	if on == hints_visible:
		return
	hints_visible = on
	hints_changed.emit(on)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # не затираем остальные настройки, если появятся
	config.set_value("ui", "hints_visible", on)
	config.save(SETTINGS_PATH)
