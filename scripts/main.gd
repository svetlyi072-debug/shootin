extends Node2D
## Корневая сцена: уровень + HUD. Отвечает за перезапуск и (для отладки) переключение уровней.


func _enter_tree() -> void:
	# Синглтон Game переживает перезагрузку сцены — сбрасываем его до создания уровня.
	Game.reset()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		if Game.game_completed:
			Game.start_new_game()
		else:
			get_tree().reload_current_scene()
		return

	var key := event as InputEventKey
	if Game.DEBUG_LEVEL_KEYS and key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_PAGEDOWN:
				Game.go_to_level(Game.level_index + 1)
			KEY_PAGEUP:
				Game.go_to_level(Game.level_index - 1)
