extends Control
## Экран «Моды»: список найденных модов с галочками, описание выбранного, запуск его кампании,
## установка нового мода из файла или по ссылке и кнопка «Открыть папку модов».
## Весь интерфейс строится кодом (сцена mods_menu.tscn — только корневой узел).

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const BACKGROUND := "res://assets/pixel_adventure/backgrounds/purple.png"
const MAX_DOWNLOAD_BYTES := 100 * 1024 * 1024

var _selected_id := ""
var _pending_consent := ""
var _list: VBoxContainer
var _detail_title: Label
var _detail_meta: Label
var _detail_text: Label
var _detail_content: Label
var _detail_problems: Label
var _settings_box: VBoxContainer
var _play_button: Button
var _continue_button: Button
var _difficulty_row: HBoxContainer
var _status: Label
var _url_edit: LineEdit
var _download_button: Button
var _consent_dialog: ConfirmationDialog
var _file_dialog: FileDialog
var _http: HTTPRequest
var _web_callback: JavaScriptObject  # держим ссылку, иначе браузерный вызов потеряется


func _ready() -> void:
	get_tree().paused = false
	_build_ui()
	Mods.rescan()
	_refresh()
	if not Mods.mods.is_empty():
		_select(Mods.mods[0].id)


# --- Построение интерфейса ----------------------------------------------------------------

