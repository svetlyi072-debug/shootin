extends Node
## Моды (автозагрузка «Mods»). Игрок кладёт мод в папку «mods» (папкой или .zip) — игра находит его,
## читает mod.json и подключает к себе: уровни, врагов, боссов и скрипты. Переустанавливать игру
## и иметь её исходники не нужно. Подробно для авторов модов — MODDING.md.
##
## Где ищутся моды (по порядку; при одинаковом id берётся первый):
##   1. папка «mods» рядом с игрой (exe);
##   2. user://mods (на Windows: %APPDATA%\Godot\app_userdata\ShootIn\mods) — сюда ставит меню «Моды»;
##   3. res://mods — только при запуске из редактора Godot.
##
## Что может мод:
##   * enemies/*.json — свои враги (ходячие, метатели, засада из земли) со своей графикой;
##   * bosses/*.json  — свои боссы: набор атак описывается данными (см. mod_boss.gd);
##   * levels/*.txt|json — свои уровни; в карте можно ставить символы своих врагов и боссов;
##   * campaign в mod.json — порядок уровней (иначе все уровни по алфавиту);
##   * scripts/*.gd — свой код: хуки на события игры (ModScript) и скрипты врагов/боссов.
## Скрипты запускаются в игре с теми же правами, что и сама игра, поэтому мод со скриптами
## включается только после явного подтверждения игрока; грубо опасные вызовы (OS, FileAccess,
## сеть и т. п.) загрузчик блокирует — но это не песочница, ставьте моды из надёжных источников.

signal mods_changed

const API_VERSION := ModInfo.API_VERSION
const CONFIG_PATH := "user://mods.cfg"
const USER_MODS_DIR := "user://mods"
const ID_PATTERN := "^[a-z0-9][a-z0-9_\\-]{1,39}$"
## Символы карты, занятые самой картой (мод не может отдать их своим врагам).
const RESERVED_SYMBOLS := ".#-^+EP "
const MAX_MAP_WIDTH := 1500
const MAX_MAP_HEIGHT := 300
const MAX_SCRIPT_BYTES := 200000
const MAX_ZIP_BYTES := 100 * 1024 * 1024
const LEVEL_EXTENSIONS := ["txt", "json"]

## Запрещённые в скриптах модов вызовы (поиск идёт по коду без комментариев и строк).
const FORBIDDEN_PATTERNS := [
	"\\bOS\\b", "\\bFileAccess\\b", "\\bDirAccess\\b", "\\bHTTPRequest\\b", "\\bHTTPClient\\b",
	"\\bTCPServer\\b", "\\bStreamPeer\\w*\\b", "\\bPacketPeer\\w*\\b", "\\bUDPServer\\b", "\\bWebSocket\\w*\\b",
	"\\bClassDB\\b", "\\bJavaScriptBridge\\b", "\\bProjectSettings\\b", "\\bGDExtension\\w*\\b",
	"\\bResourceSaver\\b", "\\bResourceLoader\\b", "\\bExpression\\b", "\\bGDScript\\b", "\\bThread\\b",
	"\\bEngine\\s*\\.\\s*(get_singleton|register_singleton|get_main_loop|has_singleton)\\b",
	"\\bload_resource_pack\\b", "\\bbytes_to_var_with_objects\\b", "\\bDisplayServer\\b", "\\bIP\\b",
]

## Найденные моды (включая сломанные — чтобы показать, что с ними не так).
var mods: Array[ModInfo] = []
var extra_dirs: Array[String] = []
## id мода → {символ → запись о враге/боссе}. Символы у каждого мода свои: два мода могут
## использовать одну и ту же букву, уровень мода видит в первую очередь символы своего мода.
var _symbols := {}
var _scripts: Array[Node] = []
var _script_cache := {}
var _enabled := {}
var _consent := {}
var _by_id := {}
var _builtin_spawns := {}

const ENEMY_SCENE := preload("res://scenes/mods/mod_walker.tscn")
const BOSS_SCENE := preload("res://scenes/mods/mod_boss.tscn")

const WALKER_STATS := {
	"health": "max_health", "reward": "power_reward", "corpse_time": "corpse_time", "dodge_chance": "dodge_chance",
	"flee_below_health": "flee_below_health", "speed": "move_speed_tiles", "aggro_range": "aggro_range_tiles",
	"attack_range": "attack_range_tiles", "attack_damage": "attack_damage", "attack_cooldown": "attack_cooldown",
	"attack_duration": "attack_duration", "attack_hit_time": "attack_hit_time", "can_jump": "can_jump_on_blocks",
}
const BOSS_STATS := {
	"health": "max_health", "smart_health_multiplier": "smart_health_multiplier", "reward": "power_reward",
	"corpse_time": "corpse_time", "speed": "walk_speed_tiles", "stop_distance": "stop_distance_tiles",
	"arena": "arena_half_width_tiles", "activation_range": "activation_range_tiles", "max_minions": "max_minions",
	"enrage_at": "enrage_ratio",
}
const ATTACK_TYPES := ["melee", "projectile", "shockwave", "summon", "charge"]


