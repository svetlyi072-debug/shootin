class_name ModSprites
extends RefCounted
## Сборка анимаций из картинок мода. Анимация — полоса кадров: один PNG, кадры подряд слева направо.
##
## Описание спрайта (в JSON врага, босса или снаряда):
##   {
##     "frame": [160, 111],            // размер одного кадра (можно задать и у каждой анимации)
##     "fps": 8,                       // скорость по умолчанию
##     "scale": 1.2,                   // во сколько раз увеличить (по умолчанию 1)
##     "offset": [0, -49.5],           // сдвиг картинки (по умолчанию считается сам: ноги на земле)
##     "animations": {
##       "idle": "sprites/idle.png",   // короткая запись: только файл
##       "attack": {"file": "sprites/attack.png", "fps": 12, "loop": false,
##                  "first": 0, "count": 4, "reverse": false, "frame": [160, 111]}
##     }
##   }
## Названия анимаций у каждого вида персонажа свои (см. MODDING.md).

## Анимации, которые по умолчанию повторяются по кругу.
const LOOPING := ["idle", "move", "walk", "run", "fly", "flight", "closed", "windup", "charge", "summon"]
## Встроенные снаряды игры, которые можно указать по имени вместо своего спрайта.
const BUILTIN_PROJECTILES := ["fireball", "bolt", "spore", "bomb", "sword"]

static var _textures := {}  # "мод|файл" → Texture2D


## Собирает SpriteFrames. Ошибки дописывает в errors (массив строк); при фатальной — null.
static func build_frames(mod: ModInfo, spec: Dictionary, errors: Array) -> SpriteFrames:
	var animations = spec.get("animations", {})
	if not animations is Dictionary or animations.is_empty():
		errors.append("у спрайта нет анимаций (поле animations)")
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var default_frame := _vec2i(spec.get("frame", null))
	var default_fps := float(spec.get("fps", 8.0))
	for anim_name in animations:
		var entry = animations[anim_name]
		if entry is String:
			entry = {"file": entry}
		if not entry is Dictionary:
			errors.append("анимация «%s»: ожидалось имя файла или объект" % anim_name)
			continue
		var file := str(entry.get("file", ""))
		var sheet := _texture(mod, file)
		if sheet == null:
			errors.append("анимация «%s»: не удалось загрузить картинку «%s»" % [anim_name, file])
			continue
		var frame := _vec2i(entry.get("frame", null))
		if frame == Vector2i.ZERO:
			frame = default_frame
		if frame == Vector2i.ZERO:
			frame = Vector2i(sheet.get_height(), sheet.get_height())  # кадры квадратные по умолчанию
		if frame.x <= 0 or frame.y <= 0 or frame.y > sheet.get_height():
			errors.append("анимация «%s»: неверный размер кадра %s (картинка %dx%d)" % [anim_name, frame, sheet.get_width(), sheet.get_height()])
			continue
		var total := sheet.get_width() / frame.x
		if total < 1:
			errors.append("анимация «%s»: картинка уже одного кадра" % anim_name)
			continue
		var first := clampi(int(entry.get("first", 0)), 0, total - 1)
		var count := int(entry.get("count", total - first))
		count = clampi(count, 1, total - first)
		var order := range(first, first + count)
		if entry.get("reverse", false):
			order.reverse()
		var anim := str(anim_name)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, maxf(float(entry.get("fps", default_fps)), 1.0))
		frames.set_animation_loop(anim, bool(entry.get("loop", LOOPING.has(anim))))
		for i in order:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * frame.x, 0, frame.x, frame.y)
			frames.add_frame(anim, atlas)
	if frames.get_animation_names().is_empty():
		errors.append("ни одна анимация не загрузилась")
		return null
	return frames


## Встроенный снаряд по имени или собранный из описания мода ({"fly": ..., "explode": ...}).
static func projectile_frames(mod: ModInfo, spec, errors: Array) -> SpriteFrames:
	if spec == null or (spec is String and spec == ""):
		spec = "fireball"
	if spec is String:
		if not BUILTIN_PROJECTILES.has(spec):
			errors.append("неизвестный встроенный снаряд «%s» (есть: %s)" % [spec, ", ".join(BUILTIN_PROJECTILES)])
			spec = "fireball"
		return load("res://assets/frames/%s.tres" % spec)
	if spec is Dictionary:
		var wrapped: Dictionary = spec if spec.has("animations") else {"animations": spec, "frame": spec.get("frame", null), "fps": spec.get("fps", 10)}
		var frames := build_frames(mod, wrapped, errors)
		if frames and not frames.has_animation("fly"):
			errors.append("у снаряда нет анимации «fly»")
			return null
		if frames and not frames.has_animation("explode"):
			# Без взрыва снаряд просто исчезнет: добавим пустой кадр.
			frames.add_animation("explode")
			frames.set_animation_loop("explode", false)
			frames.add_frame("explode", frames.get_frame_texture("fly", 0))
		return frames
	errors.append("снаряд: ожидалось имя встроенного снаряда или описание")
	return null


## Размеры персонажа по первому кадру анимации: низ ног, середина по горизонтали, ширина, высота
## (всё в пикселях кадра) — по этим числам считается сдвиг спрайта и размер тела.
static func measure(frames: SpriteFrames, anim: String) -> Dictionary:
	if not frames.has_animation(anim) or frames.get_frame_count(anim) == 0:
		return {}
	var texture := frames.get_frame_texture(anim, 0) as AtlasTexture
	if texture == null:
		return {}
	var image := texture.atlas.get_image()
	if image == null:
		return {}
	image.convert(Image.FORMAT_RGBA8)
	var region := texture.region
	var cell := image.get_region(Rect2i(region))
	var used := cell.get_used_rect()
	if used.size == Vector2i.ZERO:
		return {}
	return {
		"frame": Vector2(region.size),
		"bottom": float(used.position.y + used.size.y),
		"center_x": used.position.x + used.size.x / 2.0,
		"width": float(used.size.x),
		"height": float(used.size.y),
	}


## Сдвиг спрайта, чтобы ноги стояли на земле, а тело — по центру узла.
static func auto_offset(measured: Dictionary) -> Vector2:
	if measured.is_empty():
		return Vector2.ZERO
	var frame: Vector2 = measured["frame"]
	return Vector2(-(measured["center_x"] - frame.x / 2.0), frame.y / 2.0 - measured["bottom"])


static func _texture(mod: ModInfo, file: String) -> Texture2D:
	var key := "%s|%s" % [mod.path, file]
	if _textures.has(key):
		return _textures[key]
	var texture := mod.files.load_texture(file)
	if texture:
		_textures[key] = texture
	return texture


static func clear_cache() -> void:
	_textures.clear()


static func _vec2i(value) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
