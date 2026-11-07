class_name FireTrap
extends Trap
## Огненная ловушка (символ f): блок в полу, из которого периодически вырывается пламя.
## Блок твёрдый (как #), пламя поднимается над ним на клетку. Цикл: молчит off_time,
## разгорается warn_time (безопасно — успей отбежать), горит on_time и ранит.
## Огни соседних ловушек горят не в такт.

@export var off_time := 1.6
@export var warn_time := 0.6
@export var on_time := 1.3

enum Phase { OFF, WARN, ON }
const ANIMATIONS := ["off", "ignite", "burn"]

var phase := Phase.OFF
var _clock := 0.0
var _shown := -1
var _sprite: AnimatedSprite2D


func _ready() -> void:
	super()
	damage = 15
	bounce_tiles = 1.2
	_add_box(Vector2(20.0, 28.0)).position = Vector2(0.0, -48.0)  # пламя — клетка над блоком
	_sprite = _add_sprite("fire", "off", 2.0)
	_sprite.position = Vector2(0.0, -32.0)  # кадр 16×32: основание в клетке блока, пламя выше
	_clock = fmod(position.x * 0.37, _cycle())
	_update_phase()


func _cycle() -> float:
	return off_time + warn_time + on_time


func _animate(delta: float) -> void:
	_clock = fmod(_clock + delta, _cycle())
	_update_phase()


## Фаза огня в момент clock цикла.
func _phase_at(clock: float) -> Phase:
	var t := fmod(clock, _cycle())
	if t >= off_time + warn_time:
		return Phase.ON
	if t >= off_time:
		return Phase.WARN
	return Phase.OFF


## Пламя опасно (для осторожного врага — и пока разгорается) через t секунд.
func zone_at(t: float) -> Rect2:
	if _phase_at(_clock + t) == Phase.OFF:
		return Rect2()
	return _flame_rect()


func reach_rect() -> Rect2:
	return _flame_rect()


func _flame_rect() -> Rect2:
	return Rect2(global_position + Vector2(-10.0, -62.0), Vector2(20.0, 28.0))


func _update_phase() -> void:
	phase = _phase_at(_clock)
	if _shown != phase:
		_shown = phase
		_sprite.play(ANIMATIONS[phase])


func is_dangerous() -> bool:
	return phase == Phase.ON
