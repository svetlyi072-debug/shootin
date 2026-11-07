extends SceneTree
## Режет сгенерированные нейросетью полосы анимации (design/source/*.webp) на кадры:
## убирает белый фон, уменьшает до размера игры и приводит цвета к палитре.
## Результат — полосы кадров assets/shellback/*.png (по 8 кадров в ряд).
## Запуск из папки проекта:
##   godot --headless --path . --script tools/slice_strips.gd
##
## Как это работает:
##   1. фон: заливка белого от краёв (внутри обводки белое остаётся — вспышка при ударе);
##      светлая «бахрома» по краю силуэта убирается;
##   2. каждая полоса делится на 8 равных ячеек, ячейка по ширине становится кадром;
##      по вертикали кадр выравнивается по самой нижней строке существа (ноги на земле);
##   3. уменьшение «по площади» (каждый пиксель кадра — среднее по блоку исходника),
##      полупрозрачные края отбрасываются: кадр получается чётким, без размытия;
##   4. цвета приводятся к палитре из самых частых цветов набора (убирает остаточное размытие).

const SRC := "res://design/source/"
const OUT := "res://assets/shellback/"
const CELLS := 8
## Сколько цветов оставить в палитре набора.
const PALETTE_SIZE := 30
## Цвета ближе этого (в долях от 1, по RGB) считаются одним цветом палитры.
const PALETTE_MIN_DISTANCE := 0.085
## Сколько редких ярких цветов добавить сверх палитры и насколько они должны отличаться от неё.
const PALETTE_EXTRAS := 14
const PALETTE_EXTRA_DISTANCE := 0.16

## Наборы: у каждого свой размер кадра, строка земли и полосы.
## align: "bottom" — по нижнему краю существа, "center" — по центру содержимого.
const SETS := {
	"shellback": {
		"frame": Vector2i(64, 64), "ground": 60,
		"strips": [
			{"src": "shellback_walk_hurt", "out": "shellback_walk_hurt", "align": "bottom"},
			{"src": "shellback_curl_roll", "out": "shellback_curl_roll", "align": "bottom"},
			{"src": "shellback_dizzy_death", "out": "shellback_dizzy_death", "align": "bottom"},
		],
	},
	"king": {
		"frame": Vector2i(64, 80), "ground": 76,
		"strips": [
			{"src": "king_idle_walk", "out": "king_idle_walk", "align": "bottom"},
			{"src": "king_windup_roll_stomp", "out": "king_windup_roll_stomp", "align": "bottom"},
			{"src": "king_dizzy_hurt_death", "out": "king_dizzy_hurt_death", "align": "bottom"},
		],
	},
	"fx": {
		"frame": Vector2i(64, 64), "ground": 60,
		"strips": [
			{"src": "fx_dust_rock", "out": "fx_dust_rock", "align": "mixed"},
		],
	},
}


func is_light(c: Color) -> bool:
	return c.r > 0.94 and c.g > 0.94 and c.b > 0.94


## Прозрачным делаем белый фон, связанный с краями картинки.
func remove_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while stack.size() > 0:
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if seen[i] == 1:
			continue
		var x := i % w
		var y := i / w
		var c := img.get_pixel(x, y)
		if c.a > 0.1 and not is_light(c):
			continue
		seen[i] = 1
		img.set_pixel(x, y, Color(1, 1, 1, 0))
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	# Светлая бахрома по краю (смесь обводки с белым фоном).
	for pass_index in 2:
		var kill := []
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var near_bg := img.get_pixel(x - 1, y).a < 0.5 or img.get_pixel(x + 1, y).a < 0.5 or img.get_pixel(x, y - 1).a < 0.5 or img.get_pixel(x, y + 1).a < 0.5
				if near_bg and c.r > 0.86 and c.g > 0.86 and c.b > 0.86 and (c.r + c.g + c.b) / 3.0 > 0.9 and pass_index == 0:
					kill.append(Vector2i(x, y))
		for p in kill:
			img.set_pixelv(p, Color(1, 1, 1, 0))


## Самая нижняя строка с заметным содержимым (не меньше 3 непрозрачных пикселей в строке).
func content_bottom(img: Image, x0: int, x1: int) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		var n := 0
		for x in range(x0, x1):
			if img.get_pixel(x, y).a > 0.5:
				n += 1
				if n >= 3:
					return y
	return 0


func content_rows(img: Image, x0: int, x1: int) -> Vector2i:
	var top := img.get_height()
	var bottom := 0
	for y in img.get_height():
		for x in range(x0, x1):
			if img.get_pixel(x, y).a > 0.5:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	return Vector2i(top, bottom)