func _ready() -> void:
	for scene_symbol in _spawn_table():
		_builtin_spawns[scene_symbol] = true
	rescan()
	Game.enemy_killed.connect(func(enemy: Node, reward: int) -> void: notify("_enemy_killed", [enemy, reward]))
	Game.boss_defeated.connect(func() -> void: notify("_boss_defeated"))
	Game.player_died.connect(func() -> void: notify("_player_died"))
	Game.level_completed.connect(func(_title: String) -> void: notify("_level_completed"))
	Game.game_won.connect(func() -> void: notify("_level_completed"))


# =====================================================================================================
# Папки и поиск модов
# =====================================================================================================

func user_mods_dir() -> String:
	var path := ProjectSettings.globalize_path(USER_MODS_DIR)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func mod_directories() -> Array[String]:
	var dirs: Array[String] = []
	var next_to_game := OS.get_executable_path().get_base_dir().path_join("mods")
	if DirAccess.dir_exists_absolute(next_to_game):
		dirs.append(next_to_game)
	dirs.append(user_mods_dir())
	if OS.has_feature("editor"):
		var project_mods := ProjectSettings.globalize_path("res://mods")
		if DirAccess.dir_exists_absolute(project_mods):
			dirs.append(project_mods)
	for dir in extra_dirs:
		dirs.append(dir)
	return dirs


## Находит все моды заново и подключает включённые.
func rescan() -> void:
	_deactivate_all()
	mods.clear()
	_by_id.clear()
	_load_config()
	var seen_paths := {}
	for dir in mod_directories():
		for entry in DirAccess.get_directories_at(dir):
			if entry.begins_with(".") or entry.begins_with("_"):
				continue
			var path := dir.path_join(entry)
			if FileAccess.file_exists(path.path_join("mod.json")) and not seen_paths.has(path):
				seen_paths[path] = true
				_add_mod(path)
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() == "zip" and not file.begins_with("_"):
				var path := dir.path_join(file)
				if not seen_paths.has(path):
					seen_paths[path] = true
					_add_mod(path)
	mods.sort_custom(func(a: ModInfo, b: ModInfo) -> bool: return a.title.naturalnocasecmp_to(b.title) < 0)
	for mod in mods:
		mod.enabled = _is_enabled(mod)
	for mod in mods:
		if mod.enabled:
			_activate_entities(mod)
	for mod in mods:
		if mod.active:
			_activate_levels(mod)
	for mod in mods:
		if mod.active:
			_activate_scripts(mod)
	mods_changed.emit()


func _add_mod(path: String) -> void:
	var mod := ModInfo.new()
	mod.path = path
	mod.title = path.get_file().get_basename()
	mod.files = ModFiles.new(path)
	var open_error := mod.files.open()
	if open_error != "":
		mod.error(open_error)
		mods.append(mod)
		return
	var parsed = JSON.parse_string(mod.files.read_text("mod.json"))
	if not parsed is Dictionary:
		mod.error("mod.json не читается: проверьте запятые и кавычки (формат JSON)")
		mods.append(mod)
		return
	mod.manifest = parsed
	mod.id = str(parsed.get("id", "")).strip_edges()
	mod.title = str(parsed.get("name", mod.id))
	mod.version = str(parsed.get("version", ""))
	mod.author = str(parsed.get("author", ""))
	mod.description = str(parsed.get("description", ""))
	mod.api = int(parsed.get("api", 1))
	var id_regex := RegEx.create_from_string(ID_PATTERN)
	if id_regex.search(mod.id) == null:
		mod.error("id мода «%s» не подходит: 2–40 символов, строчные латинские буквы, цифры, «_» и «-»" % mod.id)
	elif _by_id.has(mod.id):
		mod.error("мод с таким id уже есть (%s) — этот пропущен" % _by_id[mod.id].path.get_file())
	if mod.api > API_VERSION:
		mod.error("мод сделан для более новой версии модов (api %d, у игры %d) — обновите игру" % [mod.api, API_VERSION])
	for file in mod.files.list_files("scripts", ["gd"]):
		mod.script_files.append(file)
	if mod.ok():
		_by_id[mod.id] = mod
	mods.append(mod)


func get_mod(id: String) -> ModInfo:
	return _by_id.get(id)


# =====================================================================================================
# Включение, подтверждение скриптов, сохранение выбора
# =====================================================================================================

func _load_config() -> void:
	_enabled.clear()
	_consent.clear()
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	if config.has_section("enabled"):
		for key in config.get_section_keys("enabled"):
			_enabled[key] = bool(config.get_value("enabled", key))
	if config.has_section("scripts"):
		for key in config.get_section_keys("scripts"):
			_consent[key] = str(config.get_value("scripts", key))


