extends Node2D
## Слой с листьями, которые лежат ближе к зрителю, чем Фуки (рисуются поверх неё).

func _draw() -> void:
	var system: Leaves = get_node("../Leaves")
	system.draw_on(self, true)