func _build_ui() -> void:
	var background := TextureRect.new()
	background.texture = load(BACKGROUND)
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _label("Моды", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	column.add_child(title)
	if _is_web():
		column.add_child(_label("Моды хранятся в браузере (на этом сайте): установите .zip кнопками внизу.", 14))
	elif _is_phone_app():
		column.add_child(_label("Моды хранятся в памяти игры: установите .zip из файла или по ссылке кнопками внизу.", 14))
	else:
		column.add_child(_label("Моды лежат в папке:  %s" % Mods.user_mods_dir(), 14))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)

	# Левая часть: список модов.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	body.add_child(left)
	left.add_child(_label("Установленные моды (галочка — включить)", 18))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	# Правая часть: описание выбранного мода.
	# Правая часть прокручивается: у мода могут быть настройки, и на низком экране всё не поместится.
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right)
	_detail_title = _label("", 28)
	right.add_child(_detail_title)
	_detail_meta = _label("", 14)
	right.add_child(_detail_meta)
	_detail_text = _label("", 17)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail_text)
	# Настройки сразу под описанием: на низком экране их не придётся искать внизу.
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 6)
	_settings_box.visible = false
	right.add_child(_settings_box)
	_detail_content = _label("", 16)
	_detail_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail_content)
	_detail_problems = _label("", 15)
	_detail_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_problems.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	right.add_child(_detail_problems)
	_play_button = _button("", _on_play_pressed, 20)
	right.add_child(_play_button)
	_continue_button = _button("", _on_continue_pressed, 20)
	right.add_child(_continue_button)
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 8)
	_difficulty_row.visible = false
	for difficulty in Game.DIFFICULTY_NAMES.size():
		var button := _button(Game.DIFFICULTY_NAMES[difficulty], _start_selected.bind(difficulty), 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_difficulty_row.add_child(button)
	right.add_child(_difficulty_row)

	# Низ: установка и навигация.
	var install := HBoxContainer.new()
	install.add_theme_constant_override("separation", 8)
	column.add_child(install)
	if not _is_web() and not _is_phone_app():  # у веб-версии и приложения на телефоне нет папки, которую можно открыть
		install.add_child(_button("Открыть папку модов", _open_folder, 17))
	install.add_child(_button("Установить из файла…", _choose_file, 17))
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "https://… — ссылка на .zip мода"
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.custom_minimum_size = Vector2(260, 0)
	_url_edit.text_submitted.connect(func(_text: String) -> void: _download())
	install.add_child(_url_edit)
	_download_button = _button("Скачать и установить", _download, 17)
	install.add_child(_download_button)
	_status = _label("", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var back := _button("Назад", _back, 20)
	back.custom_minimum_size = Vector2(240, 44)
	column.add_child(back)

	_consent_dialog = ConfirmationDialog.new()
	_consent_dialog.title = "Мод со скриптами"
	_consent_dialog.ok_button_text = "Включить"
	_consent_dialog.cancel_button_text = "Отмена"
	_consent_dialog.confirmed.connect(_consent_confirmed)
	add_child(_consent_dialog)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.zip ; Моды (zip-архивы)"])
	_file_dialog.title = "Выберите zip-архив мода"
	_file_dialog.file_selected.connect(_install_file)
	add_child(_file_dialog)
	_http = HTTPRequest.new()
	_http.body_size_limit = MAX_DOWNLOAD_BYTES
	_http.timeout = 60.0
	_http.request_completed.connect(_on_download_done)
	add_child(_http)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label


func _button(text: String, action: Callable, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", size)
	button.pressed.connect(action)
	return button


# --- Список и описание -------------------------------------------------------------------------

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if Mods.mods.is_empty():
		var empty := _label("Модов пока нет. Положите мод (папку или .zip) в папку модов\nили установите кнопками внизу.", 16)
		_list.add_child(empty)
	for mod in Mods.mods:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.button_pressed = mod.enabled
		check.disabled = not mod.ok()
		check.toggled.connect(_on_toggled.bind(mod.id))
		row.add_child(check)
		var text := mod.label()
		if mod.has_scripts():
			text += "  [скрипты]"
		if not mod.ok():
			text += "  [ошибка]"
		var pick := Button.new()
		pick.text = text
		pick.flat = false
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.add_theme_font_size_override("font_size", 17)
		if not mod.ok():
			pick.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		pick.pressed.connect(_select.bind(mod.id))
		row.add_child(pick)
		_list.add_child(row)
	_show_detail()


func _select(id: String) -> void:
	_selected_id = id
	_difficulty_row.visible = false
	_show_detail()


func selected_mod() -> ModInfo:
	return Mods.get_mod(_selected_id)


func _show_detail() -> void:
	var mod := selected_mod()
	_play_button.visible = false
	_continue_button.visible = false
	_difficulty_row.visible = _difficulty_row.visible and mod != null
	_build_settings(mod)
	if mod == null:
		_detail_title.text = ""
		_detail_meta.text = ""
		_detail_text.text = ""
		_detail_content.text = ""
		_detail_problems.text = ""
		return
	_detail_title.text = mod.title
	_detail_meta.text = "id: %s · версия %s · автор: %s\n%s" % [mod.id, mod.version if mod.version != "" else "—", mod.author if mod.author != "" else "—", mod.path]
	_detail_text.text = mod.description
	var parts: Array[String] = []
	if mod.active:
		var enemies := 0
		var bosses := 0
		for entity in Mods.entities_of(mod):
			if entity["kind"] == "boss":
				bosses += 1
			else:
				enemies += 1
		parts.append("Врагов: %d · боссов: %d · уровней: %d" % [enemies, bosses, mod.levels.size()])
	elif mod.ok():
		parts.append("Мод выключен — включите галочкой слева.")
	if mod.has_scripts():
		parts.append("Содержит скрипты (%d). %s" % [mod.script_files.size(), "Подтверждены вами." if Mods.has_consent(mod) else "Включайте только если доверяете автору."])
	_detail_content.text = "\n".join(parts)
	var problems: Array[String] = []
	problems.append_array(mod.errors)
	problems.append_array(mod.problems)
	var warnings: Array[String] = []
	warnings.append_array(mod.warnings)
	_detail_problems.text = "\n".join(problems) + ("\n" if not problems.is_empty() and not warnings.is_empty() else "") + "\n".join(warnings)
	if mod.active and mod.has_campaign():
		_play_button.visible = true
		_play_button.text = "Играть: %s (уровней: %d)" % [mod.campaign["title"], mod.campaign["levels"].size()]
		var saved := Game.saved_campaign("mod:" + mod.id)
		if not saved.is_empty() and saved["level_index"] < mod.campaign["levels"].size():
			_continue_button.visible = true
			_continue_button.text = "Продолжить с уровня %d" % (int(saved["level_index"]) + 1)


# --- Настройки мода (API 2) ------------------------------------------------------------------------

## Строит элементы управления для настроек выбранного мода: галочка (bool), список (choice), ползунок (number).
## Изменения сразу запоминаются (Mods.set_setting) и действуют со следующего забега.
func _build_settings(mod: ModInfo) -> void:
	for child in _settings_box.get_children():
		child.queue_free()
	_settings_box.visible = mod != null and mod.ok() and not mod.settings.is_empty()
	if not _settings_box.visible:
		return
	var header := _label("Настройки мода", 22)
	header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	_settings_box.add_child(header)
	if not mod.active:
		_settings_box.add_child(_label("Мод выключен: выбранное сохранится и заработает после включения.", 14))
	for setting in mod.settings:
		_settings_box.add_child(_make_setting_row(mod.id, setting))


func _make_setting_row(mod_id: String, setting: Dictionary) -> Control:
	var id: String = setting["id"]
	var value = Mods.get_setting(mod_id, id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	match setting["type"]:
		"bool":
			var check := CheckBox.new()
			check.text = setting["title"]
			check.button_pressed = bool(value)
			check.add_theme_font_size_override("font_size", 18)
			check.toggled.connect(func(on: bool) -> void: Mods.set_setting(mod_id, id, on))
			box.add_child(check)
		"choice":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_label(setting["title"], 18))
			var options := OptionButton.new()
			for option in setting["options"]:
				options.add_item(option)
			options.select(int(value))
			options.add_theme_font_size_override("font_size", 17)
			options.item_selected.connect(func(index: int) -> void: Mods.set_setting(mod_id, id, index))
			row.add_child(options)
			box.add_child(row)
		"number":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_label(setting["title"], 18))
			var slider := HSlider.new()
			slider.min_value = setting["min"]
			slider.max_value = setting["max"]
			slider.step = setting["step"]
			slider.value = float(value)
			slider.custom_minimum_size = Vector2(180, 24)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(slider)
			var shown := _label(str(snappedf(float(value), 0.01)), 18)
			slider.value_changed.connect(func(v: float) -> void:
				shown.text = str(snappedf(v, 0.01))
				Mods.set_setting(mod_id, id, v))
			row.add_child(shown)
			box.add_child(row)
	if str(setting["description"]) != "":
		var description := _label(setting["description"], 14)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(380, 0)
		description.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
		box.add_child(description)
	return box


# --- Действия ---------------------------------------------------------------------------------------

func _on_toggled(on: bool, id: String) -> void:
	var mod := Mods.get_mod(id)
	if mod == null:
		return
	if on and mod.has_scripts() and not Mods.has_consent(mod):
		_pending_consent = id
		_consent_dialog.dialog_text = "Мод «%s» содержит скрипты (%d).\n\nСкрипты выполняются внутри игры и могут делать всё, что разрешено самой игре. Грубо опасные вызовы игра блокирует, но это не полная защита.\n\nВключайте только моды, которым доверяете (автор известен, источник надёжный). Включить?" % [mod.title, mod.script_files.size()]
		_consent_dialog.popup_centered(Vector2i(640, 300))
		_refresh()  # галочка вернётся на место, пока игрок не подтвердил
		return
	Mods.set_enabled(mod, on)
	_selected_id = id
	_refresh()


func _consent_confirmed() -> void:
	var mod := Mods.get_mod(_pending_consent)
	_pending_consent = ""
	if mod == null:
		return
	Mods.grant_script_consent(mod)
	Mods.set_enabled(mod, true)
	_selected_id = mod.id
	_refresh()


func _on_play_pressed() -> void:
	_difficulty_row.visible = not _difficulty_row.visible


func _start_selected(difficulty: int) -> void:
	var mod := selected_mod()
	if mod == null or not mod.has_campaign():
		return
	Game.start_campaign("mod:" + mod.id, mod.campaign["title"], Mods.campaign_levels(mod), difficulty)


func _on_continue_pressed() -> void:
	var mod := selected_mod()
	if mod == null or not mod.has_campaign():
		return
	Game.continue_campaign("mod:" + mod.id, mod.campaign["title"], Mods.campaign_levels(mod))


func _open_folder() -> void:
	OS.shell_open(Mods.user_mods_dir())


func _choose_file() -> void:
	if _is_web():
		_choose_file_in_browser()
		return
	_file_dialog.popup_centered_ratio(0.7)


func _install_file(path: String) -> void:
	_report(Mods.install_zip_file(path))


func _is_web() -> bool:
	return OS.has_feature("web")


## Приложение на Android или iOS: данные игры лежат в закрытой папке, файловым менеджером её не открыть.
func _is_phone_app() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## Веб-версия: у игры нет доступа к дискам, поэтому файл выбирается обычным окном браузера
## (<input type=file>), а содержимое приходит в игру base64-строкой и ставится как скачанный мод.
func _choose_file_in_browser() -> void:
	_web_callback = JavaScriptBridge.create_callback(_on_browser_file)
	JavaScriptBridge.get_interface("window").shootinPickedMod = _web_callback
	JavaScriptBridge.eval("""
		(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.zip,application/zip';
			input.onchange = function () {
				var file = input.files[0];
				if (!file) { return; }
				var reader = new FileReader();
				reader.onload = function () {
					var bytes = new Uint8Array(reader.result);
					var binary = '';
					for (var i = 0; i < bytes.length; i += 0x8000) {
						binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
					}
					window.shootinPickedMod(file.name, btoa(binary));
				};
				reader.readAsArrayBuffer(file);
			};
			input.click();
		})();
	""", true)


func _on_browser_file(args: Array) -> void:
	if args.size() < 2:
		return
	_set_status("Устанавливаю %s…" % str(args[0]), false)
	_report(Mods.install_zip_bytes(Marshalls.base64_to_raw(str(args[1]))))


func _download() -> void:
	var url := _url_edit.text.strip_edges()
	if not url.begins_with("https://"):
		_set_status("Нужна ссылка, начинающаяся с https:// (незащищённые http-ссылки не принимаются).", true)
		return
	_set_status("Скачиваю…", false)
	_download_button.disabled = true
	var err := _http.request(url)
	if err != OK:
		_download_button.disabled = false
		_set_status("Не удалось начать скачивание (код %d)." % err, true)


func _on_download_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_download_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_status("Не удалось скачать мод (результат %d, ответ сервера %d)." % [result, code], true)
		return
	_report(Mods.install_zip_bytes(body))


func _report(outcome: Dictionary) -> void:
	_set_status(outcome["message"], not outcome["ok"])
	_refresh()
	if outcome["ok"]:
		_select(outcome["id"])


func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if is_error else Color(0.7, 1.0, 0.7))


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _difficulty_row.visible:
			_difficulty_row.visible = false
		else:
			_back()
		get_viewport().set_input_as_handled()
