extends CanvasLayer
## Интерфейс: здоровье, щит, шкала силы, номер уровня и сложность, счётчик врагов,
## полоска босса, баннер с названием уровня, подсказки, большие сообщения по центру
## экрана и пауза (Esc). Работает и на паузе (process_mode = Always в hud.tscn).

const BANNER_TIME := 3.0
const HINT_TIME := 2.5

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_value: Label = %HealthValue
@onready var _shield_row: Control = %ShieldRow
@onready var _shield_bar: ProgressBar = %ShieldBar
@onready var _shield_value: Label = %ShieldValue
@onready var _power_bar: ProgressBar = %PowerBar
@onready var _power_value: Label = %PowerValue
@onready var _level_label: Label = %LevelLabel
@onready var _enemies_label: Label = %EnemiesLabel
@onready var _boss_panel: Control = %BossPanel
@onready var _boss_name: Label = %BossName
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _banner: Label = %Banner
@onready var _hint: Label = %Hint
@onready var _message_box: Control = %MessageBox
@onready var _message: Label = %Message
@onready var _sub_message: Label = %SubMessage
@onready var _pause_panel: Control = %PausePanel
@onready var _resume_button: Button = %ResumeButton
@onready var _controls: Label = $Controls

var _banner_timer := Timer.new()
var _hint_timer := Timer.new()


func _ready() -> void:
	for timer in [_banner_timer, _hint_timer]:
		timer.one_shot = true
		add_child(timer)
	_banner_timer.timeout.connect(_banner.hide)
	_hint_timer.timeout.connect(_hint.hide)

	_controls.visible = Display.hints_visible  # P прячет и показывает подсказки с кнопками
	Display.hints_changed.connect(_controls.set_visible)
	_boss_panel.hide()
	_message_box.hide()
	_banner.hide()
	_hint.hide()
	_enemies_label.hide()
	_pause_panel.hide()
	_shield_row.visible = Game.player_has_shield()
	%DifficultyInfo.text = "Сложность: %s" % Game.difficulty_name()
	_resume_button.pressed.connect(_set_paused.bind(false))
	%RestartButton.pressed.connect(_restart_level)
	%MenuButton.pressed.connect(Game.go_to_menu)

	Game.player_health_changed.connect(_on_player_health_changed)
	Game.player_power_changed.connect(_on_player_power_changed)
	Game.player_shield_changed.connect(_on_player_shield_changed)
	Game.player_died.connect(_on_player_died)
	Game.boss_activated.connect(_on_boss_activated)
	Game.boss_health_changed.connect(_on_boss_health_changed)
	Game.boss_defeated.connect(_boss_panel.hide)
	Game.level_started.connect(_on_level_started)
	Game.enemies_left_changed.connect(_on_enemies_left_changed)
	Game.hint.connect(_show_hint)
	Game.level_completed.connect(_on_level_completed)
	Game.game_won.connect(_on_game_won)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_value.text = "%d/%d" % [current, maximum]


func _on_player_shield_changed(current: int, maximum: int) -> void:
	_shield_row.visible = maximum > 0
	_shield_bar.max_value = maximum
	_shield_bar.value = current
	_shield_value.text = "%d/%d" % [current, maximum]


func _on_player_power_changed(current: int, maximum: int) -> void:
	_power_bar.max_value = maximum
	_power_bar.value = current
	if current >= maximum:
		_power_value.text = "%d/%d  ГОТОВО! (K / ПКМ)" % [current, maximum]
	else:
		_power_value.text = "%d/%d" % [current, maximum]


func _on_level_started(number: int, total: int, title: String, require_clear: bool) -> void:
	_level_label.text = "Уровень %d/%d · %s · %s" % [number, total, title, Game.difficulty_name()]
	_enemies_label.visible = require_clear
	_banner.text = "Уровень %d\n%s" % [number, title]
	if require_clear:
		_banner.text += "\nПобеди всех врагов, чтобы открыть выход"
	_banner.show()
	_banner_timer.start(BANNER_TIME)


func _on_enemies_left_changed(count: int) -> void:
	_enemies_label.text = "Врагов осталось: %d" % count


func _on_player_died() -> void:
	_show_message("Ты умер", "R — начать уровень заново · Esc — в главное меню")


func _on_boss_activated(boss_name: String, current: int, maximum: int) -> void:
	_boss_name.text = boss_name
	_on_boss_health_changed(current, maximum)
	_boss_panel.show()


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current


func _on_level_completed(next_title: String) -> void:
	_show_message("Уровень пройден!", "Дальше: %s" % next_title)


func _on_game_won() -> void:
	_boss_panel.hide()
	_show_message("Ты победил!", "Все уровни пройдены (%s). R — новая игра · Esc — в главное меню" % Game.difficulty_name())


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint.show()
	_hint_timer.start(HINT_TIME)


func _show_message(text: String, sub_text: String) -> void:
	_banner.hide()
	_message.text = text
	_sub_message.text = sub_text
	_message_box.show()


# --- Пауза ------------------------------------------------------------------------

## Esc: пауза / продолжить. После смерти или победы — выход в главное меню.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _message_box.visible and not get_tree().paused:
		Game.go_to_menu()
	else:
		_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_panel.visible = paused
	if paused:
		_resume_button.grab_focus()


func _restart_level() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