## Уменьшение по площади: один пиксель кадра — среднее по блоку исходника
## (цвета взвешены по непрозрачности, чтобы белый фон не светился по краям).
func render_frame(img: Image, x0: float, src_ground: float, scale: float, frame: Vector2i, ground: int) -> Image:
	var out := Image.create(frame.x, frame.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var step := 1.0 / scale
	for oy in frame.y:
		var sy0 := src_ground + 1.0 - (ground - oy) * step
		var sy1 := sy0 + step
		for ox in frame.x:
			var sx0 := x0 + ox * step
			var sx1 := sx0 + step
			var sum := Color(0, 0, 0, 0)
			var weight := 0.0
			var alpha := 0.0
			var area := 0.0
			for sy in range(floori(sy0), ceili(sy1)):
				if sy < 0 or sy >= img.get_height():
					area += 1.0
					continue
				var wy := minf(sy + 1.0, sy1) - maxf(float(sy), sy0)
				for sx in range(floori(sx0), ceili(sx1)):
					var wx := minf(sx + 1.0, sx1) - maxf(float(sx), sx0)
					var wgt := wx * wy
					area += wgt
					if sx < 0 or sx >= img.get_width():
						continue
					var c := img.get_pixel(sx, sy)
					if c.a <= 0.0:
						continue
					alpha += c.a * wgt
					sum.r += c.r * c.a * wgt
					sum.g += c.g * c.a * wgt
					sum.b += c.b * c.a * wgt
					weight += c.a * wgt
			if area > 0.0 and alpha / area >= 0.5 and weight > 0.0:
				out.set_pixel(ox, oy, Color(sum.r / weight, sum.g / weight, sum.b / weight, 1.0))
	return out


func color_key(c: Color) -> int:
	return (int(c.r * 15.0 + 0.5) << 8) | (int(c.g * 15.0 + 0.5) << 4) | int(c.b * 15.0 + 0.5)


func key_color(k: int) -> Color:
	return Color(((k >> 8) & 15) / 15.0, ((k >> 4) & 15) / 15.0, (k & 15) / 15.0)


func color_distance(a: Color, b: Color) -> float:
	return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))


## Палитра из самых частых цветов набора; близкие цвета считаются одним.
func build_palette(frames: Array) -> Array:
	var counts := {}
	for frame in frames:
		var img: Image = frame
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var k := color_key(c)
				counts[k] = counts.get(k, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var palette := []
	for k in keys:
		var c := key_color(k)
		var close := false
		for p in palette:
			if color_distance(c, p) < PALETTE_MIN_DISTANCE:
				close = true
				break
		if not close:
			palette.append(c)
			if palette.size() >= PALETTE_SIZE:
				break
	# Редкие, но яркие и заметные цвета (жёлтый глаз, золото кристаллов, искры, синие камешки):
	# добавляем, если они далеко от всех уже выбранных.
	var extras := 0
	for k in keys:
		if counts[k] < 4 or extras >= PALETTE_EXTRAS:
			continue
		var c := key_color(k)
		var far := true
		for p in palette:
			if color_distance(c, p) < PALETTE_EXTRA_DISTANCE:
				far = false
				break
		if far:
			palette.append(c)
			extras += 1
	return palette


func snap_to_palette(img: Image, palette: Array) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var best: Color = palette[0]
			var best_d := 99.0
			for p in palette:
				var d := color_distance(c, p)
				if d < best_d:
					best_d = d
					best = p
			img.set_pixel(x, y, Color(best.r, best.g, best.b, 1.0))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ok := true
	for set_name in SETS:
		var set: Dictionary = SETS[set_name]
		var frame: Vector2i = set["frame"]
		var ground: int = set["ground"]
		var rendered := []  # [Image кадр, индекс полосы]
		var strips: Array = set["strips"]
		for si in strips.size():
			var strip: Dictionary = strips[si]
			var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + strip["src"] + ".webp"))
			if img == null:
				push_error("нет картинки " + strip["src"])
				ok = false
				continue
			img.convert(Image.FORMAT_RGBA8)
			remove_background(img)
			var cell := img.get_width() / float(CELLS)
			var scale := frame.x / cell
			for i in CELLS:
				var x0 := cell * i
				var xi0 := floori(x0)
				var xi1 := mini(floori(x0 + cell), img.get_width())
				var align: String = strip["align"]
				var src_ground := float(content_bottom(img, xi0, xi1))
				if align == "mixed" and i >= 4:
					# Камень парит: выравниваем по центру содержимого.
					var rows := content_rows(img, xi0, xi1)
					var mid := (rows.x + rows.y) / 2.0
					src_ground = mid + (frame.y / 2.0 - ground) / scale + (ground - frame.y / 2.0) / scale * 0.0
					src_ground = mid + (ground - frame.y / 2.0) / scale
				var piece := render_frame(img, x0, src_ground, scale, frame, ground)
				rendered.append([piece, si])
		var palette := build_palette(rendered.map(func(r): return r[0]))
		print("%s: палитра из %d цветов" % [set_name, palette.size()])
		for r in rendered:
			snap_to_palette(r[0], palette)
		# Сборка полос.
		for si in strips.size():
			var sheet := Image.create(frame.x * CELLS, frame.y, false, Image.FORMAT_RGBA8)
			sheet.fill(Color(0, 0, 0, 0))
			var n := 0
			for r in rendered:
				if r[1] == si:
					sheet.blit_rect(r[0], Rect2i(0, 0, frame.x, frame.y), Vector2i(n * frame.x, 0))
					n += 1
			var path: String = OUT + String(strips[si]["out"]) + ".png"
			var err := sheet.save_png(ProjectSettings.globalize_path(path))
			print("  %s: %d кадров, %s" % [path, n, "ok" if err == OK else "ошибка %d" % err])
			ok = ok and err == OK
	quit(0 if ok else 1)
