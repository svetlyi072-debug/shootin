extends ModScript
## Пример скрипта мода. Скрипт обязан начинаться с «extends ModScript» (без class_name).
## Игра вызывает хуки, названия которых начинаются с «_»; ненужные можно не писать.

var kills := 0


func _mod_ready() -> void:
	kills = int(load_data().get("kills", 0))
	log_message("Жажда крови подключена. Убито за всё время: %d" % kills)


func _level_started(_level) -> void:
	hint("Жажда крови: за каждого убитого врага — +3 здоровья")


func _enemy_killed(_enemy, _power_reward) -> void:
	kills += 1
	var player = get_player()  # без типа: у игрока есть метод heal()
	if player != null and not player.is_dead():
		player.heal(3)
	if kills % 10 == 0:
		hint("Убито врагов за всё время: %d" % kills)
		save_data({"kills": kills})