func _save_config() -> void:
	var config := ConfigFile.new()
	for key in _enabled:
		config.set_value("enabled", key, _enabled[key])
	for key in _consent:
		config.set_value("scripts", key, _consent[key])
	config.save(CONFIG_PATH)


## Включён ли мод: явный выбор игрока; иначе моды без скриптов включаются сами, со скриптами — нет.
func _is_enabled(mod: ModInfo) -> bool:
	if not mod.ok():
		return false
	if _enabled.has(mod.id):
		return _enabled[mod.id] and (not mod.has_scripts() or has_consent(mod))
	return not mod.has_scripts()


## Отпечаток всех скриптов мода: если они изменились, подтверждение нужно дать заново.
func script_hash(mod: ModInfo) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	for file in mod.script_files:
		hasher.update(file.to_utf8_buffer())
		hasher.update(mod.files.read_bytes(file))
	return hasher.finish().hex_encode()


func has_consent(mod: ModInfo) -> bool:
	return not mod.has_scripts() or _consent.get(mod.id, "") == script_hash(mod)


func grant_script_consent(mod: ModInfo) -> void:
	if mod.has_scripts():
		_consent[mod.id] = script_hash(mod)
		_save_config()


## Включает или выключает мод. Для мода со скриптами сначала нужно grant_script_consent().
func set_enabled(mod: ModInfo, on: bool) -> bool:
	if on and (not mod.ok() or not has_consent(mod)):
		return false
	_enabled[mod.id] = on
	_save_config()
	rescan()
	return true


func enabled_mods() -> Array[ModInfo]:
	var out: Array[ModInfo] = []
	for mod in mods:
		if mod.active:
			out.append(mod)
	return out


# =====================================================================================================
# Подключение мода: враги, боссы, уровни, скрипты
# =====================================================================================================

func _deactivate_all() -> void:
	for node in _scripts:
		if is_instance_valid(node):
			node.queue_free()
	_scripts.clear()
	_script_cache.clear()
	_symbols.clear()
	ModSprites.clear_cache()
	for mod in mods:
		if mod.files:
			mod.files.close()


func _activate_entities(mod: ModInfo) -> void:
	mod.active = true
	for file in mod.files.list_files("enemies", ["json"]):
		_load_entity(mod, file, "enemy")
	for file in mod.files.list_files("bosses", ["json"]):
		_load_entity(mod, file, "boss")


func _activate_levels(mod: ModInfo) -> void:
	for file in mod.files.list_files("levels", LEVEL_EXTENSIONS):
		var level := parse_level(mod, file)
		if not level.is_empty():
			mod.levels[file] = level
	var declared = mod.manifest.get("campaign", null)
	if declared is Dictionary:
		var paths: Array[String] = []
		for entry in declared.get("levels", []):
			var rel := str(entry)
			if not mod.levels.has(rel):
				mod.problem("в кампании указан уровень «%s», такого файла нет или он с ошибками" % rel)
			else:
				paths.append(rel)
		mod.campaign = {"title": str(declared.get("title", mod.title)), "levels": paths}
	elif not mod.levels.is_empty():
		var all: Array[String] = []
		for rel in mod.levels:
			all.append(rel)
		all.sort()
		mod.campaign = {"title": mod.title, "levels": all}


func _activate_scripts(mod: ModInfo) -> void:
	if not mod.has_scripts() or not has_consent(mod):
		return
	var entry_files: Array = mod.manifest.get("scripts", [])
	if entry_files.is_empty() and mod.files.exists("scripts/main.gd"):
		entry_files = ["scripts/main.gd"]
	for entry in entry_files:
		var script := load_mod_script(mod, str(entry))
		if script == null:
			continue
		var node = script.new()
		if not node is ModScript:
			mod.problem("скрипт «%s» должен начинаться с «extends ModScript»" % entry)
			continue
		node.mod = mod
		node.name = "Mod_%s_%s" % [mod.id, str(entry).get_file().get_basename()]
		add_child(node)
		_scripts.append(node)
		node._mod_ready()


## Загружает скрипт мода (GDScript из текста). null — если скрипта нет, он опасен или не компилируется.
func load_mod_script(mod: ModInfo, rel: String) -> GDScript:
	var key := "%s|%s" % [mod.id, rel]
	if _script_cache.has(key):
		return _script_cache[key]
	if not mod.files.exists(rel) or rel.get_extension() != "gd":
		mod.problem("скрипт «%s» не найден" % rel)
		return null
	if not has_consent(mod):
		mod.problem("скрипты мода не подтверждены игроком")
		return null
	var source := mod.files.read_text(rel)
	if source.length() > MAX_SCRIPT_BYTES:
		mod.problem("скрипт «%s» слишком большой" % rel)
		return null
	var banned := scan_script(source)
	if banned != "":
		mod.problem("скрипт «%s» использует запрещённое: %s" % [rel, banned])
		return null
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	if err != OK:
		mod.problem("скрипт «%s» не компилируется (ошибка %d) — см. вывод игры" % [rel, err])
		return null
	_script_cache[key] = script
	return script


