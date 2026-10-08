extends RefCounted
## Помощник для переходов между локациями: затемнение, место появления и подсказка про клавишу E.

static var spawn_x: float = -1.0   ## Где появится Фуки в новой локации (-1 — где стоит по умолчанию)
static var busy: bool = false


static func _overlay(host: Node, alpha: float) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 100
	host.add_child(layer)
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	return r


## Плавно проявить картинку из чёрного (вызывать при входе в локацию).
static func fade_in(host: Node) -> void:
	var r := _overlay(host, 1.0)
	var tw := host.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.55)
	tw.tween_callback(r.get_parent().queue_free)


## Затемнить экран и перейти в другую сцену; Фуки появится на x = spawn.
static func go(host: Node, scene_path: String, spawn: float) -> void:
	if busy:
		return
	busy = true
	spawn_x = spawn
	var r := _overlay(host, 0.0)
	var tw := host.create_tween()
	tw.tween_property(r, "color:a", 1.0, 0.45)
	tw.tween_callback(func():
		busy = false
		host.get_tree().change_scene_to_file(scene_path))


## Подсказка «E в лапке» над головой Фуки (по умолчанию скрыта). Включается через hint.visible = true/false.
static func make_hint(host: Node, text: String) -> Node2D:
	var layer := CanvasLayer.new()
	layer.layer = 20
	host.add_child(layer)
	var h := Node2D.new()
	h.set_script(load("res://scripts/paw_hint.gd"))
	var pl = host.get("player")
	if pl == null and host.get("players") != null:
		pl = host.get("players")[0]
	h.player = pl
	h.text = text
	layer.add_child(h)
	return h


## Порядок локаций для быстрых стрелок наверху экрана.
const SCENE_LIST := [
	["res://scenes/location_6.tscn", "Белый лист"],
	["res://scenes/location_7.tscn", "Офис"],
]


## Две стрелки в верхних углах (index — номер текущей, с 0).
## Мир идёт справа налево: левая стрелка — СЛЕДУЮЩАЯ сцена, правая — предыдущая.
static func add_scene_arrows(host: Node, index: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	host.add_child(layer)
	for side in [-1, 1]:
		var target: int = index - side   # слева — следующая, справа — предыдущая
		if target < 0 or target >= SCENE_LIST.size():
			continue
		var b := Button.new()
		var name: String = SCENE_LIST[target][1]
		b.text = ("◀  " + name) if side < 0 else (name + "  ▶")
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		if side < 0:
			b.anchor_left = 0.0
			b.anchor_right = 0.0
			b.offset_left = 12.0
			b.offset_right = 12.0
			b.grow_horizontal = Control.GROW_DIRECTION_END
		else:
			b.anchor_left = 1.0
			b.anchor_right = 1.0
			b.offset_left = -12.0
			b.offset_right = -12.0
			b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		b.offset_top = 10.0
		b.pressed.connect(func(): go(host, SCENE_LIST[target][0], -1.0))
		layer.add_child(b)
