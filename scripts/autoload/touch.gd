extends CanvasLayer
## Сенсорное управление для телефонов и планшетов (автозагрузка «Touch»).
##
##   Нижняя левая часть экрана — джойстик: влево-вправо — бег, резко вверх — прыжок.
##   Тап в любое другое место — выстрел в ту точку, куда ткнули. Палец можно не отпускать:
##   пули полетят очередью.
##   Когда шкала силы полна, зажми палец на месте цели: вокруг пальца заполнится кольцо,
##   и в эту сторону вылетит заряженная сфера. Короткий тап при полной шкале — обычная пуля.
##   Справа внизу кнопки «Прыжок», «Удар» и (если есть щит) «Щит», справа вверху — пауза.
##
## Касания превращаются в обычные действия Input (move_left, jump, attack, shield), так что
## игрок, враги и моды про сенсорный экран ничего не знают. Только прицел игрок спрашивает
## у Touch: aim_screen — точка на экране, в которую ткнули пальцем.
##
## Включается сам: на телефонах и планшетах (Android, iOS, браузер с «грубым» указателем) —
## всегда, на компьютере — при первом касании экрана и выключается, если взялись за мышь или
## клавиатуру. Для проверки в обычном браузере: адрес игры с ?touch=1.
## Работает и на паузе (process_mode = Always): так он убирает кнопки, пока открыто меню.

signal enabled_changed(on: bool)

## Что игроку делать с выстрелом в этот кадр (poll_shot).
const SHOT_NONE := 0
const SHOT_BULLET := 1
const SHOT_SPHERE := 2

## Сколько надо держать палец при полной шкале силы, чтобы вылетела сфера, мс.
const HOLD_MS := 350
## Сколько мс «запомненный» тап ждёт, пока кончится перезарядка выстрела.
const TAP_LATCH_MS := 250

const STICK_RADIUS := 84.0
const KNOB_RADIUS := 36.0
## Отступ центра джойстика от левого нижнего угла.
const STICK_HOME := Vector2(150.0, 140.0)
## Касание левее и ниже этих долей экрана берёт джойстик (центр джойстика — где коснулись).
const STICK_ZONE_X := 0.32
const STICK_ZONE_Y := 0.58
## Отклонение, с которого джойстик считается нажатым (доля радиуса).
const MOVE_DEADZONE := 0.3
## Прыжок джойстиком: отклонён не меньше чем на столько и направлен достаточно вверх.
const JUMP_MIN_LENGTH := 0.6
const JUMP_MIN_UP := 0.72
## Касание в зоне джойстика короче этого времени и без сдвига дальше этого — тап-выстрел.
const STICK_TAP_MS := 250
const STICK_TAP_TRAVEL := 20.0
## Запас вокруг кнопок для попадания пальцем, пиксели.
const BUTTON_PAD := 12.0

## Сенсорное управление включено.
var enabled := false
## Точка экрана (в координатах окна игры), куда последний раз ткнули для выстрела.
var aim_screen := Vector2.ZERO

var _mobile := false
var _overlay: Control
var _shown := false
## Какие действия сейчас нажаты нами (чтобы не нажимать повторно каждый кадр).
var _applied := {}
## Какие кнопки зажаты: имя → true.
var _held := {}
## Палец (номер касания) → его роль: "stick", "aim" или имя кнопки.
var _fingers := {}
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _stick_active := false
## Откуда и когда начали водить пальцем по джойстику (короткий тап без движения — это выстрел).
var _stick_start_ms := 0
var _stick_start_pos := Vector2.ZERO
var _stick_travel := 0.0
var _has_aim := false
var _aim_down := false
var _down_ms := 0
var _full_start_ms := -1
var _sphere_used := false
var _tap_ms := -1
var _release_tap_ms := -1
var _power_full := false
var _marker := Vector2.ZERO
var _marker_ms := -1000000
var _portrait := false
var _portrait_paused := false
var _fullscreen_asked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_mobile = _detect_mobile()
	set_enabled(_mobile)


func _detect_mobile() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	if OS.has_feature("web"):
		# ?touch=1 / ?touch=0 — включить или выключить принудительно (удобно для проверки).
		var forced = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('touch')", true)
		if forced == "1":
			return true
		if forced == "0":
			return false
		var coarse = JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches || (navigator.maxTouchPoints > 0 && !window.matchMedia('(any-pointer: fine)').matches)", true)
		return bool(coarse)
	return false


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	_release_all()
	# На телефонах экран вытянутый (20:9 и шире): вместо чёрных полос показываем больше мира.
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if on else Window.CONTENT_SCALE_ASPECT_KEEP
	enabled_changed.emit(on)


