extends SceneTree
## Собирает SpriteFrames-ресурсы (assets/frames/*.tres) из листов кадров в assets/.
## Запуск из папки проекта (после того как Godot импортировал картинки):
##   godot --headless --path . --script tools/build_sprite_frames.gd
## Готовые .tres можно открыть и поправить в редакторе (панель SpriteFrames).

const OUT := "res://assets/frames/"
const PA := "res://assets/pixel_adventure/"
const TRAPS := PA + "traps/"
const SB := "res://assets/shellback/"
const MCF := "res://assets/monsters_creatures_fantasy/"
const MCF2 := "res://assets/monsters_creatures_fantasy_2/"
const WORM := "res://assets/fire_worm/"
const WIZ := "res://assets/evil_wizard_2/"
## Зомби: перекрашены из спрайтов LuizMelo (tools/make_zombies.gd).
const ZB := "res://assets/zombie/"

## Шуткин. Чтобы сменить героя, поменяйте папку: virtual_guy / ninja_frog / mask_dude / pink_man.
const HERO := PA + "heroes/virtual_guy/"


## Кадры из листа: ширина и высота кадра, с какого кадра и сколько (-1 — до конца).
func strip(path: String, frame_w: int, frame_h: int, first := 0, count := -1) -> Array:
	return ["strip", path, frame_w, frame_h, first, count]


## Те же кадры, но задом наперёд (смерть наоборот — зомби вылезает из земли).
func strip_rev(path: String, frame_w: int, frame_h: int, first := 0, count := -1) -> Array:
	return ["strip_rev", path, frame_w, frame_h, first, count]


## Отдельный файл на каждый кадр: шаблон пути с %d и число кадров.
func files(pattern: String, count: int) -> Array:
	return ["files", pattern, count]


## Анимация: кадров в секунду, зацикливать ли, источники (склеиваются по порядку).
func anim(fps: float, loop: bool, sources: Array) -> Dictionary:
	return {"fps": fps, "loop": loop, "sources": sources}


