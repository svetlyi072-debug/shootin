extends Node
## Звук: фоновая музыка и короткие эффекты (автозагрузка «Sound»).
## Файлы лежат в assets/: background.mp3 (музыка, зациклена и не прерывается при смене
## сцен) и bloop.wav (эффект). Эффект один, поэтому события различаются высотой тона
## и громкостью (см. EVENTS), а каждый раз он ещё чуть «плавает» по тону, чтобы не
## надоедало. Звуки с места действия (атаки врагов, удары игрока) затухают с расстоянием
## от камеры и слегка смещаются в нужное ухо; звуки меню звучат ровно.
##
## Использование:  Sound.play("click")  или  Sound.play("enemy_attack", global_position)
## Кнопки меню и паузы озвучиваются сами: любая кнопка, попавшая в дерево сцены, щёлкает.

const MUSIC_PATH := "res://assets/background.mp3"
const SFX_PATH := "res://assets/bloop.wav"

## Музыка боя с боссом (папка assets/music/, см. README.md в ней). Формат — .ogg или .mp3, название — как ниже.
## «boss» — любой бой с боссом, «final» — бой на последнем уровне (если трека для него нет, играет «boss»).
## Файлов может не быть — тогда во время боя продолжает играть обычная музыка.
const BOSS_MUSIC := {
	"boss": ["res://assets/music/boss_battle.ogg", "res://assets/music/boss_battle.mp3"],
	"final": ["res://assets/music/boss_final.ogg", "res://assets/music/boss_final.mp3"],
}
## Громкость музыки боя чуть выше обычной: бой должен звучать мощнее.
const BOSS_MUSIC_DB := -11.0
## Громкость «выключенной» музыки (затухание до тишины).
const SILENT_DB := -60.0
## Сколько секунд нарастает музыка боя и затухает обычная в начале боя.
const BOSS_FADE_IN := 0.7
## С какой секунды трек боя продолжается после круга: первые секунды (удар, разгон) звучат только в начале боя,
## а конец трека подогнан (перекрёстное затухание) под эту точку. Для других треков безвреден: пропускаются первые 4 с.
const BOSS_LOOP_OFFSET := 4.0

## Громкость музыки (дБ): тише эффектов, чтобы не заглушала бой.
const MUSIC_DB := -14.0
## Дальше этого расстояния (px) эффект не слышен.
const HEARING_DISTANCE := 800.0
const PLAIN_POOL := 6
const WORLD_POOL := 12

## pitch — высота тона (1 = как в файле), db — громкость.
const EVENTS := {
	"click": {"pitch": 1.25, "db": -4.0},         # нажатие кнопки меню
	"bounce": {"pitch": 1.9, "db": -3.0},         # батут
	"punch": {"pitch": 0.9, "db": 0.0},           # удар игрока
	"shot": {"pitch": 1.6, "db": -9.0},           # пуля игрока (стреляет часто — тихо)
	"sphere": {"pitch": 0.55, "db": 0.0},         # заряженная сфера
	"enemy_attack": {"pitch": 0.8, "db": -2.0},   # атака врага
	"boss_attack": {"pitch": 0.5, "db": 2.0},     # атака босса — ниже и громче
}

var _music: AudioStreamPlayer
var _default_music: AudioStream
## Музыка боя звучит отдельным проигрывателем: обычная музыка уровня при этом затихает, но не прерывается.
var _boss_music: AudioStreamPlayer
var _boss_on := false
var _boss_streams := {}
var _fade: Tween
## Подмена трека боя (для проверок и модов); null — брать из файлов assets/music/.
var boss_stream_override: AudioStream
var _sfx: AudioStream
var _plain: Array[AudioStreamPlayer] = []
var _world: Array[AudioStreamPlayer2D] = []
var _next_plain := 0
var _next_world := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # музыка и щелчки работают и на паузе
	_sfx = _load(SFX_PATH)
	for i in PLAIN_POOL:
		var player := AudioStreamPlayer.new()
		player.stream = _sfx
		add_child(player)
		_plain.append(player)
	for i in WORLD_POOL:
		var player := AudioStreamPlayer2D.new()
		player.stream = _sfx
		player.max_distance = HEARING_DISTANCE
		player.attenuation = 1.4
		player.panning_strength = 0.6
		add_child(player)
		_world.append(player)

	var music := _load(MUSIC_PATH)
	if music is AudioStreamMP3:
		music.loop = true
	_default_music = music
	if music:
		_music = AudioStreamPlayer.new()
		_music.stream = music
		_music.volume_db = MUSIC_DB
		add_child(_music)
		_music.play()

	get_tree().node_added.connect(_on_node_added)


