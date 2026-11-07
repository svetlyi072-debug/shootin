extends SceneTree
## Проверка собранной игры: главное меню, экран модов и все уровни должны загрузиться
## из упакованных ресурсов. Запускается на самом экспортированном exe/бинарнике:
##   ShootIn.exe --headless --script D:/shootin/tools/export/smoke_test.gd
## или на игре из проекта:
##   godot --headless --path D:/shootin --script res://tools/export/smoke_test.gd
## Код выхода 0 — всё хорошо, 1 — есть ошибки.

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var game = root.get_node("Game")
	var mods = root.get_node("Mods")
	_save_user_files()
	await frames(2)
	print("система: %s, exe: %s, редактор: %s" % [OS.get_name(), OS.get_executable_path(), str(OS.has_feature("editor"))])
	print("версия игры: ", ProjectSettings.get_setting("application/config/version", "?"))

	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await frames(10)
	check(current_scene != null and current_scene.name == "MainMenu", "главное меню загрузилось (%s)" % str(current_scene))

	change_scene_to_file("res://scenes/ui/mods_menu.tscn")
	await frames(10)
	check(current_scene != null and current_scene.get_child_count() > 3, "экран модов построился")

	var total: int = game.level_count()
	check(total == 34, "уровней в игре: %d" % total)
	game.difficulty = 1
	for i in total:
		if OS.get_cmdline_user_args().has("--verbose-levels"):
			print("... уровень %d" % (i + 1))
		game.level_index = i
		change_scene_to_file("res://scenes/main.tscn")
		await frames(30)
		var player := get_first_node_in_group("player")
		var enemies := get_nodes_in_group("enemies").size()
		var ok: bool = player != null and player.is_on_floor() and enemies > 0
		if not ok:
			check(false, "уровень %d: игрок %s, на земле %s, врагов %d" % [i + 1, str(player), str(player != null and player.is_on_floor()), enemies])
	check(true, "все %d уровней загружены, игрок стоит на земле, враги на месте" % total)

	await _test_mod_install(game, mods)
	_restore_user_files()
	print("ИТОГ: %s (%d ошибок)" % ["ВСЁ ХОРОШО" if fails == 0 else "ЕСТЬ ОШИБКИ", fails])
	quit(1 if fails else 0)


## Игрок ставит мод из .zip: файл читается из архива, мод находится, его уровень запускается.
## (Эта проверка поймала ошибку, из-за которой в собранной игре не читался ни один файл мода.)
func _test_mod_install(game, mods) -> void:
	var rows: Array[String] = []
	for y in 12:
		rows.append(".".repeat(40))
	rows[10] = "..P" + ".".repeat(35) + "E."
	rows[11] = "#".repeat(40)
	rows[9] = ".".repeat(20) + "G" + ".".repeat(19)
	var level_text := "title: Проверка мода\ntheme: grass\nrequire_clear: no\n\n" + "\n".join(rows) + "\n"
	var manifest := {"id": "smoke_test_mod", "name": "Проверка установки", "version": "1.0.0", "author": "тест", "description": "Мод для проверки сборки.", "api": 1, "campaign": {"title": "Проверка", "levels": ["levels/01.txt"]}}
	var zip_path := ProjectSettings.globalize_path("user://smoke_mod.zip")
	var packer := ZIPPacker.new()
	check(packer.open(zip_path) == OK, "тестовый zip создан")
	packer.start_file("mod.json")
	packer.write_file(JSON.stringify(manifest, "  ").to_utf8_buffer())
	packer.close_file()
	packer.start_file("levels/01.txt")
	packer.write_file(level_text.to_utf8_buffer())
	packer.close_file()
	packer.close()

	var outcome: Dictionary = mods.install_zip_file(zip_path)
	check(outcome["ok"], "мод из zip устанавливается: %s" % outcome["message"])
	var mod = mods.get_mod("smoke_test_mod")
	check(mod != null and mod.ok() and mod.title == "Проверка установки", "мод найден, название с кириллицей прочитано (%s)" % (str(mod.title) if mod != null else "нет мода"))
	if mod != null and mod.ok():
		var levels: Array = mods.campaign_levels(mod)
		check(levels.size() == 1, "уровень мода прочитан из архива (%d)" % levels.size())
		if levels.size() == 1:
			game.start_campaign("mod:smoke_test_mod", "Проверка", levels, 1)
			await frames(40)
			var player := get_first_node_in_group("player")
			check(player != null and player.is_on_floor(), "уровень мода запускается, игрок стоит на земле")
			game.leave_campaign()
	# Уборка: закрыть архив, удалить установленный мод и временный файл.
	mods._deactivate_all()
	for path in [ProjectSettings.globalize_path("user://mods/smoke_test_mod.zip"), zip_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	mods.rescan()
	check(mods.get_mod("smoke_test_mod") == null, "после уборки тестового мода в списке нет")


# Тест не должен затирать сохранения того, кто его запускает: копируем файлы и возвращаем на место.
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