## Ищет в коде запрещённые вызовы. Возвращает найденное слово или "".
func scan_script(source: String) -> String:
	var code := source
	for pattern in ["\"\"\"[\\s\\S]*?\"\"\"", "'''[\\s\\S]*?'''", "\"(\\\\.|[^\"\\\\\\n])*\"", "'(\\\\.|[^'\\\\\\n])*'", "#[^\\n]*"]:
		code = RegEx.create_from_string(pattern).sub(code, "", true)
	for pattern in FORBIDDEN_PATTERNS:
		var found := RegEx.create_from_string(pattern).search(code)
		if found:
			return found.get_string().replace("\n", " ")
	return ""


# =====================================================================================================
# Враги и боссы из JSON
# =====================================================================================================

func _spawn_table() -> Dictionary:
	var level_script: GDScript = load("res://scripts/level/level.gd")
	return level_script.get_script_constant_map()["SPAWNS"]


func _read_json(mod: ModInfo, rel: String) -> Dictionary:
	var parsed = JSON.parse_string(mod.files.read_text(rel))
	if not parsed is Dictionary:
		mod.problem("%s: не читается как JSON (проверьте запятые и кавычки)" % rel)
		return {}
	return parsed


func _load_entity(mod: ModInfo, rel: String, kind: String) -> void:
	var def := _read_json(mod, rel)
	if def.is_empty():
		return
	var where := rel
	var id := str(def.get("id", rel.get_file().get_basename()))
	var symbol := str(def.get("symbol", ""))
	if symbol.length() != 1 or RESERVED_SYMBOLS.contains(symbol):
		mod.problem("%s: symbol должен быть одним символом, не из «%s» и не пробелом (получено «%s»)" % [where, RESERVED_SYMBOLS.strip_edges(), symbol])
		return
	if _builtin_spawns.has(symbol):
		mod.problem("%s: символ «%s» занят игрой — выберите другой" % [where, symbol])
		return
	var own: Dictionary = _symbols.get(mod.id, {})
	if own.has(symbol):
		mod.problem("%s: символ «%s» уже занят другим врагом этого мода (%s)" % [where, symbol, own[symbol]["id"]])
		return
	var problems: Array = []
	var sprite_spec = def.get("sprite", {})
	if not sprite_spec is Dictionary:
		mod.problem("%s: sprite должен быть объектом" % where)
		return
	var frames := ModSprites.build_frames(mod, sprite_spec, problems)
	for problem in problems:
		mod.problem("%s: %s" % [where, problem])
	if frames == null:
		return
	var record := {
		"mod": mod, "kind": kind, "id": id, "symbol": symbol, "def": def, "frames": frames,
		"name": str(def.get("name", id)), "script": null, "attacks": [], "throw_frames": null,
	}
	var scale := float(sprite_spec.get("scale", 1.0))
	var idle_name := _pick_animation(frames, ["idle", "stand", "walk", "move", "run"])
	record["idle"] = idle_name
	var measured := ModSprites.measure(frames, idle_name)
	if sprite_spec.has("offset") and sprite_spec["offset"] is Array and sprite_spec["offset"].size() >= 2:
		record["offset"] = Vector2(float(sprite_spec["offset"][0]), float(sprite_spec["offset"][1]))
	else:
		record["offset"] = ModSprites.auto_offset(measured)
	var body = def.get("body", null)
	if body is Array and body.size() >= 2:
		record["body"] = Vector2(float(body[0]), float(body[1]))
	elif not measured.is_empty():
		record["body"] = Vector2(
			clampf(measured["width"] * scale * 0.6, 12.0, 400.0),
			clampf(measured["height"] * scale * 0.9, 16.0, 400.0))
	else:
		record["body"] = Vector2(24.0, 52.0)
	var script_rel := str(def.get("script", ""))
	if script_rel != "":
		var script := load_mod_script(mod, script_rel)
		if script == null:
			return
		record["script"] = script
	if kind == "boss":
		for entry in def.get("attacks", []):
			var attack := _normalize_attack(mod, where, entry)
			if not attack.is_empty():
				record["attacks"].append(attack)
		if record["attacks"].is_empty() and script_rel == "":
			mod.problem("%s: у босса нет ни одной атаки (поле attacks) и нет своего скрипта" % where)
			return
	elif def.has("throw") and def["throw"] is Dictionary:
		var throw_errors: Array = []
		record["throw_frames"] = ModSprites.projectile_frames(mod, def["throw"].get("projectile", "bomb"), throw_errors)
		for problem in throw_errors:
			mod.problem("%s: throw: %s" % [where, problem])
	own[symbol] = record
	_symbols[mod.id] = own