## Музыка уровня мода вместо обычной; null — вернуть обычную.
func set_music_override(stream: AudioStream) -> void:
	if _music == null:
		return
	var target := stream if stream != null else _default_music
	if _music.stream == target:
		return
	_music.stream = target
	_music.play()


# --- Музыка боя с боссом ---------------------------------------------------------------------

## Есть ли трек для боя (kind — «boss» или «final»).
func has_boss_music(kind: String = "boss") -> bool:
	return _boss_stream(kind) != null


## Идёт ли сейчас музыка боя (включена и не затухает).
func boss_music_on() -> bool:
	return _boss_on


func _boss_stream(kind: String) -> AudioStream:
	if boss_stream_override != null:
		return boss_stream_override
	if _boss_streams.has(kind):
		return _boss_streams[kind]
	var stream: AudioStream = null
	for path in BOSS_MUSIC.get(kind, []):
		stream = _load(path) as AudioStream
		if stream != null:
			break
	if stream == null and kind != "boss":
		stream = _boss_stream("boss")  # своего трека нет — обычный трек боя
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true  # бой может идти долго — трек зациклен
		stream.loop_offset = BOSS_LOOP_OFFSET
	_boss_streams[kind] = stream
	return stream


## Включает музыку боя: она нарастает с нуля, а обычная музыка уровня затихает (но продолжает идти).
## Возвращает false, если трека нет — тогда ничего не меняется.
func start_boss_music(kind: String = "boss") -> bool:
	var stream := _boss_stream(kind)
	if stream == null:
		return false
	if _boss_music == null:
		_boss_music = AudioStreamPlayer.new()
		_boss_music.volume_db = SILENT_DB
		add_child(_boss_music)
	if not _boss_music.playing or _boss_music.stream != stream:
		_boss_music.stream = stream
		_boss_music.volume_db = SILENT_DB
		_boss_music.play()
	_boss_on = true
	_crossfade(BOSS_MUSIC_DB, SILENT_DB, BOSS_FADE_IN)
	return true


## Выключает музыку боя: она затухает за fade секунд, обычная музыка уровня возвращается.
func stop_boss_music(fade: float = 1.4) -> void:
	if not _boss_on:
		return
	_boss_on = false
	_crossfade(SILENT_DB, MUSIC_DB, fade)


## Плавно меняет громкость музыки боя и обычной музыки. Музыка боя, дойдя до тишины, останавливается.
func _crossfade(boss_db: float, level_db: float, seconds: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	if _boss_music != null:
		_fade.tween_property(_boss_music, "volume_db", boss_db, seconds)
	if _music != null:
		_fade.tween_property(_music, "volume_db", level_db, seconds)
	if boss_db <= SILENT_DB:
		_fade.chain().tween_callback(func() -> void:
			if not _boss_on and _boss_music != null:
				_boss_music.stop())


## Файла может не быть (например, звуки ещё не добавлены) — тогда игра просто молчит.
func _load(path: String) -> Resource:
	return load(path) if ResourceLoader.exists(path) else null


## Сыграть событие из EVENTS. С at — как звук из точки мира (громче вблизи камеры),
## без at — ровно.
func play(event: String, at := Vector2.INF) -> void:
	if _sfx == null:
		return
	var spec: Dictionary = EVENTS.get(event, EVENTS["punch"])
	var pitch: float = spec["pitch"] * randf_range(0.94, 1.06)
	if at == Vector2.INF:
		var player := _free_plain()
		player.pitch_scale = pitch
		player.volume_db = spec["db"]
		player.play()
	else:
		var player := _free_world()
		player.global_position = at
		player.pitch_scale = pitch
		player.volume_db = spec["db"]
		player.play()


## Свободный проигрыватель из пула; если заняты все — самый давний (звук обрывается).
func _free_plain() -> AudioStreamPlayer:
	for player in _plain:
		if not player.playing:
			return player
	_next_plain = (_next_plain + 1) % _plain.size()
	return _plain[_next_plain]


func _free_world() -> AudioStreamPlayer2D:
	for player in _world:
		if not player.playing:
			return player
	_next_world = (_next_world + 1) % _world.size()
	return _world[_next_world]


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button and not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play("click")
