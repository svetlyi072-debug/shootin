class_name ModInfo
extends RefCounted
## Один мод: описание из mod.json, его файлы, состояние (включён/выключен) и ошибки.

## API 2: настройки мода (settings в mod.json), правила забега для скриптов
## (lock_difficulty, set_permadeath) и require_clear_all() у уровня.
const API_VERSION := 2

var id := ""
var title := ""
var version := ""
var author := ""
var description := ""
var api := 1
var path := ""
var files: ModFiles
var manifest := {}
## Включён ли мод игроком; активен ли он реально (включён и без фатальных ошибок).
var enabled := false
var active := false
## Фатальные ошибки (мод нельзя подключить: нет mod.json, плохой id, слишком новый api).
var errors: Array[String] = []
## Проблемы содержимого (сломанный враг, уровень, скрипт): такая часть пропускается, мод работает.
var problems: Array[String] = []
var warnings: Array[String] = []
## Какие скрипты (.gd) есть в моде: относительные пути.
var script_files: Array[String] = []
## Определения из файлов мода: id → словарь.
var enemies := {}
var bosses := {}
## Уровни мода: относительный путь → нормализованный словарь уровня (см. Mods.parse_level).
var levels := {}
## Кампания: {"title": ..., "levels": [относительные пути]} или пустой словарь.
var campaign := {}
## Настройки мода из mod.json (проверенные): список словарей {id, type, title, description, default,
## options | min, max, step}. Значения, выбранные игроком, хранит Mods (get_setting).
var settings: Array = []


func has_scripts() -> bool:
	return not script_files.is_empty()


func has_campaign() -> bool:
	return not campaign.is_empty() and not campaign.get("levels", []).is_empty()


func ok() -> bool:
	return errors.is_empty()


## Короткое описание для списка: «Название 1.0 · Автор».
func label() -> String:
	var text := title if title != "" else id
	if version != "":
		text += " " + version
	if author != "":
		text += " · " + author
	return text


func error(text: String) -> void:
	errors.append(text)
	push_warning("[мод %s] %s" % [id if id != "" else path.get_file(), text])


func problem(text: String) -> void:
	problems.append(text)
	push_warning("[мод %s] %s" % [id if id != "" else path.get_file(), text])


func warn(text: String) -> void:
	warnings.append(text)