func _pick_animation(frames: SpriteFrames, candidates: Array) -> String:
	for name in candidates:
		if frames.has_animation(name):
			return name
	return str(frames.get_animation_names()[0])


## Приводит описание атаки босса к полному виду (с числами по умолчанию). {} — если атака негодная.
func _normalize_attack(mod: ModInfo, where: String, entry) -> Dictionary:
	if not entry is Dictionary:
		mod.problem("%s: каждая атака должна быть объектом" % where)
		return {}
	var type := str(entry.get("type", ""))
	if not ATTACK_TYPES.has(type):
		mod.problem("%s: неизвестный тип атаки «%s» (есть: %s)" % [where, type, ", ".join(ATTACK_TYPES)])
		return {}
	var attack: Dictionary = entry.duplicate(true)
	attack["type"] = type
	var defaults := {
		"melee": {"range": 2.0, "damage": 12, "interval": 1.5, "windup": 0.3, "recover": 0.4},
		"projectile": {"count": 1, "speed": 8.0, "damage": 10, "interval": 3.5, "windup": 0.4, "recover": 0.4, "gap": 0.3, "pattern": "aimed", "min_range": 2.0},
		"shockwave": {"radius": 8.0, "speed": 9.0, "damage": 15, "interval": 8.0, "windup": 0.4, "recover": 0.5},
		"summon": {"count": 2, "interval": 14.0, "windup": 0.6, "recover": 0.6, "enemy": ""},
		"charge": {"speed": 10.0, "damage": 20, "interval": 9.0, "windup": 0.7, "max_time": 1.5, "min_range": 4.0, "smart_only": true},
	}
	for key in defaults[type]:
		if not attack.has(key):
			attack[key] = defaults[type][key]
	if type == "melee":
		attack["max_range"] = float(attack.get("max_range", attack["range"]))
	if type == "projectile":
		var pattern := str(attack["pattern"])
		if not ["aimed", "fan", "lob", "rain"].has(pattern):
			mod.problem("%s: pattern снаряда «%s» неизвестен (aimed, fan, lob, rain)" % [where, pattern])
			return {}
		var errors: Array = []
		attack["frames"] = ModSprites.projectile_frames(mod, entry.get("projectile", "fireball"), errors)
		for problem in errors:
			mod.problem("%s: атака projectile: %s" % [where, problem])
		if attack["frames"] == null:
			return {}
	if type == "summon":
		var symbol := str(attack["enemy"])
		if symbol == "":
			mod.problem("%s: у атаки summon не указан enemy (символ врага)" % where)
			return {}
	return attack


# =====================================================================================================
# Создание врагов и боссов мода для уровня
# =====================================================================================================

## Запись о символе: сначала у мода mod_id, потом (если там нет) у других включённых модов.
func _find(symbol: String, mod_id: String = "") -> Variant:
	if mod_id != "" and _symbols.has(mod_id) and _symbols[mod_id].has(symbol):
		return _symbols[mod_id][symbol]
	for id in _symbols:
		if _symbols[id].has(symbol):
			return _symbols[id][symbol]
	return null


## Есть ли такой символ у мода mod_id (или, если mod_id пуст, у любого включённого мода).
func has_symbol(symbol: String, mod_id: String = "") -> bool:
	return _find(symbol, mod_id) != null


## Узел врага или босса по символу карты (null, если символа нет). Конфигурация применяется до add_child.
func create_entity(symbol: String, mod_id: String = "") -> Node2D:
	var record = _find(symbol, mod_id)
	if record == null:
		return null
	if record.has("factory"):
		return record["factory"].call()
	return _make_boss(record) if record["kind"] == "boss" else _make_enemy(record)


## Какие враги и боссы добавлены модом: [{symbol, id, name, kind}, ...].
func entities_of(mod: ModInfo) -> Array:
	var out: Array = []
	var own: Dictionary = _symbols.get(mod.id, {})
	for symbol in own:
		var record: Dictionary = own[symbol]
		out.append({"symbol": symbol, "id": record["id"], "name": record.get("name", record["id"]), "kind": record["kind"]})
	return out


## Враг по символу: свой (мод) или встроенный в игру. Для призыва боссом.
func create_any(symbol: String, mod_id: String = "") -> Node2D:
	if has_symbol(symbol, mod_id):
		return create_entity(symbol, mod_id)
	var spawns := _spawn_table()
	if spawns.has(symbol):
		return (spawns[symbol] as PackedScene).instantiate() as Node2D
	return null