func has_aim() -> bool:
	return _has_aim


## Игрок спрашивает раз в кадр, пока может стрелять: что делать с выстрелом.
## power_full — шкала силы полна. Пулю игрок выпускает, когда кончилась перезарядка,
## и сообщает об этом через bullet_done().
func poll_shot(power_full: bool) -> int:
	_power_full = power_full
	var now := Time.get_ticks_msec()
	if power_full:
		if _aim_down:
			if _full_start_ms < 0:
				_full_start_ms = now
			if not _sphere_used and now - _full_start_ms >= HOLD_MS:
				_sphere_used = true
				_tap_ms = -1
				return SHOT_SPHERE
			return SHOT_NONE  # ждём: это либо тап (пуля при отпускании), либо зажим (сфера)
		_full_start_ms = -1
		_sphere_used = false
		if _release_tap_ms >= 0 and now - _release_tap_ms < TAP_LATCH_MS:
			return SHOT_BULLET
		return SHOT_NONE
	_full_start_ms = -1
	_sphere_used = false
	_release_tap_ms = -1
	if _aim_down or (_tap_ms >= 0 and now - _tap_ms < TAP_LATCH_MS):
		return SHOT_BULLET
	return SHOT_NONE


## Игрок выстрелил пулей: запомненный тап израсходован.
func bullet_done() -> void:
	_tap_ms = -1
	_release_tap_ms = -1


# --- Касания ------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _mobile:
		_adapt_to_device(event)
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


