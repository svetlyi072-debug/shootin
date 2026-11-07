extends WalkerEnemy
## Скрипт врага: «Злой гуль» от каждого удара бегает быстрее.
## Скрипт врага должен расширять тот же класс, что и враг этого вида:
## WalkerEnemy — ходячие враги из enemies/*.json, ModBoss — боссы из bosses/*.json.

const RAGE_BOOST := 1.15


func _on_damaged(amount: int) -> void:
	super(amount)
	move_speed_tiles *= RAGE_BOOST
