extends SceneTree
## Проверка музыки боя с боссом: она должна включаться, когда бой начался (босс проснулся и игрок рядом),
## а не весь финальный уровень; затихать, если игрок убежал, босс убит или игрок погиб; не ломаться без трека.
## Настоящий трек не нужен: подставляется короткая заглушка (Sound.boss_stream_override).
## Запуск (на отдельной папке данных, чтобы не трогать сохранения игрока):
##   node D:/ShotMOD/tools/godot_isolated.js --headless --script res://tools/export/boss_music_test.gd
## Код выхода 0 — всё хорошо.

var fails := 0
var game
var sound


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


## Секунда тишины в формате WAV с зацикливанием — вместо настоящего трека.
func stub_track() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()  # свойство data возвращает копию, поэтому собираем массив отдельно
	samples.resize(22050 * 2)
	wav.data = samples
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	return wav


func open_final() -> Node:
	game.leave_campaign()
	game.difficulty = 1
	game.game_completed = false
	game.go_to_level(game.level_count() - 1)
	await frames(40)
	return current_scene.find_child("BossMusic", true, false)


## Ставит игрока рядом с боссом (по горизонтали, чуть выше земли — упадёт на пол).
func stand_near(boss, tiles: float) -> void:
	var player = get_first_node_in_group("player")
	player.global_position = boss.global_position + Vector2(-game.tiles(tiles), -game.tiles(2.0))
	player.velocity = Vector2.ZERO


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	game = root.get_node("Game")
	sound = root.get_node("Sound")
	await frames(2)

	sound.boss_stream_override = stub_track()
	var music = await open_final()
	check(music != null, "на уровне есть узел BossMusic")
	if music == null:
		print("ИТОГ: узла музыки боя нет")
		quit(1)
		return
	var level = get_first_node_in_group("level")
	var boss = level.win_boss
	check(boss != null and not boss.is_awake(), "главный босс финала спит")
	check(not music.fighting and not sound.boss_music_on(), "на старте финала (боссы далеко) музыки боя нет")
	await frames(60)
	check(not music.fighting, "пока игрок не подошёл к боссу, музыка не включается (весь уровень она не играет)")
	var level_db_before: float = sound._music.volume_db if sound._music != null else 0.0
	var start_pos: Vector2 = get_first_node_in_group("player").global_position  # старт финала: от боссов далеко

	# --- Подошли к боссу: бой начался ---
	stand_near(boss, 10.0)
	await frames(50)
	check(boss.is_awake(), "босс проснулся, когда игрок подошёл")
	check(music.fighting and sound.boss_music_on(), "бой начался — музыка боя включена")
	check(sound._boss_music != null and sound._boss_music.playing, "трек боя действительно играет")
	await frames(60)
	check(sound._boss_music.volume_db > -20.0, "музыка боя набрала громкость (%.1f дБ)" % sound._boss_music.volume_db)
	if sound._music != null:
		check(sound._music.volume_db < -40.0, "обычная музыка затихла, но продолжает идти (%.1f дБ, играет: %s)" % [sound._music.volume_db, str(sound._music.playing)])

	# --- Убежали: музыка отменяется ---
	var runner = get_first_node_in_group("player")
	runner.global_position = start_pos
	runner.velocity = Vector2.ZERO
	check(boss.distance_to_player_tiles() > 40.0, "убежал на старт уровня: до босса %.0f клеток" % boss.distance_to_player_tiles())
	await frames(30)
	check(music.fighting, "сразу после рывка музыка ещё держится (не дёргается)")
	await frames(110)
	check(not music.fighting and not sound.boss_music_on(), "убежал далеко — музыка боя отменена")
	await frames(120)
	check(not sound._boss_music.playing, "трек боя остановлен после затухания")
	if sound._music != null:
		check(absf(sound._music.volume_db - level_db_before) < 1.0, "обычная музыка уровня вернулась (%.1f дБ)" % sound._music.volume_db)

	# --- Вернулись: снова бой ---
	stand_near(boss, 12.0)
	await frames(60)
	check(music.fighting and sound.boss_music_on() and sound._boss_music.playing, "вернулся к боссу — музыка снова включилась")

	# --- Игрок погиб ---
	get_first_node_in_group("player").kill()
	await frames(25)
	check(not music.fighting and not sound.boss_music_on(), "игрок погиб — музыка боя выключена")

	# --- Босс убит ---
	music = await open_final()
	boss = get_first_node_in_group("level").win_boss
	stand_near(boss, 10.0)
	await frames(60)
	check(music.fighting, "новая попытка: бой снова идёт")
	boss.take_damage(999999, boss.global_position + Vector2(-20, 0))
	await frames(60)
	check(not music.fighting and not sound.boss_music_on(), "босс убит — музыка боя выключена")

	# --- Выход из уровня во время боя ---
	music = await open_final()
	boss = get_first_node_in_group("level").win_boss
	stand_near(boss, 10.0)
	await frames(60)
	check(sound.boss_music_on(), "бой идёт перед выходом в меню")
	game.go_to_menu()
	await frames(30)
	check(not sound.boss_music_on(), "после выхода в меню музыка боя не остаётся")

	# --- Настоящий трек из assets/music/ (если он положен) ---
	sound.boss_stream_override = null
	sound._boss_streams.clear()
	if sound.has_boss_music("boss"):
		var real: AudioStream = sound._boss_stream("boss")
		check(real is AudioStreamOggVorbis or real is AudioStreamMP3, "настоящий трек загружен (%s)" % real.get_class())
		check(real.loop and absf(real.loop_offset - sound.BOSS_LOOP_OFFSET) < 0.01, "трек зациклен, после круга идёт с %.1f с" % real.loop_offset)
		check(real.get_length() > 30.0, "длина трека %.1f с" % real.get_length())
		music = await open_final()
		boss = get_first_node_in_group("level").win_boss
		stand_near(boss, 10.0)
		await frames(60)
		check(music.fighting and sound.boss_music_on() and sound._boss_music.stream == real and sound._boss_music.playing, "в бою играет настоящий трек")
		check(sound._boss_music.get_playback_position() > 0.3, "трек идёт (позиция %.1f с)" % sound._boss_music.get_playback_position())
		get_first_node_in_group("player").kill()
		await frames(25)
		check(not sound.boss_music_on(), "после гибели настоящий трек затихает")

	# --- Нет трека: игра не ломается ---
	sound.boss_stream_override = null
	sound._boss_streams.clear()
	check(not sound.has_boss_music("boss") or sound.has_boss_music("boss"), "поиск трека без файла не падает")
	if not sound.has_boss_music("boss"):
		music = await open_final()
		boss = get_first_node_in_group("level").win_boss
		stand_near(boss, 10.0)
		await frames(60)
		check(music.fighting and not sound.boss_music_on(), "без трека бой определяется, но звука боя нет и ошибок нет")
		check(sound._music == null or sound._music.volume_db > -20.0, "без трека обычная музыка продолжает играть как играла")

	print("ИТОГ: %s (%d ошибок)" % ["ВСЁ ХОРОШО" if fails == 0 else "ЕСТЬ ОШИБКИ", fails])
	quit(1 if fails else 0)
