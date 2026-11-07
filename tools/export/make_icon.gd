extends SceneTree
## Рисует иконку игры (Шуткин на тёмном фоне) и собирает из неё:
##   res://icon.png                      — иконка проекта (512×512);
##   tools/export/assets/icon.ico        — иконка для exe и установщика Windows (16…256 px);
##   tools/export/assets/icon-256.png    — иконка для Linux (.desktop) и справки.
## Запуск: godot --headless --path D:/shootin --script res://tools/export/make_icon.gd

const HERO := "res://assets/pixel_adventure/heroes/virtual_guy/idle.png"
const OUT_DIR := "res://tools/export/assets/"
const SIZES := [16, 24, 32, 48, 64, 128, 256]


func _initialize() -> void:
	var hero := Image.load_from_file(ProjectSettings.globalize_path(HERO))
	var frame := hero.get_region(Rect2i(0, 0, 32, 32))
	frame.convert(Image.FORMAT_RGBA8)
	var used := frame.get_used_rect()
	frame = frame.get_region(used)
	var scale := 11
	frame.resize(used.size.x * scale, used.size.y * scale, Image.INTERPOLATE_NEAREST)

	var size := 512
	var icon := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var radius := 96.0
	for y in size:
		var t := float(y) / float(size - 1)
		var top := Color(0.24, 0.17, 0.42)
		var bottom := Color(0.07, 0.06, 0.15)
		var base := top.lerp(bottom, t)
		for x in size:
			# Мягкое свечение за героем.
			var d := Vector2(x - size * 0.5, y - size * 0.52).length() / (size * 0.5)
			var glow := clampf(1.0 - d, 0.0, 1.0)
			var color := base.lerp(Color(0.62, 0.42, 0.9), glow * glow * 0.45)
			color.a = _corner_alpha(x, y, size, radius)
			icon.set_pixel(x, y, color)
	# Земля под героем.
	var ground_top := int(size * 0.80)
	for y in range(ground_top, size):
		for x in size:
			var c := icon.get_pixel(x, y)
			if c.a > 0.0:
				var shade := Color(0.16, 0.11, 0.26) if y > ground_top + 6 else Color(0.55, 0.85, 0.4)
				icon.set_pixel(x, y, Color(shade.r, shade.g, shade.b, c.a))
	# Герой стоит на земле по центру.
	var pos := Vector2i((size - frame.get_width()) / 2, ground_top - frame.get_height() + 4)
	icon.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), pos)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	icon.save_png(ProjectSettings.globalize_path("res://icon.png"))
	var png_bytes := {}
	for s in SIZES:
		var copy := icon.duplicate() as Image
		copy.resize(s, s, Image.INTERPOLATE_LANCZOS)
		png_bytes[s] = copy.save_png_to_buffer()
		if s == 256:
			copy.save_png(ProjectSettings.globalize_path(OUT_DIR + "icon-256.png"))
	_write_ico(png_bytes)
	print("иконки готовы")
	quit()


func _corner_alpha(x: int, y: int, size: int, radius: float) -> float:
	var cx := clampf(float(x) + 0.5, radius, size - radius)
	var cy := clampf(float(y) + 0.5, radius, size - radius)
	var dist := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length()
	return clampf(radius - dist + 0.5, 0.0, 1.0)


func _write_ico(png_bytes: Dictionary) -> void:
	var sizes: Array = png_bytes.keys()
	sizes.sort()
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_u16(0)
	buffer.put_u16(1)
	buffer.put_u16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for s in sizes:
		var data: PackedByteArray = png_bytes[s]
		buffer.put_u8(0 if s >= 256 else s)
		buffer.put_u8(0 if s >= 256 else s)
		buffer.put_u8(0)
		buffer.put_u8(0)
		buffer.put_u16(1)
		buffer.put_u16(32)
		buffer.put_u32(data.size())
		buffer.put_u32(offset)
		offset += data.size()
	for s in sizes:
		buffer.put_data(png_bytes[s])
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "icon.ico"), FileAccess.WRITE)
	file.store_buffer(buffer.data_array)
	file.close()