## На компьютере: коснулись экрана — включаем кнопки, взялись за мышь или клавиатуру — убираем.
## Мышь, эмулированная из касания, от настоящей отличается номером устройства.
func _adapt_to_device(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		set_enabled(true)
	elif enabled and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton or event is InputEventMouseMotion \
				or (event is InputEventKey and event.pressed):
			set_enabled(false)


func _on_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed or event.canceled:
		_ask_fullscreen_once()
	if not _gameplay_active():
		return
	if event.pressed:
		if _fingers.has(event.index):
			return
		var role := _role_at(event.position)
		if role == "":
			return
		_fingers[event.index] = role
		match role:
			"stick":
				_stick_active = true
				_stick_origin = _clamp_to_screen(event.position)
				_stick_vec = Vector2.ZERO
				_stick_start_ms = Time.get_ticks_msec()
				_stick_start_pos = event.position
				_stick_travel = 0.0
			"aim":
				_begin_aim(event.position)
			"pause":
				_held["pause"] = true
			_:
				_held[role] = true
	else:
		var role: String = _fingers.get(event.index, "")
		_fingers.erase(event.index)
		match role:
			"stick":
				_stick_active = false
				_stick_vec = Vector2.ZERO
				# Короткий тап без движения в зоне джойстика — это выстрел: у игрока, прижатого камерой
				# к низу уровня, именно здесь стоят и он сам, и враги рядом с ним.
				if not event.canceled and Time.get_ticks_msec() - _stick_start_ms < STICK_TAP_MS \
						and _stick_travel < STICK_TAP_TRAVEL:
					_tap_shot(_stick_start_pos)
			"aim":
				_end_aim()
			"pause":
				_held.erase("pause")
				var button: Array = _buttons()["pause"]
				if not event.canceled and event.position.distance_to(button[0]) <= button[1] + BUTTON_PAD:
					_press_ui_cancel()
			"":
				pass
			_:
				_held.erase(role)
	_sync_actions()


func _on_drag(event: InputEventScreenDrag) -> void:
	match _fingers.get(event.index, ""):
		"stick":
			_move_stick(event.position)
			_sync_actions()
		"aim":
			aim_screen = event.position


func _role_at(pos: Vector2) -> String:
	var buttons := _buttons()
	for button_name in buttons:
		var button: Array = buttons[button_name]
		if pos.distance_to(button[0]) <= button[1] + BUTTON_PAD:
			return button_name
	var size := _view_size()
	if not _fingers.values().has("stick") and pos.x < size.x * STICK_ZONE_X and pos.y > size.y * STICK_ZONE_Y:
		return "stick"
	if not _fingers.values().has("aim"):
		return "aim"
	return ""


## Центр и радиус каждой кнопки (в координатах окна игры).
func _buttons() -> Dictionary:
	var size := _view_size()
	var buttons := {
		"jump": [Vector2(size.x - 118.0, size.y - 118.0), 64.0],
		"attack": [Vector2(size.x - 252.0, size.y - 78.0), 46.0],
		"pause": [Vector2(size.x - 44.0, 108.0), 26.0],
	}
	if Game.player_has_shield():
		buttons["shield"] = [Vector2(size.x - 92.0, size.y - 252.0), 46.0]
	return buttons


func _begin_aim(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	aim_screen = pos
	_has_aim = true
	_aim_down = true
	_down_ms = now
	_marker = pos
	_marker_ms = now
	if not _power_full:
		_tap_ms = now  # выстрел сразу, не дожидаясь очередного опроса игрока


## Выстрел одним коротким касанием (палец уже поднят).
func _tap_shot(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	aim_screen = pos
	_has_aim = true
	_marker = pos
	_marker_ms = now
	if _power_full:
		_release_tap_ms = now
	else:
		_tap_ms = now


func _end_aim() -> void:
	var now := Time.get_ticks_msec()
	_aim_down = false
	var since := now - (_full_start_ms if _full_start_ms >= 0 else _down_ms)
	if _power_full and not _sphere_used and since < HOLD_MS:
		_release_tap_ms = now  # короткий тап при полной шкале — обычная пуля, когда палец отпустили
	_full_start_ms = -1


## Джойстик: если палец ушёл дальше радиуса, центр едет за ним, чтобы не «выбираться» назад.
func _move_stick(pos: Vector2) -> void:
	_stick_travel = maxf(_stick_travel, pos.distance_to(_stick_start_pos))
	var offset := pos - _stick_origin
	var dist := offset.length()
	if dist > STICK_RADIUS:
		_stick_origin += offset / dist * (dist - STICK_RADIUS)
		offset = pos - _stick_origin
	_stick_vec = offset / STICK_RADIUS


func _clamp_to_screen(pos: Vector2) -> Vector2:
	var size := _view_size()
	var margin := STICK_RADIUS + 8.0
	return Vector2(clampf(pos.x, margin, size.x - margin), clampf(pos.y, margin, size.y - margin))


## Превращает состояние джойстика и кнопок в действия Input (нажимает и отпускает только при смене).
func _sync_actions() -> void:
	var length := _stick_vec.length()
	var stick_jump := length >= JUMP_MIN_LENGTH and -_stick_vec.y / length >= JUMP_MIN_UP
	var want := {
		"move_left": _stick_vec.x <= -MOVE_DEADZONE,
		"move_right": _stick_vec.x >= MOVE_DEADZONE,
		"jump": _held.has("jump") or stick_jump,
		"attack": _held.has("attack"),
		"shield": _held.has("shield"),
	}
	for action in want:
		var on: bool = want[action]
		if on == _applied.get(action, false):
			continue
		_applied[action] = on
		if on:
			Input.action_press(action)
		else:
			Input.action_release(action)


func _release_all() -> void:
	_fingers.clear()
	_held.clear()
	_stick_active = false
	_stick_vec = Vector2.ZERO
	_aim_down = false
	_full_start_ms = -1
	_sphere_used = false
	_tap_ms = -1
	_release_tap_ms = -1
	_sync_actions()


func _press_ui_cancel() -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"ui_cancel"
		event.pressed = pressed
		Input.parse_input_event(event)


## В браузере на телефоне после первого касания просим полноэкранный режим и горизонтальную ориентацию.
func _ask_fullscreen_once() -> void:
	if _fullscreen_asked or not _mobile or not OS.has_feature("web"):
		return
	_fullscreen_asked = true
	JavaScriptBridge.eval("(function () { var e = document.documentElement; if (!e.requestFullscreen) return; e.requestFullscreen().then(function () { if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function () {}); }).catch(function () {}); })()")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:  # кнопка «назад» на Android = Esc
			_press_ui_cancel()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_release_all()


# --- Состояние экрана -----------------------------------------------------------------

func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Сейчас идёт уровень (а не меню).
func _in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == Game.MAIN_SCENE


func _gameplay_active() -> bool:
	return enabled and _in_game() and not get_tree().paused and not Game.is_game_over and not _portrait


func _process(_delta: float) -> void:
	if not enabled:
		if _shown:
			_shown = false
			_overlay.queue_redraw()
		return
	_check_portrait()
	var active := _gameplay_active()
	if active != _shown:
		_shown = active
		if not active:
			_release_all()
	_overlay.queue_redraw()


## Телефон держат вертикально: игра на паузе, пока его не повернут.
func _check_portrait() -> void:
	var size := _view_size()
	var block := size.y > size.x * 1.02 and _in_game()
	if block and not _portrait:
		_portrait = true
		if not get_tree().paused:
			get_tree().paused = true
			_portrait_paused = true
	elif not block and _portrait:
		_portrait = false
		if _portrait_paused:
			get_tree().paused = false
			_portrait_paused = false


# --- Рисование -------------------------------------------------------------------------

func _draw_overlay() -> void:
	var o := _overlay
	var size := _view_size()
	if _portrait:
		o.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.1, 0.96))
		var font := o.get_theme_default_font()
		o.draw_string(font, Vector2(0.0, size.y * 0.45), "Поверни устройство горизонтально", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color.WHITE)
		return
	if not _shown:
		return

	# Джойстик.
	var center := _stick_origin if _stick_active else Vector2(STICK_HOME.x, size.y - STICK_HOME.y)
	var vec := _stick_vec if _stick_active else Vector2.ZERO
	o.draw_circle(center, STICK_RADIUS, Color(1, 1, 1, 0.10))
	o.draw_arc(center, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.38 if _stick_active else 0.22), 3.0)
	o.draw_circle(center + vec * STICK_RADIUS, KNOB_RADIUS, Color(1, 1, 1, 0.5 if _stick_active else 0.25))

	# Кнопки.
	var buttons := _buttons()
	for button_name in buttons:
		var button: Array = buttons[button_name]
		_draw_button(button_name, button[0], button[1], _held.has(button_name))

	# След последнего тапа и кольцо заряда сферы.
	var now := Time.get_ticks_msec()
	var age := now - _marker_ms
	if age < 300:
		var t := age / 300.0
		o.draw_arc(_marker, 14.0 + 26.0 * t, 0.0, TAU, 32, Color(1, 1, 1, 0.6 * (1.0 - t)), 3.0)
	if _aim_down:
		o.draw_circle(aim_screen, 10.0, Color(1, 1, 1, 0.25))
		if _power_full and _full_start_ms >= 0 and not _sphere_used:
			var progress := clampf((now - _full_start_ms) / float(HOLD_MS), 0.0, 1.0)
			o.draw_arc(aim_screen, 40.0, 0.0, TAU, 48, Color(0.45, 0.85, 1.0, 0.3), 6.0)
			o.draw_arc(aim_screen, 40.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, Color(0.45, 0.85, 1.0, 0.95), 6.0)


