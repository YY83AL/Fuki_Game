extends Node2D
## Проба векторной куклы: рука из SVG при разном увеличении.
## Запуск: открыть сцену vector_test/vector_arm_test.tscn в Godot и нажать F6.
## Пробел — пауза, A — сглаживание краёв вкл/выкл, S — рукав вкл/выкл.

const BASE := 0.167        ## Масштаб «как в игре»: кошка ростом 1500 px занимает на экране 250 px
const RASTER_BASE := 0.38  ## Масштаб нынешней растровой куклы в игре
const SHOULDER_Y := 130.0
const BG := Color(0.85, 0.82, 0.76)
const INK := Color(0.16, 0.15, 0.14)

var arms: Array[VecArm] = []
var t: float = 0.0
var paused: bool = false
var smooth: bool = true
var hint: Label
var hidden_panels: Array[CanvasLayer] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	# Панель «Эффекты» на время пробы прячем, чтобы не закрывала руки.
	var fx: Node = get_node_or_null("/root/FX")
	if fx:
		for child in fx.get_children():
			var panel := child as CanvasLayer
			if panel and panel.visible and panel.layer == 16:
				panel.visible = false
				hidden_panels.append(panel)
	_apply_smooth()

	_add_arm(Vector2(90, SHOULDER_Y), 1.0, true, "Вектор ×1\nкак в игре")
	_add_arm(Vector2(250, SHOULDER_Y), 3.0, true, "Вектор ×3")
	_add_arm(Vector2(520, SHOULDER_Y), 6.0, true, "Вектор ×6\nс рукавом")
	_add_arm(Vector2(810, SHOULDER_Y), 6.0, false, "Вектор ×6\nбез рукава")

	# Для сравнения: кусок нынешнего рукава (картинка PNG) при том же увеличении ×6.
	var tex: Texture2D = load("res://assets/characters/red_cat/sleeveonly_L.png")
	if tex:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.region_enabled = true
		sp.region_rect = Rect2(60, 20, 90, 190)
		sp.scale = Vector2.ONE * RASTER_BASE * 6.0
		sp.position = Vector2(1050, SHOULDER_Y - 60)
		add_child(sp)
	_label(Vector2(1050, 640), "Нынешний рукав\n(картинка) ×6")

	hint = _label(Vector2(24, 24), "")
	_update_hint()
	set_process(true)


func _exit_tree() -> void:
	for panel in hidden_panels:                  # возвращаем панель, как была
		if is_instance_valid(panel):
			panel.visible = true
	VecMesh.set_smooth(true)


func _add_arm(pos: Vector2, zoom: float, sleeve: bool, text: String) -> void:
	var arm := VecArm.new()
	arm.show_sleeve = sleeve
	arm.position = pos
	arm.scale = Vector2.ONE * BASE * zoom
	add_child(arm)
	arms.append(arm)
	_label(Vector2(pos.x - 60, 640), text)


func _label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", INK)
	add_child(l)
	return l


func _apply_smooth() -> void:
	VecMesh.set_smooth(smooth)


func _update_hint() -> void:
	hint.text = "Пробел — пауза   ·   A — сглаживание краёв: %s   ·   S — рукав" % ("вкл" if smooth else "выкл")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match int(event.physical_keycode):
			KEY_SPACE:
				paused = not paused
			KEY_A:
				smooth = not smooth
				_apply_smooth()
				_update_hint()
			KEY_S:
				arms[2].set_sleeve(not arms[2].show_sleeve)


func _process(delta: float) -> void:
	if not paused:
		t += delta
	pose_at(t)


## Поза в момент времени: рука качается в плече, сгибается в локте до 110°, кисть покачивается.
func pose_at(time: float) -> void:
	var shoulder: float = 22.0 * sin(time * 1.1)
	var elbow: float = 55.0 - 55.0 * cos(time * 1.7)
	var wrist: float = 25.0 * sin(time * 2.3)
	for arm in arms:
		arm.set_pose(shoulder, elbow, wrist)