func sets() -> Dictionary:
	return {
		"player": {
			"idle": anim(20, true, [strip(HERO + "idle.png", 32, 32)]),
			"run": anim(20, true, [strip(HERO + "run.png", 32, 32)]),
			"jump": anim(20, true, [strip(HERO + "jump.png", 32, 32)]),
			"fall": anim(20, true, [strip(HERO + "fall.png", 32, 32)]),
			"hit": anim(20, false, [strip(HERO + "hit.png", 32, 32)]),
			"double_jump": anim(20, true, [strip(HERO + "double_jump.png", 32, 32)]),
			"wall_jump": anim(20, true, [strip(HERO + "wall_jump.png", 32, 32)]),
		},
		"slime": {
			"idle": anim(8, true, [files("res://assets/slime/idle_%d.png", 4)]),
			"move": anim(8, true, [files("res://assets/slime/move_%d.png", 4)]),
			"attack": anim(14, false, [files("res://assets/slime/attack_%d.png", 5)]),
			"hurt": anim(14, false, [files("res://assets/slime/hurt_%d.png", 4)]),
			"die": anim(8, false, [files("res://assets/slime/die_%d.png", 4)]),
		},
		"skeleton": {
			"idle": anim(6, true, [strip(MCF + "skeleton/idle.png", 150, 150)]),
			"walk": anim(8, true, [strip(MCF + "skeleton/walk.png", 150, 150)]),
			"attack": anim(20, false, [strip(MCF + "skeleton/attack.png", 150, 150)]),
			"attack2": anim(16, false, [strip(MCF + "skeleton/attack2.png", 150, 150)]),
			"throw": anim(12, false, [strip(MCF + "skeleton/attack3.png", 150, 150)]),
			"take_hit": anim(14, false, [strip(MCF + "skeleton/take_hit.png", 150, 150)]),
			"death": anim(8, false, [strip(MCF + "skeleton/death.png", 150, 150)]),
			"shield": anim(10, false, [strip(MCF + "skeleton/shield.png", 150, 150)]),
		},
		"flying_eye": {
			"flight": anim(14, true, [strip(MCF + "flying_eye/flight.png", 150, 150)]),
			"attack": anim(20, false, [strip(MCF + "flying_eye/attack.png", 150, 150)]),
			"attack2": anim(16, false, [strip(MCF + "flying_eye/attack2.png", 150, 150)]),
			"cast": anim(12, false, [strip(MCF + "flying_eye/attack3.png", 150, 150)]),
			"take_hit": anim(14, false, [strip(MCF + "flying_eye/take_hit.png", 150, 150)]),
			"death": anim(8, false, [strip(MCF + "flying_eye/death.png", 150, 150)]),
		},
		"bat": {
			"fly": anim(14, true, [strip(MCF2 + "bat/fly.png", 87, 87)]),
			"attack": anim(26, false, [strip(MCF2 + "bat/attack.png", 87, 87)]),
			"hurt": anim(12, false, [strip(MCF2 + "bat/hurt.png", 87, 87)]),
			"death": anim(10, false, [strip(MCF2 + "bat/fly_to_fall.png", 87, 87), strip(MCF2 + "bat/fall.png", 87, 87)]),
		},
		"goblin": {
			"idle": anim(6, true, [strip(MCF + "goblin/idle.png", 150, 150)]),
			"run": anim(12, true, [strip(MCF + "goblin/run.png", 150, 150)]),
			"attack": anim(16, false, [strip(MCF + "goblin/attack.png", 150, 150)]),
			"attack2": anim(16, false, [strip(MCF + "goblin/attack2.png", 150, 150)]),
			"throw": anim(20, false, [strip(MCF + "goblin/attack3.png", 150, 150)]),
			"take_hit": anim(14, false, [strip(MCF + "goblin/take_hit.png", 150, 150)]),
			"death": anim(8, false, [strip(MCF + "goblin/death.png", 150, 150)]),
		},
		"mushroom": {
			"idle": anim(6, true, [strip(MCF + "mushroom/idle.png", 150, 150)]),
			"run": anim(10, true, [strip(MCF + "mushroom/run.png", 150, 150)]),
			"attack": anim(16, false, [strip(MCF + "mushroom/attack.png", 150, 150)]),
			"summon": anim(14, false, [strip(MCF + "mushroom/attack2.png", 150, 150)]),
			"throw": anim(18, false, [strip(MCF + "mushroom/attack3.png", 150, 150)]),
			"take_hit": anim(14, false, [strip(MCF + "mushroom/take_hit.png", 150, 150)]),
			"death": anim(8, false, [strip(MCF + "mushroom/death.png", 150, 150)]),
		},
		"rat": {
			"idle": anim(10, true, [strip(MCF2 + "rat/idle.png", 70, 70)]),
			"run": anim(14, true, [strip(MCF2 + "rat/run.png", 70, 70)]),
			"bite": anim(24, false, [strip(MCF2 + "rat/bite.png", 70, 70)]),
			"hurt": anim(12, false, [strip(MCF2 + "rat/hurt.png", 70, 70)]),
			"death": anim(10, false, [strip(MCF2 + "rat/death.png", 70, 70)]),
		},
		"mimic": {
			"closed": anim(1, true, [strip(MCF2 + "mimic/closed.png", 146, 146)]),
			"wake": anim(16, false, [strip(MCF2 + "mimic/opening.png", 146, 146), strip(MCF2 + "mimic/transform.png", 146, 146)]),
			"idle": anim(10, true, [strip(MCF2 + "mimic/idle.png", 146, 146)]),
			"walk": anim(10, true, [strip(MCF2 + "mimic/walk.png", 146, 146)]),
			"bite": anim(24, false, [strip(MCF2 + "mimic/bite.png", 146, 146)]),
			"tongue": anim(22, false, [strip(MCF2 + "mimic/tongue.png", 146, 146)]),
			"hurt": anim(12, false, [strip(MCF2 + "mimic/hurt.png", 146, 146)]),
			"death": anim(10, false, [strip(MCF2 + "mimic/death.png", 146, 146)]),
		},
		"fire_worm": {
			"idle": anim(10, true, [strip(WORM + "idle.png", 90, 90)]),
			"walk": anim(10, true, [strip(WORM + "walk.png", 90, 90)]),
			"attack": anim(24, false, [strip(WORM + "attack.png", 90, 90)]),
			"hit": anim(12, false, [strip(WORM + "hit.png", 90, 90)]),
			"death": anim(10, false, [strip(WORM + "death.png", 90, 90)]),
		},
		"evil_wizard": {
			"idle": anim(10, true, [strip(WIZ + "idle.png", 250, 250)]),
			"run": anim(12, true, [strip(WIZ + "run.png", 250, 250)]),
			"cast": anim(14, false, [strip(WIZ + "attack1.png", 250, 250)]),
			"slash": anim(14, false, [strip(WIZ + "attack2.png", 250, 250)]),
			"jump": anim(8, true, [strip(WIZ + "jump.png", 250, 250)]),
			"fall": anim(8, true, [strip(WIZ + "fall.png", 250, 250)]),
			"take_hit": anim(12, false, [strip(WIZ + "take_hit.png", 250, 250)]),
			"death": anim(10, false, [strip(WIZ + "death.png", 250, 250)]),
		},
		# --- Снаряды врагов: fly — полёт, explode — попадание ---
		"bomb": {
			"fly": anim(16, true, [strip(MCF + "goblin/bomb.png", 100, 100, 0, 9)]),
			"explode": anim(20, false, [strip(MCF + "goblin/bomb.png", 100, 100, 9)]),
		},
		"spore": {
			"fly": anim(10, true, [strip(MCF + "mushroom/spore.png", 50, 50, 0, 4)]),
			"explode": anim(16, false, [strip(MCF + "mushroom/spore.png", 50, 50, 4)]),
		},
		"sword": {
			"fly": anim(16, true, [strip(MCF + "skeleton/sword.png", 92, 102, 0, 4)]),
			"explode": anim(16, false, [strip(MCF + "skeleton/sword.png", 92, 102, 4)]),
		},
		"bolt": {
			"fly": anim(12, true, [strip(MCF + "flying_eye/bolt.png", 48, 48, 0, 3)]),
			"explode": anim(16, false, [strip(MCF + "flying_eye/bolt.png", 48, 48, 3)]),
		},
		"fireball": {
			"fly": anim(14, true, [strip(WORM + "fireball.png", 46, 46)]),
			"explode": anim(16, false, [strip(WORM + "fireball_explosion.png", 46, 46)]),
		},
		# --- Предметы ---
		"flag": {
			"idle": anim(10, true, [strip(PA + "flag_idle.png", 64, 64)]),
			"pressed": anim(20, false, [strip(PA + "flag_pressed.png", 64, 64)]),
		},
		"apple": {
			"idle": anim(20, true, [strip(PA + "apple.png", 32, 32)]),
			"collected": anim(20, false, [strip(PA + "collected.png", 32, 32)]),
		},
		# Панцирник и Царь-Панцирь: кадры из design/source, нарезаны tools/slice_strips.gd.
		"panzernik": {
			"idle": anim(3, true, [strip(SB + "shellback_walk_hurt.png", 64, 64, 0, 2)]),
			"walk": anim(10, true, [strip(SB + "shellback_walk_hurt.png", 64, 64, 0, 6)]),
			"hurt": anim(10, false, [strip(SB + "shellback_walk_hurt.png", 64, 64, 6, 2)]),
			"curl": anim(8, false, [strip(SB + "shellback_curl_roll.png", 64, 64, 0, 4)]),
			"roll": anim(20, true, [strip(SB + "shellback_curl_roll.png", 64, 64, 4, 4)]),
			"dizzy": anim(5, true, [strip(SB + "shellback_dizzy_death.png", 64, 64, 0, 2)]),
			"death": anim(9, false, [strip(SB + "shellback_dizzy_death.png", 64, 64, 2, 6)]),
		},
		"shellback_king": {
			"idle": anim(4, true, [strip(SB + "king_idle_walk.png", 64, 80, 0, 4)]),
			"walk": anim(6, true, [strip(SB + "king_idle_walk.png", 64, 80, 4, 4)]),
			"windup": anim(6, true, [strip(SB + "king_windup_roll_stomp.png", 64, 80, 0, 2)]),
			"roll": anim(18, true, [strip(SB + "king_windup_roll_stomp.png", 64, 80, 2, 4)]),
			"stomp": anim(3, false, [strip(SB + "king_windup_roll_stomp.png", 64, 80, 6, 2)]),
			"dizzy": anim(4, true, [strip(SB + "king_dizzy_hurt_death.png", 64, 80, 0, 2)]),
			"recover": anim(1, false, [strip(SB + "king_dizzy_hurt_death.png", 64, 80, 2, 1)]),
			"hurt": anim(10, false, [strip(SB + "king_dizzy_hurt_death.png", 64, 80, 3, 1)]),
			"death": anim(6, false, [strip(SB + "king_dizzy_hurt_death.png", 64, 80, 4, 4)]),
		},
		# --- Зомби (LuizMelo, CC0; перекрашены tools/make_zombies.gd) ---
		"zombie": {
			"idle": anim(7, true, [strip(ZB + "zombie_idle.png", 160, 111)]),
			"run": anim(9, true, [strip(ZB + "zombie_run.png", 160, 111)]),
			"attack": anim(11, false, [strip(ZB + "zombie_attack.png", 160, 111)]),
			"hit": anim(12, false, [strip(ZB + "zombie_hit.png", 160, 111)]),
			"death": anim(8, false, [strip(ZB + "zombie_death.png", 160, 111)]),
		},
		"grave_zombie": {
			"closed": anim(1, false, [strip(ZB + "grave_death.png", 160, 111, 5, 1)]),
			"wake": anim(7, false, [strip_rev(ZB + "grave_death.png", 160, 111)]),
			"idle": anim(7, true, [strip(ZB + "grave_idle.png", 160, 111)]),
			"run": anim(11, true, [strip(ZB + "grave_run.png", 160, 111)]),
			"attack": anim(12, false, [strip(ZB + "grave_attack.png", 160, 111)]),
			"hit": anim(12, false, [strip(ZB + "grave_hit.png", 160, 111)]),
			"death": anim(8, false, [strip(ZB + "grave_death.png", 160, 111)]),
		},
		"zombie_knight": {
			"idle": anim(8, true, [strip(ZB + "knight_idle.png", 180, 180)]),
			"run": anim(10, true, [strip(ZB + "knight_run.png", 180, 180)]),
			"attack": anim(14, false, [strip(ZB + "knight_attack.png", 180, 180)]),
			"attack2": anim(14, false, [strip(ZB + "knight_attack2.png", 180, 180)]),
			"hit": anim(12, false, [strip(ZB + "knight_hit.png", 180, 180)]),
			"death": anim(9, false, [strip(ZB + "knight_death.png", 180, 180)]),
		},
		"zombie_king": {
			"idle": anim(7, true, [strip(ZB + "king_idle.png", 160, 111)]),
			"run": anim(10, true, [strip(ZB + "king_run.png", 160, 111)]),
			"attack": anim(10, false, [strip(ZB + "king_attack.png", 160, 111)]),
			"attack2": anim(10, false, [strip(ZB + "king_attack2.png", 160, 111)]),
			"smash": anim(8, false, [strip(ZB + "king_attack3.png", 160, 111)]),
			"summon": anim(4, true, [strip(ZB + "king_attack.png", 160, 111, 0, 2)]),
			"hit": anim(12, false, [strip(ZB + "king_hit.png", 160, 111)]),
			"death": anim(7, false, [strip(ZB + "king_death.png", 160, 111)]),
			"jump": anim(6, false, [strip(ZB + "king_jump.png", 160, 111)]),
			"fall": anim(6, false, [strip(ZB + "king_fall.png", 160, 111)]),
		},
		# Камень, падающий с потолка (fly), и облако пыли при ударе о землю (puff).
		"shellback_rock": {
			"fly": anim(12, true, [strip(SB + "fx_dust_rock.png", 64, 64, 4, 4)]),
		},
		"dust_puff": {
			"puff": anim(14, false, [strip(SB + "fx_dust_rock.png", 64, 64, 0, 4)]),
		},
		# Ловушки (Pixel Adventure, папка Traps): пила, батут, огненная ловушка.
		"saw": {
			"spin": anim(24, true, [strip(TRAPS + "saw_on.png", 38, 38)]),
		},
		"trampoline": {
			"idle": anim(1, false, [strip(TRAPS + "trampoline_idle.png", 28, 28)]),
			"jump": anim(18, false, [strip(TRAPS + "trampoline_jump.png", 28, 28)]),
		},
		"fire": {
			"off": anim(1, false, [strip(TRAPS + "fire_off.png", 16, 32)]),
			"ignite": anim(10, true, [strip(TRAPS + "fire_hit.png", 16, 32)]),
			"burn": anim(12, true, [strip(TRAPS + "fire_on.png", 16, 32)]),
		},
	}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := false
	var all := sets()
	for set_name in all:
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var anims: Dictionary = all[set_name]
		for anim_name in anims:
			var spec: Dictionary = anims[anim_name]
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, spec["fps"])
			frames.set_animation_loop(anim_name, spec["loop"])
			for source in spec["sources"]:
				failed = not _add_frames(frames, anim_name, source) or failed
		var err := ResourceSaver.save(frames, OUT + set_name + ".tres")
		print("%s.tres: %s" % [set_name, "ok" if err == OK else "ошибка %d" % err])
		failed = failed or err != OK
	quit(1 if failed else 0)


func _add_frames(frames: SpriteFrames, anim_name: String, source: Array) -> bool:
	if source[0] == "files":
		for i in int(source[2]):
			var tex: Texture2D = load(source[1] % i)
			if tex == null:
				push_error("нет картинки " + source[1] % i)
				return false
			frames.add_frame(anim_name, tex)
		return true
	var reverse: bool = source[0] == "strip_rev"
	var sheet: Texture2D = load(source[1])
	if sheet == null:
		push_error("нет картинки " + source[1])
		return false
	var fw: int = source[2]
	var fh: int = source[3]
	var total := sheet.get_width() / fw
	var first: int = source[4]
	var count: int = source[5] if source[5] >= 0 else total - first
	var order := range(first, first + count)
	if reverse:
		order.reverse()
	for i in order:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim_name, atlas)
	return true
