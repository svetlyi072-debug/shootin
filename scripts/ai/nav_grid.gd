class_name NavGrid
extends RefCounted
## Граф проходимости уровня для умных наземных врагов.
## Узлы — клетки, где можно стоять (клетка и клетка над ней свободны, под ногами блок или
## сквозная платформа, не шипы). Переходы:
##   * шаг влево/вправо;
##   * спуск: сойти с края и упасть на пол внизу (до MAX_DROP клеток), в том числе
##     с разбега — на 1–2 клетки дальше края (чтобы перескочить шипы внизу);
##   * прыжок вверх на 1–MAX_JUMP_UP клеток со сдвигом до 2 клеток (в т.ч. сквозь платформы);
##   * прыжок через яму или шипы до MAX_JUMP_ACROSS клеток (на 2 клетки выше/ниже).
## Путь ищется A* с двоичной кучей. Узлы и переходы строятся лениво и запоминаются.
## Поисков за один кадр физики — не больше SEARCHES_PER_FRAME (иначе — в следующем кадре).

const MAX_JUMP_UP := 2
const MAX_JUMP_ACROSS := 4
const MAX_DROP := 8
const MAX_EXPANDED := 1200
const SEARCHES_PER_FRAME := 2

var _level: Node
var _height := 0
var _edges := {}
var _standable := {}
var _frame := -1
var _searches := 0


func _init(level: Node, height: int) -> void:
	_level = level
	_height = height


## На клетке cell (место ног) можно стоять.
func standable(cell: Vector2i) -> bool:
	if _standable.has(cell):
		return _standable[cell]
	var ok: bool = cell.y >= 1 and cell.y < _height \
		and not _level.is_solid_cell(cell) and not _level.is_spike_cell(cell) \
		and not _level.is_solid_cell(cell + Vector2i.UP) and _level.is_floor_cell(cell + Vector2i.DOWN)
	_standable[cell] = ok
	return ok


## Ближайшая клетка, где можно стоять: та же, ниже (до 6) или по бокам.
func nearest_standable(cell: Vector2i) -> Vector2i:
	for dy in range(0, 7):
		for dx in [0, -1, 1]:
			var c := cell + Vector2i(dx, dy)
			if standable(c):
				return c
	return cell


## Можно ли ещё искать путь в этом кадре (общий бюджет на всех врагов).
func can_search() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_searches = 0
	return _searches < SEARCHES_PER_FRAME


func _free(cell: Vector2i) -> bool:
	return not _level.is_solid_cell(cell)


func edges(cell: Vector2i) -> Array:
	if _edges.has(cell):
		return _edges[cell]
	var out := []
	var seen := {}
	for dir in [-1, 1]:
		var side := cell + Vector2i(dir, 0)
		if standable(side):
			_add(out, seen, side, 1.0)
		elif _free(side) and _free(side + Vector2i.UP):
			# Обрыв: сходим с края и падаем на пол внизу — прямо или с разбега чуть дальше.
			for reach in range(0, 3):
				var column := side + Vector2i(dir * reach, 0)
				if reach > 0 and not (_free(column) and _free(column + Vector2i.UP)):
					break
				for depth in range(1, MAX_DROP + 1):
					var below := column + Vector2i(0, depth)
					if not _free(below) or _level.is_spike_cell(below):
						break
					if standable(below):
						_add(out, seen, below, 1.0 + depth * 0.25 + reach * 0.75)
						break
		# Прыжок вверх.
		for up in range(1, MAX_JUMP_UP + 1):
			for shift in range(0, 3):
				var target := cell + Vector2i(dir * shift, -up)
				if standable(target) and _clear_arc(cell, target):
					_add(out, seen, target, 2.0 + up + shift * 0.5)
		# Прыжок через яму или шипы.
		if not standable(side):
			for across in range(2, MAX_JUMP_ACROSS + 1):
				for dy in [0, -1, 1, 2, -2]:
					var target := cell + Vector2i(dir * across, dy)
					if standable(target) and _clear_arc(cell, target):
						_add(out, seen, target, 2.0 + across + absi(dy) * 0.5)
	_edges[cell] = out
	return out


func _add(out: Array, seen: Dictionary, target: Vector2i, cost: float) -> void:
	if not seen.has(target):
		seen[target] = true
		out.append([target, cost])


## Над траекторией прыжка нет блоков (запас в клетку над головой).
func _clear_arc(from: Vector2i, to: Vector2i) -> bool:
	var top := mini(from.y, to.y) - 2
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		var bottom := mini(from.y, to.y)
		if x == from.x:
			bottom = from.y
		elif x == to.x:
			bottom = to.y
		for y in range(top, bottom + 1):
			if _level.is_solid_cell(Vector2i(x, y)):
				return false
	return true


## Путь A* от from до to (обе — клетки, где можно стоять). Пустой массив — пути нет.
## Возвращает клетки после from, по порядку.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if from == to or not standable(from) or not standable(to):
		return []
	can_search()
	_searches += 1
	var heap: Array = []  # [f, x, y] — двоичная куча по f
	var came := {from: from}
	var cost := {from: 0.0}
	var closed := {}
	_push(heap, [_h(from, to), from.x, from.y])
	var expanded := 0
	while not heap.is_empty() and expanded < MAX_EXPANDED:
		var top: Array = _pop(heap)
		var current := Vector2i(top[1], top[2])
		if closed.has(current):
			continue
		if current == to:
			var path := []
			while current != from:
				path.append(current)
				current = came[current]
			path.reverse()
			return path
		closed[current] = true
		expanded += 1
		for edge in edges(current):
			var next: Vector2i = edge[0]
			if closed.has(next):
				continue
			var new_cost: float = cost[current] + edge[1]
			if not cost.has(next) or new_cost < cost[next]:
				cost[next] = new_cost
				came[next] = current
				_push(heap, [new_cost + _h(next, to), next.x, next.y])
	return []


func _h(a: Vector2i, b: Vector2i) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y) * 0.5


func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= item[0]:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var child := i * 2 + 1
		if child >= n:
			break
		if child + 1 < n and heap[child + 1][0] < heap[child][0]:
			child += 1
		if heap[child][0] >= last[0]:
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return top
