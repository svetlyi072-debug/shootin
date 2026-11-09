extends Control
## Главное меню: новая игра с выбором сложности, продолжение с сохранённого уровня, выход.
## Управляется мышью и клавиатурой (стрелки, Enter, Esc — назад).

const DESCRIPTIONS := [
	"У Шуткина есть щит (держи H или среднюю кнопку мыши). Враги без ИИ: ходят своим маршрутом и не охотятся за тобой, бьют, только если встанешь прямо перед ними. Боссы атакуют реже и не зовут помощников.",
	"У Шуткина есть щит (держи H или среднюю кнопку мыши). Враги с мега-мозгом: ищут путь по уровню, нападают стаей по очереди, ждут, пока опустишь щит, делают финты, видят, куда ты целишься, лечатся яблоками и подстраиваются под твой стиль. Боссы целятся на упреждение и звереют на половине здоровья.",
	"Щита нет. Враги с тем же мега-мозгом, что на нормальной.",
]

@onready var _main_buttons: Control = %MainButtons
@onready var _difficulty_panel: Control = %DifficultyPanel
@onready var _new_game: Button = %NewGameButton
@onready var _continue: Button = %ContinueButton
@onready var _mods: Button = %ModsButton
@onready var _quit: Button = %QuitButton
@onready var _easy: Button = %EasyButton
@onready var _normal: Button = %NormalButton
@onready var _hard: Button = %HardButton
@onready var _back: Button = %BackButton
@onready var _description: Label = %Description
@onready var _footer: Label = $Footer

const MODS_SCENE := "res://scenes/ui/mods_menu.tscn"
const CREDITS := "Графика CC0: Pixel Frog, LuizMelo, rvros"
const KEYS := "A/D — бег · Space — прыжок · ЛКМ — стрельба · J — удар · K / ПКМ — сфера · H / СКМ — щит · Esc — пауза
F11 — на весь экран · P — скрыть подсказки"
const TOUCH_KEYS := "Джойстик — бег · тап по экрану — выстрел · зажми палец при полной шкале силы — сфера"


func _ready() -> void:
	get_tree().paused = false
	Game.leave_campaign()  # главное меню — всегда про встроенную игру
	Sound.set_music_override(null)
	_update_footer(Display.hints_visible)
	Display.hints_changed.connect(_update_footer)
	Touch.enabled_changed.connect(func(_on: bool) -> void: _update_footer(Display.hints_visible))
	_new_game.pressed.connect(_show_difficulty)
	_continue.pressed.connect(Game.continue_game)
	_mods.pressed.connect(func() -> void: get_tree().change_scene_to_file(MODS_SCENE))
	_refresh_mods_button()
	_quit.pressed.connect(get_tree().quit)
	# В браузере выйти из игры нельзя — вкладку закрывают сами, кнопка только вводила бы в заблуждение.
	_quit.visible = not OS.has_feature("web")
	_back.pressed.connect(_show_main)
	var buttons := [_easy, _normal, _hard]
	for difficulty in buttons.size():
		var button: Button = buttons[difficulty]
		button.pressed.connect(Game.start_new_game.bind(difficulty))
		button.focus_entered.connect(_describe.bind(difficulty))
		button.mouse_entered.connect(_describe.bind(difficulty))
	_refresh_continue()
	_show_main()


## Подсказки с кнопками (P прячет их, остаются только авторы графики).
func _update_footer(show_keys: bool) -> void:
	if Touch.enabled:
		_footer.text = TOUCH_KEYS + "    " + CREDITS  # на телефоне клавиши P нет — подсказку не прячем
		return
	_footer.text = (KEYS + "    " + CREDITS) if show_keys else CREDITS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _difficulty_panel.visible:
		_show_main()
		get_viewport().set_input_as_handled()


## На кнопке — сколько модов сейчас включено.
func _refresh_mods_button() -> void:
	var active := Mods.enabled_mods().size()
	_mods.text = "Моды (включено: %d)" % active if active > 0 else "Моды"


func _refresh_continue() -> void:
	var saved := Game.saved_progress()
	_continue.visible = not saved.is_empty()
	if saved.is_empty():
		return
	var index: int = saved["level_index"]
	var title: String = Game.level_data(index).get("TITLE", "")
	_continue.text = "Продолжить: уровень %d «%s» · %s" % [index + 1, title, Game.DIFFICULTY_NAMES[saved["difficulty"]]]


func _show_main() -> void:
	_main_buttons.show()
	_difficulty_panel.hide()
	(_continue if _continue.visible else _new_game).grab_focus()


func _show_difficulty() -> void:
	_main_buttons.hide()
	_difficulty_panel.show()
	_normal.grab_focus()
	_describe(Game.Difficulty.NORMAL)


func _describe(difficulty: int) -> void:
	var text: String = DESCRIPTIONS[difficulty]
	if Touch.enabled:
		text = text.replace("(держи H или среднюю кнопку мыши)", "(держи кнопку щита справа)")
	var forced := Mods.forced_difficulty()
	if forced >= 0:  # включённый мод (например, «Хардкорный режим») задаёт сложность сам
		text += "

Сложность задаёт мод «%s»: %s." % [Mods.forced_difficulty_mod(), Game.DIFFICULTY_NAMES[forced]]
	_description.text = text