func _apply_common(node: Node2D, record: Dictionary) -> void:
	var def: Dictionary = record["def"]
	var sprite_spec: Dictionary = def.get("sprite", {})
	if record["script"] != null:
		node.set_script(record["script"])
	var sprite := node.get_node("Body/Sprite") as AnimatedSprite2D
	sprite.sprite_frames = record["frames"]
	sprite.animation = record["idle"]
	var scale := float(sprite_spec.get("scale", 1.0))
	sprite.scale = Vector2(scale, scale)
	sprite.offset = record["offset"]
	sprite.flip_h = bool(sprite_spec.get("faces_left", false))
	var body: Vector2 = record["body"]
	var shape := RectangleShape2D.new()
	shape.size = body
	var collision := node.get_node("CollisionShape2D") as CollisionShape2D
	collision.shape = shape
	collision.position = Vector2(0.0, -body.y / 2.0)
	var label := node.get_node("StateLabel") as Label
	label.offset_top = -body.y - 24.0
	label.offset_bottom = -body.y - 8.0


func _animation_name(record: Dictionary, role: String, fallbacks: Array) -> String:
	var def: Dictionary = record["def"]
	var names: Dictionary = def.get("animation_names", {})
	if names.has(role):
		return str(names[role])
	var frames: SpriteFrames = record["frames"]
	for candidate in [role] + fallbacks:
		if frames.has_animation(candidate):
			return candidate
	return role


## Присваивает число из JSON свойству, приводя его к типу свойства (JSON хранит все числа как дробные).
func _set_stat(node: Object, property: String, value) -> void:
	var current = node.get(property)
	if current is int and (value is float or value is int):
		node.set(property, int(value))
	elif current is float and (value is float or value is int):
		node.set(property, float(value))
	elif current is bool:
		node.set(property, bool(value))
	else:
		node.set(property, value)


func _make_enemy(record: Dictionary) -> Node2D:
	var node: Node2D = ENEMY_SCENE.instantiate()
	_apply_common(node, record)
	var def: Dictionary = record["def"]
	var stats: Dictionary = def.get("stats", {})
	for key in stats:
		if WALKER_STATS.has(key):
			_set_stat(node, WALKER_STATS[key], stats[key])
		else:
			push_warning("[мод %s] враг «%s»: неизвестный параметр stats.%s" % [record["mod"].id, record["id"], key])
	node.set("anim_idle", _animation_name(record, "idle", ["stand"]))
	node.set("anim_move", _animation_name(record, "move", ["run", "walk"]))
	node.set("anim_attack", _animation_name(record, "attack", ["strike", "hit"]))
	node.set("anim_throw", _animation_name(record, "throw", ["attack"]))
	node.set("anim_hurt", _animation_name(record, "hurt", ["hit", "take_hit", "damage"]))
	node.set("anim_death", _animation_name(record, "death", ["die", "dead"]))
	var dormant = def.get("dormant", null)
	if dormant is Dictionary:
		node.set("starts_dormant", true)
		node.set("wake_range_tiles", float(dormant.get("wake_range", 2.0)))
		node.set("wake_duration", float(dormant.get("wake_time", 0.9)))
		node.set("dormant_height", float(dormant.get("lying_height", 14.0)))
		node.set("anim_dormant", _animation_name(record, "closed", ["idle"]))
		node.set("anim_wake", _animation_name(record, "wake", ["idle"]))
	var throw = def.get("throw", null)
	if throw is Dictionary and record["throw_frames"] != null:
		node.set("throw_frames", record["throw_frames"])
		node.set("throw_damage", int(throw.get("damage", 12)))
		node.set("throw_cooldown", float(throw.get("cooldown", 3.0)))
		node.set("throw_min_range_tiles", float(throw.get("min_range", 3.0)))
		node.set("throw_max_range_tiles", float(throw.get("max_range", 7.0)))
		node.set("throw_duration", float(throw.get("duration", 0.6)))
		node.set("throw_release_time", float(throw.get("release_time", 0.35)))
		node.set("throw_explode_radius_tiles", float(throw.get("explode_radius", 1.2)))
		node.set("throw_scale", float(throw.get("scale", 1.0)))
	return node


func _make_boss(record: Dictionary) -> Node2D:
	var node: Node2D = BOSS_SCENE.instantiate()
	_apply_common(node, record)
	var def: Dictionary = record["def"]
	var stats: Dictionary = def.get("stats", {})
	node.set("boss_name", record["name"])
	node.set("power_reward", 0)  # у боссов награды нет, пока мод её не задаст
	node.set("corpse_time", 2.0)
	for key in stats:
		if BOSS_STATS.has(key):
			_set_stat(node, BOSS_STATS[key], stats[key])
		else:
			push_warning("[мод %s] босс «%s»: неизвестный параметр stats.%s" % [record["mod"].id, record["id"], key])
	node.set("anim_idle", _animation_name(record, "idle", ["stand"]))
	node.set("anim_walk", _animation_name(record, "walk", ["move", "run"]))
	node.set("anim_run", _animation_name(record, "run", ["move", "walk"]))
	node.set("anim_hurt", _animation_name(record, "hurt", ["hit", "take_hit", "damage"]))
	node.set("anim_death", _animation_name(record, "death", ["die", "dead"]))
	node.set("attacks", record["attacks"])
	node.set("summon_factory", Callable(self, "create_any").bind(record["mod"].id))
	return node


