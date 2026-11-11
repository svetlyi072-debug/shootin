class_name BossMusic
extends Node
## Музыка боя с боссом. Узел создаёт уровень (level.gd).
##
## Музыка включается не «при появлении босса на уровне», а когда бой начался: босс проснулся (игрок подошёл или
## ударил его) и игрок рядом с ним (ENGAGE_TILES). На огромном финальном уровне она поэтому звучит только рядом
## с боссами, а не весь уровень. Если игрок убежал далеко (RELEASE_TILES), босс убит или игрок погиб, музыка
## затихает и возвращается обычная музыка уровня. Два порога (20 и 26 клеток; экран шириной примерно 27 клеток)
## не дают музыке мигать на границе. Босс на арене с поводком уходит от своего места не дальше полуширины арены,
## так что игрок, убежавший из арены, оказывается за порогом.
## Сам трек и его формат — в Sound (assets/music/). Нет трека — узел ничего не делает, кроме подсчёта.

## Ближе этого (клетки) бой начинается, если босс проснулся.
const ENGAGE_TILES := 20.0
## Дальше этого бой считается оконченным: игрок убежал.
const RELEASE_TILES := 26.0
## Сколько секунд подряд боя нет, прежде чем музыка стихнет (чтобы не дёргалась, если босс на миг отошёл).
const CALM_SECONDS := 1.2
## Как часто проверять расстояния, секунд (босс до 70 врагов в группе, каждый кадр не нужно).
const CHECK_EVERY := 0.2

## Идёт ли бой (для проверок и подсказок).
var fighting := false

var _calm := 0.0
var _since_check := 0.0
var _final := false


func _ready() -> void:
	name = "BossMusic"
	_final = Game.is_last_level()


func _physics_process(delta: float) -> void:
	_since_check += delta
	if _since_check < CHECK_EVERY:
		return
	var elapsed := _since_check
	_since_check = 0.0
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.is_dead() or Game.is_game_over:
		if fighting:
			_set_fighting(false, 0.5)  # погиб игрок или уровень пройден — стихаем сразу
		return
	var reach := RELEASE_TILES if fighting else ENGAGE_TILES  # уже идущий бой держится дольше, чем начинается
	if _boss_nearby(reach):
		_calm = 0.0
		if not fighting:
			_set_fighting(true)
	elif fighting:
		_calm += elapsed
		if _calm >= CALM_SECONDS:
			_set_fighting(false)


## Есть ли проснувшийся живой босс не дальше reach клеток от игрока.
func _boss_nearby(reach: float) -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var boss := node as Boss
		if boss != null and boss.is_awake() and boss.distance_to_player_tiles() <= reach:
			return true
	return false


func _set_fighting(on: bool, fade: float = 1.4) -> void:
	fighting = on
	_calm = 0.0
	if on:
		Sound.start_boss_music("final" if _final else "boss")
	else:
		Sound.stop_boss_music(fade)


func _exit_tree() -> void:
	# Уровень закрывается (меню, следующий уровень, перезапуск): музыка боя не должна переходить в другую сцену.
	Sound.stop_boss_music(0.4)
