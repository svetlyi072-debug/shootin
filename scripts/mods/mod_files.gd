class_name ModFiles
extends RefCounted
## Файлы одного мода: папка на диске или .zip-архив. Читаются напрямую (zip распаковывать не надо).
## Пути внутри мода — относительные, с «/» (например "sprites/ghoul.png"); выход за пределы
## мода («..», абсолютные пути) запрещён.

var root := ""
var is_zip := false
var _zip: ZIPReader
## Если в архиве всё лежит внутри одной папки-обёртки («МойМод/mod.json»), её имя — здесь.
var _prefix := ""
var _zip_names := {}  # относительный путь → полный путь в архиве


func _init(path: String) -> void:
	root = path
	is_zip = path.get_extension().to_lower() == "zip"


## Открывает мод. Возвращает пустую строку или текст ошибки.
func open() -> String:
	if not is_zip:
		return "" if DirAccess.dir_exists_absolute(root) else "папка не найдена: " + root
	_zip = ZIPReader.new()
	var err := _zip.open(root)
	if err != OK:
		return "не удалось открыть архив (код %d): %s" % [err, root]
	var names := _zip.get_files()
	# Если mod.json не в корне, ищем его на один уровень глубже (папка-обёртка).
	if not names.has("mod.json"):
		for name in names:
			if name.ends_with("/mod.json") and name.count("/") == 1:
				_prefix = name.get_base_dir() + "/"
				break
	for name in names:
		if name.ends_with("/"):
			continue
		if _prefix != "" and not name.begins_with(_prefix):
			continue
		_zip_names[name.trim_prefix(_prefix)] = name
	return ""


func close() -> void:
	if _zip:
		_zip.close()
		_zip = null


## Безопасный относительный путь или "" (если путь выходит за пределы мода).
static func clean(rel: String) -> String:
	var path := rel.replace("\\", "/").strip_edges()
	while path.begins_with("./"):
		path = path.substr(2)
	if path == "" or path.begins_with("/") or path.contains(":") or path.contains("//"):
		return ""
	for part in path.split("/"):
		if part == ".." or part == "":
			return ""
	return path


func exists(rel: String) -> bool:
	var path := clean(rel)
	if path == "":
		return false
	if is_zip:
		return _zip_names.has(path)
	return FileAccess.file_exists(root.path_join(path))


func read_bytes(rel: String) -> PackedByteArray:
	var path := clean(rel)
	if path == "" or not exists(path):
		return PackedByteArray()
	if is_zip:
		return _zip.read_file(_zip_names[path])
	return FileAccess.get_file_as_bytes(root.path_join(path))


func read_text(rel: String) -> String:
	var bytes := read_bytes(rel)
	var text := bytes.get_string_from_utf8()
	# BOM из «Блокнота». Сравниваем по коду символа, а не со строкой "﻿": в собранной игре такая
	# строка-константа превращалась в пустую (при чтении BOM отбрасывается), begins_with("") всегда
	# истинно, и у каждого файла мода отрезался первый знак — моды не устанавливались.
	if text.length() > 0 and text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	return text


## Файлы папки dir (без вложенных) с нужными расширениями, по алфавиту. Пути — от корня мода.
func list_files(dir: String, extensions: Array = []) -> PackedStringArray:
	var out := PackedStringArray()
	var base := clean(dir) if dir != "" else ""
	if is_zip:
		var prefix := base + "/" if base != "" else ""
		for name in _zip_names:
			if not name.begins_with(prefix):
				continue
			var rest: String = name.substr(prefix.length())
			if rest.contains("/") or not _ext_ok(rest, extensions):
				continue
			out.append(name)
	else:
		var path := root.path_join(base) if base != "" else root
		if not DirAccess.dir_exists_absolute(path):
			return out
		for file in DirAccess.get_files_at(path):
			if _ext_ok(file, extensions):
				out.append((base + "/" + file) if base != "" else file)
	out.sort()
	return out


func _ext_ok(file: String, extensions: Array) -> bool:
	return extensions.is_empty() or extensions.has(file.get_extension().to_lower())


## Картинка из мода (png, webp, jpg). null, если файла нет или он повреждён.
func load_image(rel: String) -> Image:
	var bytes := read_bytes(rel)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match rel.get_extension().to_lower():
		"png":
			err = image.load_png_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(bytes)
	return image if err == OK else null


func load_texture(rel: String) -> Texture2D:
	var image := load_image(rel)
	return ImageTexture.create_from_image(image) if image else null


## Звук из мода: ogg или mp3. null, если файла нет или формат не поддерживается.
func load_audio(rel: String) -> AudioStream:
	var bytes := read_bytes(rel)
	if bytes.is_empty():
		return null
	match rel.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = bytes
			return stream
	return null
