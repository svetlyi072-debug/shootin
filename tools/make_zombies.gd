extends SceneTree
## Делает зомби из CC0-спрайтов LuizMelo (те же руки, что нарисовали скелета, гоблина и грибника в игре):
##   design/source/luizmelo/medieval_king_2/  Medieval King Pack 2 → зомби, могильные зомби, Король зомби
##   design/source/luizmelo/hero_knight/      Hero Knight          → ржавый рыцарь-мертвец
## Листы перекрашиваются и кладутся в assets/zombie/. Кадры «смерти» проигрываются задом наперёд —
## так зомби вылезает из могилы (в build_sprite_frames.gd).
## Запуск из папки проекта:
##   godot --headless --path . --script tools/make_zombies.gd
## Правила перекраски — в функциях recolor_*(); поправьте и запустите ещё раз.

const SRC := "res://design/source/luizmelo/"
const OUT := "res://assets/zombie/"

## Листы: [папка, файл-источник, имя результата, вид перекраски].
##   zombie — обычный зомби (тело короля без короны, зелёная кожа, рваная серо-бурая одежда);
##   grave  — могильный зомби (бледнее, одежда сине-серая): вылезает из земли;
##   knight — ржавый рыцарь-мертвец (броня с зеленцой, кровавый шарф);
##   king   — Король зомби: золотая корона, зелёный плащ, фиолетовая одежда.
const JOBS := [
	["medieval_king_2", "Idle", "zombie_idle", "zombie"],
	["medieval_king_2", "Run", "zombie_run", "zombie"],
	["medieval_king_2", "Attack1", "zombie_attack", "zombie"],
	["medieval_king_2", "Take Hit", "zombie_hit", "zombie"],
	["medieval_king_2", "Death", "zombie_death", "zombie"],
	["medieval_king_2", "Idle", "grave_idle", "grave"],
	["medieval_king_2", "Run", "grave_run", "grave"],
	["medieval_king_2", "Attack2", "grave_attack", "grave"],
	["medieval_king_2", "Take Hit", "grave_hit", "grave"],
	["medieval_king_2", "Death", "grave_death", "grave"],
	["hero_knight", "Idle", "knight_idle", "knight"],
	["hero_knight", "Run", "knight_run", "knight"],
	["hero_knight", "Attack1", "knight_attack", "knight"],
	["hero_knight", "Attack2", "knight_attack2", "knight"],
	["hero_knight", "Take Hit", "knight_hit", "knight"],
	["hero_knight", "Death", "knight_death", "knight"],
	["medieval_king_2", "Idle", "king_idle", "king"],
	["medieval_king_2", "Run", "king_run", "king"],
	["medieval_king_2", "Attack1", "king_attack", "king"],
	["medieval_king_2", "Attack2", "king_attack2", "king"],
	["medieval_king_2", "Attack3", "king_attack3", "king"],
	["medieval_king_2", "Take Hit", "king_hit", "king"],
	["medieval_king_2", "Death", "king_death", "king"],
	["medieval_king_2", "Jump", "king_jump", "king"],
	["medieval_king_2", "Fall", "king_fall", "king"],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := false
	for job in JOBS:
		var path: String = SRC + job[0] + "/" + job[1] + ".png"
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			push_error("нет картинки " + path)
			failed = true
			continue
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					img.set_pixel(x, y, recolor(c, job[3]))
		var out_path := ProjectSettings.globalize_path(OUT + job[2] + ".png")
		var err := img.save_png(out_path)
		print("%s: %s" % [job[2], "ok" if err == OK else "ошибка %d" % err])
		failed = failed or err != OK
	quit(1 if failed else 0)


func recolor(c: Color, kind: String) -> Color:
	match kind:
		"zombie":
			return recolor_zombie(c, false)
		"grave":
			return recolor_zombie(c, true)
		"knight":
			return recolor_knight(c)
		"king":
			return recolor_king(c)
	return c


## Тело короля → простой зомби. Зелёная кожа и борода-плесень, корона и пряжка ржавеют,
## красная куртка и синий плащ — грязные лохмотья. pale — могильный вариант
## (бледная кожа, сине-серая одежда), чтобы два вида зомби не сливались.
func recolor_zombie(c: Color, pale: bool) -> Color:
	var h := c.h
	var s := c.s
	var v := c.v
	var out: Color
	if s < 0.16:
		out = Color.from_hsv(0.22, 0.14 + s * 0.4, clampf(v * 0.82, 0.0, 1.0))
	elif h < 0.04 or h > 0.92:
		# Тёмно-красная куртка.
		out = Color.from_hsv(0.58, 0.28, v * 0.95) if pale else Color.from_hsv(0.09, 0.38, clampf(v * 0.9 + 0.04, 0.0, 1.0))
	elif h < 0.1:
		# Кожа и борода.
		out = Color.from_hsv(0.2 if pale else 0.25, 0.3 if pale else 0.5, clampf(v * 0.95 + 0.05, 0.0, 1.0))
	elif h < 0.2:
		# Золото (корона, пряжка) → ржавчина.
		out = Color.from_hsv(0.07, clampf(s * 0.55, 0.0, 0.6), v * 0.5)
	elif h > 0.45 and h < 0.8:
		# Синий плащ и штаны.
		out = Color.from_hsv(0.5 if pale else 0.1, 0.3 if pale else 0.22, v * 0.7)
	else:
		out = Color.from_hsv(0.28, clampf(s * 0.7, 0.0, 0.6), v * 0.9)
	return Color(out.r, out.g, out.b, c.a)


## Hero Knight → ржавый рыцарь-мертвец: броня оливковая, шарф — кровавый, всё чуть темнее.
func recolor_knight(c: Color) -> Color:
	var h := c.h
	var s := c.s
	var v := c.v
	var out: Color
	if s < 0.16 or (h > 0.45 and h < 0.8):
		out = Color.from_hsv(0.2, 0.26 + s * 0.3, clampf(v * 0.88, 0.0, 1.0))
	elif h < 0.06 or h > 0.9:
		out = Color.from_hsv(0.0, clampf(s * 0.9, 0.0, 0.9), v * 0.7)
	else:
		out = Color.from_hsv(0.25, clampf(s * 0.7, 0.0, 0.6), v * 0.9)
	return Color(out.r, out.g, out.b, c.a)


## Король зомби: корона остаётся золотой, плащ — зелёный, одежда — фиолетовая, кожа — зелёная.
func recolor_king(c: Color) -> Color:
	var h := c.h
	var s := c.s
	var v := c.v
	var out: Color
	if s < 0.16:
		out = Color.from_hsv(0.30, 0.2 + s * 0.4, clampf(v * 0.92, 0.0, 1.0))
	elif h < 0.04 or h > 0.92:
		out = Color.from_hsv(0.82, clampf(s * 0.55, 0.0, 0.6), v * 0.85)
	elif h < 0.1:
		out = Color.from_hsv(0.24, clampf(0.35 + s * 0.25, 0.0, 0.7), clampf(v * 0.95 + 0.05, 0.0, 1.0))
	elif h < 0.2:
		out = Color.from_hsv(0.12, clampf(s * 0.9, 0.0, 0.85), v * 0.95)
	elif h > 0.45 and h < 0.8:
		out = Color.from_hsv(0.38, clampf(s * 0.55, 0.0, 0.6), v * 0.78)
	else:
		out = Color.from_hsv(0.28, clampf(s * 0.7, 0.0, 0.6), v * 0.9)
	return Color(out.r, out.g, out.b, c.a)
