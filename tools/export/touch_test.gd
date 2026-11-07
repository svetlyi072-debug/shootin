extends SceneTree
## Проверка сенсорного управления: в игру подаются искусственные касания, как от пальцев.
##   godot --headless --path D:/shootin --script res://tools/export/touch_test.gd
## Можно запускать и на собранной игре:  ShootIn.exe --headless --script D:/shootin/tools/export/touch_test.gd
## Код выхода 0 — всё хорошо, 1 — есть ошибки. Сохранения игрока возвращаются на место.

var fails := 0
var shots: Array = []  # снаряды, появившиеся в игре: {"kind", "dir"}


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


## Ждём и физический, и обычный кадр: события ввода доставляются в игру между ними.
func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	Input.parse_input_event(event)


func drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	Input.parse_input_event(event)


func _on_node_added(node: Node) -> void:
	var path: String = node.get_script().resource_path if node.get_script() else ""
	if path.ends_with("/bullet.gd"):
		shots.append({"kind": "bullet", "dir": node.direction})
	elif path.ends_with("/energy_sphere.gd"):
		shots.append({"kind": "sphere", "dir": node.direction})


func count(kind: String) -> int:
	var n := 0
	for shot in shots:
		if shot["kind"] == kind:
			n += 1
	return n


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var game = root.get_node("Game")
	var touch_node = root.get_node("Touch")
	_save_user_files()
	root.size = Vector2i(1280, 720)
	await frames(2)
	print("окно: ", root.size, ", видимая область: ", root.get_visible_rect().size)

	# 1. На компьютере сенсорный режим включается касанием и выключается настоящей мышью.
	check(not touch_node.enabled, "на компьютере сенсорный режим по умолчанию выключен")
	touch(9, Vector2(640, 100), true)
	touch(9, Vector2(640, 100), false)
	await frames(2)
	check(touch_node.enabled, "первое касание включило сенсорный режим")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	Input.parse_input_event(emulated)
	await frames(2)
	check(touch_node.enabled, "мышь, эмулированная из касания, режим не выключает")
	var real := InputEventMouseButton.new()
	real.device = 0
	real.button_index = MOUSE_BUTTON_LEFT
	real.pressed = true
	Input.parse_input_event(real)
	await frames(2)
	check(not touch_node.enabled, "настоящая мышь выключила сенсорный режим")
	touch(9, Vector2(640, 100), true)
	touch(9, Vector2(640, 100), false)
	await frames(2)
	check(touch_node.enabled, "касание снова включило его")

	# 2. Уровень.
	game.difficulty = 1
	game.level_index = 0
	change_scene_to_file("res://scenes/main.tscn")
	await frames(40)
	node_added.connect(_on_node_added)
	var player = get_first_node_in_group("player")
	check(player != null and player.is_on_floor(), "уровень загружен, игрок на земле")
	var size: Vector2 = root.get_visible_rect().size
	print("размер экрана игры: ", size)

	# 3. Джойстик: бег вправо и влево.
	var x0: float = player.global_position.x
	touch(0, Vector2(120, 600), true)
	await frames(2)
	drag(0, Vector2(190, 600))
	await frames(25)
	check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_left"), "джойстик вправо = move_right")
	check(player.global_position.x > x0 + 30.0, "игрок бежит вправо (%.0f → %.0f)" % [x0, player.global_position.x])
	drag(0, Vector2(40, 600))
	await frames(3)
	check(Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "джойстик влево = move_left")
	drag(0, Vector2(120, 600))
	await frames(3)
	check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "джойстик в центре — стоим")
	touch(0, Vector2(120, 600), false)
	await frames(20)

	# 4. Прыжок джойстиком (резко вверх) и кнопкой.
	check(player.is_on_floor(), "перед прыжком игрок на земле")
	touch(0, Vector2(120, 600), true)
	await frames(2)
	drag(0, Vector2(120, 530))
	await frames(3)
	check(Input.is_action_pressed("jump"), "джойстик вверх = jump")
	check(player.velocity.y < 0.0 or not player.is_on_floor(), "игрок прыгнул от джойстика")
	touch(0, Vector2(120, 530), false)
	await frames(60)
	check(player.is_on_floor() and not Input.is_action_pressed("jump"), "приземлился, прыжок отпущен")
	var jump_button := Vector2(size.x - 118.0, size.y - 118.0)
	touch(1, jump_button, true)
	await frames(3)
	check(Input.is_action_pressed("jump") and not player.is_on_floor(), "кнопка «Прыжок» подбрасывает игрока")
	touch(1, jump_button, false)
	await frames(60)

	# 5. Тап — пуля в ту точку, куда ткнули; можно стрелять одновременно с бегом (два пальца).
	var before := count("bullet")
	var target := Vector2(size.x * 0.75, size.y * 0.3)
	touch(0, Vector2(120, 600), true)  # палец 1 на джойстике
	touch(2, target, true)  # палец 2 — выстрел
	await frames(2)
	touch(2, target, false)
	await frames(10)
	check(count("bullet") == before + 1, "тап = ровно одна пуля (было %d, стало %d)" % [before, count("bullet")])
	var expected: Vector2 = (player.aim_point() - player.get_muzzle()).normalized()
	var got: Vector2 = shots[shots.size() - 1]["dir"]
	check(got.x > 0.0 and got.y < 0.0, "пуля летит вправо-вверх, как и тап (%s)" % str(got))
	check(got.dot(expected) > 0.97, "направление пули совпадает с направлением на палец")
	touch(0, Vector2(120, 600), false)
	await frames(20)
	before = count("bullet")
	# Тап левее игрока (камера у края уровня, так что игрок не в центре экрана).
	var on_screen: Vector2 = player.get_canvas_transform() * player.get_muzzle()
	var left_tap := Vector2(maxf(on_screen.x - 120.0, 10.0), on_screen.y - 40.0)
	print("игрок на экране: ", on_screen, ", тап: ", left_tap, ", мир x игрока: ", player.global_position.x)
	check(left_tap.x < size.x * 0.32 and left_tap.y > size.y * 0.58, "тап слева лежит в зоне джойстика (игрок прижат камерой к низу уровня)")
	touch(2, left_tap, true)
	await frames(2)
	touch(2, left_tap, false)
	await frames(10)
	check(count("bullet") == before + 1 and shots[shots.size() - 1]["dir"].x < 0.0, "короткий тап в зоне джойстика стреляет влево, а не двигает джойстик")
	check(player.facing == -1, "игрок развернулся к цели")
	check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "тап в зоне джойстика не сдвинул игрока")

	# 6. Зажатый палец без полной шкалы — очередь пуль.
	await frames(30)
	before = count("bullet")
	touch(2, target, true)
	await frames(75)
	touch(2, target, false)
	await frames(5)
	check(count("bullet") - before >= 3, "зажатый палец стреляет очередью (%d пуль за 1,2 с)" % (count("bullet") - before))

	# 7. Полная шкала: короткий тап — пуля, зажим — сфера.
	await frames(30)
	player.add_power(player.max_power)
	await frames(3)
	check(player.power >= player.max_power, "шкала силы заполнена")
	before = count("bullet")
	var spheres := count("sphere")
	touch(2, target, true)
	await frames(8)
	check(count("bullet") == before, "при полной шкале пуля не вылетает, пока палец прижат")
	touch(2, target, false)
	await frames(8)
	check(count("bullet") == before + 1 and count("sphere") == spheres, "короткий тап при полной шкале = обычная пуля")
	check(player.power >= player.max_power, "шкала силы после тапа не потрачена")

	await frames(30)
	var hold_target := Vector2(size.x * 0.8, size.y * 0.55)
	touch(2, hold_target, true)
	await frames(15)
	check(player.state != 4 and count("sphere") == spheres, "через 0,25 с зажатия сфера ещё не вылетела")
	await frames(30)
	check(player.state == 4 or player.state == 5 or count("sphere") > spheres, "через 0,75 с зажатия игрок заряжает сферу")
	await frames(30)
	check(count("sphere") == spheres + 1, "вылетела ровно одна сфера")
	var sphere_dir := Vector2.ZERO
	for shot in shots:
		if shot["kind"] == "sphere":
			sphere_dir = shot["dir"]
	var want: Vector2 = (get_first_node_in_group("player").aim_point() - get_first_node_in_group("player").get_muzzle()).normalized()
	check(sphere_dir.x > 0.5 and absf(sphere_dir.angle_to(want)) < 0.35, "сфера полетела в сторону пальца (%s)" % str(sphere_dir))
	check(player.power == 0, "шкала силы потрачена")
	touch(2, hold_target, false)
	await frames(10)

	# 8. Удар и щит.
	var attack_button := Vector2(size.x - 252.0, size.y - 78.0)
	await frames(60)
	touch(3, attack_button, true)
	await frames(3)
	check(Input.is_action_pressed("attack") and player.state == 3, "кнопка «Удар» бьёт")
	touch(3, attack_button, false)
	await frames(30)
	var shield_button := Vector2(size.x - 92.0, size.y - 252.0)
	touch(3, shield_button, true)
	await frames(5)
	check(player.is_shielding(), "кнопка «Щит» поднимает щит, пока её держат")
	touch(3, shield_button, false)
	await frames(5)
	check(not player.is_shielding(), "щит опущен после отпускания")

	# 9. Пауза и выход после смерти.
	touch(3, Vector2(size.x - 44.0, 108.0), true)
	touch(3, Vector2(size.x - 44.0, 108.0), false)
	await frames(5)
	check(paused, "кнопка паузы ставит игру на паузу")
	paused = false
	current_scene.get_node("HUD")._set_paused(false)
	await frames(5)
	player.kill()
	await frames(5)
	var hud = current_scene.get_node("HUD")
	check(hud._touch_buttons.visible, "после смерти показаны кнопки «Заново» и «В меню»")
	check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("jump"), "после смерти кнопки управления отпущены")

	_restore_user_files()
	print("ИТОГ: %s (%d ошибок)" % ["ВСЁ ХОРОШО" if fails == 0 else "ЕСТЬ ОШИБКИ", fails])
	quit(1 if fails else 0)


const USER_FILES := ["user://progress.cfg", "user://mod_progress.cfg", "user://mods.cfg", "user://settings.cfg"]
var _backup := {}


func _save_user_files() -> void:
	for path in USER_FILES:
		_backup[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func _restore_user_files() -> void:
	for path in USER_FILES:
		var data = _backup.get(path)
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(data)
			file.close()
