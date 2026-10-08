extends Node2D
## Следы Фуки на песке: появляются при шаге и постепенно исчезают (песок разглаживается).

const LIFE := 9.0           ## Через сколько секунд след пропадает совсем
const MAX_PRINTS := 90

var prints: Array = []       ## [позиция, возраст, сторона (−1/1), направление (−1/1), размер]


func add_print(pos: Vector2, dir: float, size: float, side: float) -> void:
	prints.append([pos, 0.0, side, dir, size])
	if prints.size() > MAX_PRINTS:
		prints.pop_front()


func _process(delta: float) -> void:
	for p in prints:
		p[1] += delta
	while not prints.is_empty() and prints[0][1] > LIFE:
		prints.pop_front()
	queue_redraw()


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	for p in prints:
		var pos: Vector2 = p[0]
		var age: float = p[1]
		var s: float = p[4]
		var dir: float = p[3]
		var a: float = clampf(1.0 - age / LIFE, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)                 # плавное исчезновение
		a *= clampf(age / 0.12, 0.0, 1.0)           # и мягкое появление
		var rx: float = 11.0 * s
		var ry: float = 4.6 * s
		# ямка в песке: тёмная, со светлым ободком с солнечной стороны
		draw_colored_polygon(_ellipse(pos + Vector2(0.0, 1.0 * s), rx + 1.4 * s, ry + 1.2 * s), Color(1.0, 0.82, 0.62, 0.20 * a))
		draw_colored_polygon(_ellipse(pos, rx, ry), Color(0.20, 0.13, 0.12, 0.50 * a))
		# носок: пальцы чуть впереди по ходу
		var toe: Vector2 = pos + Vector2(dir * rx * 0.85, 0.0)
		draw_colored_polygon(_ellipse(toe, 3.4 * s, 2.6 * s, 10), Color(0.18, 0.11, 0.10, 0.5 * a))
