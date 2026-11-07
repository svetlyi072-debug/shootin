extends SceneTree
## Иконки для телефонов, из той же картинки, что и иконка игры (res://icon.png):
##   android-main-192.png   — обычный значок Android (192×192);
##   android-fg-432.png     — передний план «адаптивного» значка (Шуткин на прозрачном фоне, в центральных 288 px);
##   android-bg-432.png     — фон «адаптивного» значка (тот же фиолетовый градиент, на весь квадрат);
##   pwa-144.png, pwa-180.png, pwa-512.png — значки веб-приложения (добавление на главный экран).
## Запуск: godot --headless --path D:/shootin --script res://tools/export/make_mobile_icons.gd

const HERO := "res://assets/pixel_adventure/heroes/virtual_guy/idle.png"
const ICON := "res://icon.png"
const OUT_DIR := "res://tools/export/assets/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var icon := Image.load_from_file(ProjectSettings.globalize_path(ICON))
	for entry in [["android-main-192.png", 192], ["pwa-144.png", 144], ["pwa-180.png", 180], ["pwa-512.png", 512]]:
		var copy := icon.duplicate() as Image
		if copy.get_width() != entry[1]:
			copy.resize(entry[1], entry[1], Image.INTERPOLATE_LANCZOS)
		copy.save_png(ProjectSettings.globalize_path(OUT_DIR + entry[0]))

	var size := 432
	# Фон: градиент и мягкое свечение, как у иконки игры, но без скруглённых углов (форму вырежет Android).
	var back := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var base := Color(0.24, 0.17, 0.42).lerp(Color(0.07, 0.06, 0.15), float(y) / float(size - 1))
		for x in size:
			var d := Vector2(x - size * 0.5, y - size * 0.5).length() / (size * 0.5)
			var glow := clampf(1.0 - d, 0.0, 1.0)
			back.set_pixel(x, y, base.lerp(Color(0.62, 0.42, 0.9), glow * glow * 0.45))
	back.save_png(ProjectSettings.globalize_path(OUT_DIR + "android-bg-432.png"))

	# Передний план: герой и полоска земли под ним — всё в центральной части (Android обрезает края).
	var hero := Image.load_from_file(ProjectSettings.globalize_path(HERO))
	var frame := hero.get_region(Rect2i(0, 0, 32, 32))
	frame.convert(Image.FORMAT_RGBA8)
	var used := frame.get_used_rect()
	frame = frame.get_region(used)
	frame.resize(used.size.x * 8, used.size.y * 8, Image.INTERPOLATE_NEAREST)
	var front := Image.create(size, size, false, Image.FORMAT_RGBA8)
	front.fill(Color(0, 0, 0, 0))
	var feet := int(size * 0.70)
	front.fill_rect(Rect2i(int(size * 0.5) - 100, feet, 200, 8), Color(0.55, 0.85, 0.4))
	front.fill_rect(Rect2i(int(size * 0.5) - 100, feet + 8, 200, 22), Color(0.16, 0.11, 0.26))
	front.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((size - frame.get_width()) / 2, feet - frame.get_height() + 4))
	front.save_png(ProjectSettings.globalize_path(OUT_DIR + "android-fg-432.png"))
	print("значки для телефонов готовы")
	quit()
