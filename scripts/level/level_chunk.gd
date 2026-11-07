class_name LevelChunk
extends Node2D
## Кусок карты шириной в несколько колонок: рисует свои блоки, платформы и шипы.
## Уровень делится на такие куски, чтобы на огромных картах Godot не рисовал каждый кадр
## десятки тысяч невидимых клеток (кусок вне экрана пропускается целиком).

var level: Node
var first_column := 0
var last_column := 0


func _draw() -> void:
	level.paint_chunk(self, first_column, last_column)
