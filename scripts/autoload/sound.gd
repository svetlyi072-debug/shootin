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
