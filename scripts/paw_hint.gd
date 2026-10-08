extends Node2D
## Подсказка «нажми E»: контур кошачьей лапки с буквой E над головой Фуки + короткая подпись.
## Используется везде, где нужно подтвердить действие (переходы между сценами и т.п.).

const DoorLockScript = preload("res://scripts/door_lock.gd")

var player: Node2D
var head_offset: float = -190.0
var alpha: float = 0.0
var caption: String = ""
var t: float = 0.0

## Совместимость со старым Label: hint.text = "E — куда-то" -> подпись «куда-то»
var text: String = "":
	set(v):
		text = v
		var i: int = v.find("—")
		caption = v.substr(i + 1).strip_edges() if i >= 0 else v


func _process(delta: float) -> void:
	t += delta
	alpha = move_toward(alpha, 1.0 if visible else 0.0, delta * 6.0 if visible else delta * 100.0)
	if player:
		var p: Vector2 = player.get_global_transform_with_canvas().origin
		var sc: float = float(player.get("base_scale")) if player.get("base_scale") != null else 1.0
		position = p + Vector2(0.0, -(215.0 * sc + 62.0) + sin(t * 3.0) * 3.0)
	queue_redraw()


func _draw() -> void:
	if alpha < 0.01:
		return
	var s: float = 0.85 + 0.15 * alpha
	DoorLockScript.draw_paw(self, Vector2.ZERO, s, Color(1, 1, 1, alpha), Color(0.08, 0.06, 0.1, 0.72 * alpha), 2.6, true)
	if caption != "":
		var f: Font = ThemeDB.fallback_font
		var w: float = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string_outline(f, Vector2(-w * 0.5, 50.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0, 0, 0, 0.8 * alpha))
		draw_string(f, Vector2(-w * 0.5, 50.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, alpha))
