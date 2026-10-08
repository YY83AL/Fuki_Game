extends Node2D
## Слой дождя в доме, который ближе к зрителю, чем Фуки (рисуется поверх неё).

func _draw() -> void:
	var system: IndoorRain = get_node("../IndoorRain")
	system.draw_on(self, true)