## Скрипт мода может добавить свой символ карты: factory() должен вернуть Node2D (врага, предмет).
func register_script_symbol(mod: ModInfo, symbol: String, factory: Callable) -> bool:
	var own: Dictionary = _symbols.get(mod.id, {})
	if symbol.length() != 1 or RESERVED_SYMBOLS.contains(symbol) or _builtin_spawns.has(symbol) or own.has(symbol):
		mod.problem("скрипт: символ «%s» недоступен" % symbol)
		return false
	own[symbol] = {"mod": mod, "kind": "script", "id": symbol, "factory": factory}
	_symbols[mod.id] = own
	return true


# =====================================================================================================
# Уровни из файлов мода
# =====================================================================================================

## Читает уровень (.txt или .json) в словарь с теми же ключами, что у констант встроенных уровней
## (TITLE, REQUIRE_CLEAR, THEME, MAP, WIN_BOSS, BOSS_LEASH, BOSS_ARENA, ZONES). {} — если файл негодный.
func parse_level(mod: ModInfo, rel: String) -> Dictionary:
	var text := mod.files.read_text(rel)
	var header := {}
	var rows: Array[String] = []
	if rel.get_extension().to_lower() == "json":
		var parsed = JSON.parse_string(text)
		if not parsed is Dictionary:
			mod.problem("%s: не читается как JSON" % rel)
			return {}
		header = parsed.duplicate()
		for row in parsed.get("map", []):
			rows.append(str(row))
		header.erase("map")
	else:
		var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
		var index := 0
		if lines.size() > 0 and RegEx.create_from_string("^[A-Za-z_]+\\s*:").search(lines[0]) != null:
			while index < lines.size() and lines[index].strip_edges() != "":
				var line := lines[index]
				var colon := line.find(":")
				header[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
				index += 1
			index += 1
		for i in range(index, lines.size()):
			rows.append(lines[i].trim_suffix("\n"))
		while not rows.is_empty() and rows[rows.size() - 1].strip_edges() == "":
			rows.pop_back()
	if rows.is_empty():
		mod.problem("%s: в уровне нет карты" % rel)
		return {}
	var width := 0
	for row in rows:
		width = maxi(width, row.length())
	if width > MAX_MAP_WIDTH or rows.size() > MAX_MAP_HEIGHT:
		mod.problem("%s: карта %dx%d слишком большая (не больше %dx%d)" % [rel, width, rows.size(), MAX_MAP_WIDTH, MAX_MAP_HEIGHT])
		return {}
	var players := 0
	var has_exit := false
	var has_boss := false
	var unknown := {}
	for row in rows:
		for ch in row:
			if ch == "P":
				players += 1
			elif ch == "E":
				has_exit = true
			elif _find(ch, mod.id) != null and _find(ch, mod.id)["kind"] == "boss":
				has_boss = true
			elif _builtin_spawns.has(ch) and "MNOWVBKZ".contains(ch):
				has_boss = true
			elif not ".#-^+ ".contains(ch) and not _builtin_spawns.has(ch) and _find(ch, mod.id) == null:
				unknown[ch] = true
	if players != 1:
		mod.problem("%s: на карте должен быть ровно один игрок P (найдено %d)" % [rel, players])
		return {}
	if not has_exit and not has_boss:
		mod.warn("%s: нет выхода E и боссов — уровень не пройти" % rel)
	if not unknown.is_empty():
		mod.warn("%s: неизвестные символы на карте: %s (будут пустыми)" % [rel, " ".join(unknown.keys())])
	var theme := str(header.get("theme", "grass"))
	var level_script: GDScript = load("res://scripts/level/level.gd")
	var themes: Dictionary = level_script.get_script_constant_map()["THEMES"]
	if not themes.has(theme):
		mod.warn("%s: тема «%s» неизвестна (есть: %s) — взята grass" % [rel, theme, ", ".join(themes.keys())])
		theme = "grass"
	var level := {
		"TITLE": str(header.get("title", rel.get_file().get_basename())),
		"REQUIRE_CLEAR": _truthy(header.get("require_clear", false)),
		"THEME": theme,
		"MAP": rows,
		"WIN_BOSS": str(header.get("win_boss", "")),
		"BOSS_LEASH": _truthy(header.get("boss_leash", false)),
		"BOSS_ARENA": _parse_arena(header.get("boss_arena", {})),
		"ZONES": _parse_zones(header.get("zones", []), themes, mod, rel),
		"MUSIC_PATH": str(header.get("music", "")),
		"MOD_ID": mod.id,
	}
	return level


func _truthy(value) -> bool:
	if value is bool:
		return value
	return ["yes", "true", "да", "1", "on"].has(str(value).strip_edges().to_lower())


func _parse_arena(value) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for key in value:
			out[str(key)] = float(value[key])
	else:
		for part in str(value).split(" ", false):
			var pair := part.split("=")
			if pair.size() == 2 and pair[0].length() == 1:
				out[pair[0]] = float(pair[1])
	return out


func _parse_zones(value, themes: Dictionary, mod: ModInfo, rel: String) -> Array:
	var out: Array = []
	var pairs: Array = []
	if value is Array:
		pairs = value
	else:
		for part in str(value).split(" ", false):
			var pair := part.split(":")
			if pair.size() == 2:
				pairs.append([int(pair[0]), pair[1]])
	for pair in pairs:
		if pair is Array and pair.size() >= 2:
			if themes.has(str(pair[1])):
				out.append([int(pair[0]), str(pair[1])])
			else:
				mod.warn("%s: тема зоны «%s» неизвестна" % [rel, pair[1]])
	out.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	return out


## Уровни кампании мода по порядку (словари для Game.level_data).
func campaign_levels(mod: ModInfo) -> Array:
	var out: Array = []
	if mod.has_campaign():
		for rel in mod.campaign["levels"]:
			out.append(mod.levels[rel])
	return out


## Музыка уровня мода (null — оставить обычную).
func level_music(level: Dictionary) -> AudioStream:
	var rel: String = level.get("MUSIC_PATH", "")
	if rel == "":
		return null
	var mod := get_mod(str(level.get("MOD_ID", "")))
	if mod == null:
		return null
	var stream := mod.files.load_audio(rel)
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	return stream


# =====================================================================================================
# Установка мода из файла или скачанных данных
# =====================================================================================================

## Устанавливает мод из .zip. Возвращает {"ok": bool, "message": String, "id": String}.
func install_zip_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "Файл не найден: " + path, "id": ""}
	return install_zip_bytes(FileAccess.get_file_as_bytes(path))