func _draw_button(button_name: String, c: Vector2, r: float, pressed: bool) -> void:
	var o := _overlay
	o.draw_circle(c, r, Color(1, 1, 1, 0.30 if pressed else 0.13))
	o.draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55 if pressed else 0.35), 3.0)
	var ink := Color(1, 1, 1, 0.9 if pressed else 0.7)
	match button_name:
		"jump":  # две стрелки вверх
			for dy in [-8.0, 12.0]:
				o.draw_polyline(PackedVector2Array([c + Vector2(-20, dy + 8), c + Vector2(0, dy - 10), c + Vector2(20, dy + 8)]), ink, 6.0)
		"attack":  # меч
			o.draw_line(c + Vector2(-16, 16), c + Vector2(15, -15), ink, 6.0)
			o.draw_line(c + Vector2(-14, -6), c + Vector2(6, 14), ink, 5.0)
		"shield":
			o.draw_polyline(PackedVector2Array([c + Vector2(-17, -17), c + Vector2(17, -17), c + Vector2(17, 2), c + Vector2(0, 21), c + Vector2(-17, 2), c + Vector2(-17, -17)]), ink, 5.0)
		"pause":
			o.draw_rect(Rect2(c + Vector2(-9, -10), Vector2(6, 20)), ink)
			o.draw_rect(Rect2(c + Vector2(3, -10), Vector2(6, 20)), ink)