func install_zip_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_ZIP_BYTES:
		return {"ok": false, "message": "Архив слишком большой (больше 100 МБ).", "id": ""}
	var temp := user_mods_dir().path_join("_incoming.zip")
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Не удалось записать файл в папку модов.", "id": ""}
	file.store_buffer(bytes)
	file.close()
	var files := ModFiles.new(temp)
	var open_error := files.open()
	if open_error != "":
		DirAccess.remove_absolute(temp)
		return {"ok": false, "message": "Это не zip-архив мода (%s)." % open_error, "id": ""}
	var parsed = JSON.parse_string(files.read_text("mod.json"))
	files.close()
	if not parsed is Dictionary or RegEx.create_from_string(ID_PATTERN).search(str(parsed.get("id", ""))) == null:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "message": "В архиве нет правильного mod.json (нужен id латиницей).", "id": ""}
	var id := str(parsed["id"])
	var target := user_mods_dir().path_join(id + ".zip")
	var replaced := FileAccess.file_exists(target)
	_deactivate_all()  # закрыть открытые архивы: на Windows занятый файл не заменить
	if replaced:
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(temp, target) != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "message": "Не удалось сохранить мод в папку модов.", "id": id}
	rescan()
	var verb := "обновлён" if replaced else "установлен"
	var mod := get_mod(id)
	var note := ""
	if mod and mod.has_scripts():
		note = " Мод содержит скрипты — включите его вручную после проверки."
	return {"ok": true, "message": "Мод «%s» %s.%s" % [str(parsed.get("name", id)), verb, note], "id": id}


# =====================================================================================================
# Хуки для скриптов модов
# =====================================================================================================

func notify(method: StringName, args: Array = []) -> void:
	for node in _scripts:
		if is_instance_valid(node) and node.has_method(method):
			node.callv(method, args)


func has_scripts_active() -> bool:
	return not _scripts.is_empty()


func notify_level_started(level: Node) -> void:
	notify("_level_started", [level])


func notify_enemy_spawned(enemy: Node, symbol: String) -> void:
	if not _scripts.is_empty():
		notify("_enemy_spawned", [enemy, symbol])


func notify_player_spawned(player: Node) -> void:
	notify("_player_spawned", [player])


## Сохранённые данные мода (для скриптов): user://mod_data/<id>.json.
func save_mod_data(mod: ModInfo, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mod_data"))
	var file := FileAccess.open("user://mod_data/%s.json" % mod.id, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_mod_data(mod: ModInfo) -> Dictionary:
	var path := "user://mod_data/%s.json" % mod.id
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
