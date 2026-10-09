class_name HybridLight
extends Node2D
## Гибридный свет сцены: фон остаётся таким, как нарисован, а «живых» источников всего несколько.
##   • Фуки подкрашивается в общий тон сцены (tone), чтобы не выглядела вырезанной из другой картинки.
##   • Каждый живой источник — мягкое пятно света. По умолчанию оно светит только на Фуки;
##     галочка «Светит и на фон» разрешает ему освещать и рисунок.
##   • Режим настройки: источники таскаются мышью, справа панель с яркостью, размером, цветом и мерцанием.
## Настройки сцены лежат в папке lighting/ (обычный текстовый файл .json), кнопка «Сохранить» пишет туда.
## Подключение в сцене: HybridLight.new() → add_child → setup(игрок, "имя_сцены", настройки по умолчанию).

signal enabled_changed(on: bool)      ## Гибрид включили или выключили (в том числе сам, из-за кнопки «Свет»)
signal editing_changed(on: bool)

const DIR := "res://lighting/"
const CAT_LAYER := 2                  ## Слой света, на котором лежит только Фуки
const HANDLE_R := 13.0
const NEW_LIGHT := {"pos": Vector2.ZERO, "color": Color(0.8, 0.88, 1.0), "energy": 1.5, "size": 1.5, "flicker": 0.0, "bg": false}

var player: Player
var scene_key: String = ""
var defaults: Dictionary = {}
var enabled: bool = false
var editing: bool = false
var tone: Color = Color(0.5, 0.57, 0.84)   ## Тон сцены: в него красится Фуки
var lights: Array = []                     ## Настройки источников: словари как NEW_LIGHT
var nodes: Array[PointLight2D] = []
var selected: int = -1
var drag: int = -1
var drag_off: Vector2 = Vector2.ZERO
var t: float = 0.0
var tex: GradientTexture2D
var dirty: bool = false

var overlay: Node2D
var panel_layer: CanvasLayer
var title: Label
var energy_slider: HSlider
var size_slider: HSlider
var flicker_slider: HSlider
var color_button: ColorPickerButton
var bg_check: CheckBox
var tone_button: ColorPickerButton
var status: Label
var light_controls: Array[Control] = []


func setup(p_player: Player, key: String, p_defaults: Dictionary) -> void:
	player = p_player
	scene_key = key
	defaults = p_defaults
	tex = _make_glow()
	for n in player.body.find_children("*", "CanvasItem", true, false):   # Фуки попадает и на «свой» слой света
		(n as CanvasItem).light_mask |= CAT_LAYER
	overlay = Node2D.new()
	overlay.name = "Handles"
	overlay.z_index = 200
	overlay.light_mask = 0
	overlay.draw.connect(_draw_handles)
	add_child(overlay)
	_build_panel()
	_load()
	_apply_enabled()
	set_editing(false)


func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 13:
		var u := float(i) / 12.0
		offs.append(u)
		cols.append(Color(1, 1, 1, 0.6 * pow(1.0 - u, 1.5)))
	g.offsets = offs
	g.colors = cols
	var tx := GradientTexture2D.new()
	tx.width = 256
	tx.height = 256
	tx.fill = GradientTexture2D.FILL_RADIAL
	tx.fill_from = Vector2(0.5, 0.5)
	tx.fill_to = Vector2(1.0, 0.5)
	tx.gradient = g
	return tx


# ------------------------------------------------------------------ включение

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:                                    # нынешний общий свет и гибрид вместе дают кашу: общий выключаем
		var fx: Node = get_node_or_null("/root/FX")
		if fx and fx.get("state")["light"]:
			fx.get("buttons")["light"].button_pressed = false
	else:
		set_editing(false)
	_apply_enabled()
	enabled_changed.emit(on)


func _apply_enabled() -> void:
	if player:
		player.body.modulate = tone if enabled else Color.WHITE
	for n in nodes:
		n.visible = enabled


func set_editing(on: bool) -> void:
	if on and not enabled:
		set_enabled(true)
	editing = on
	if panel_layer:
		panel_layer.visible = on
	overlay.visible = on
	drag = -1
	if on:
		_refresh_panel()
	editing_changed.emit(on)


func _process(delta: float) -> void:
	t += delta
	if enabled:
		var fx: Node = get_node_or_null("/root/FX")
		if fx and fx.get("state")["light"]:   # игрок включил общий свет — гибрид уступает
			set_enabled(false)
			return
		for i in nodes.size():
			var d: Dictionary = lights[i]
			var f: float = float(d["flicker"])
			var wob: float = 0.55 * sin(t * 9.0 + i * 2.1) + 0.3 * sin(t * 23.0 + i * 5.3) + 0.15 * sin(t * 47.0 + i)
			nodes[i].energy = maxf(float(d["energy"]) * (1.0 + 0.45 * f * wob), 0.0)
	if editing:
		overlay.queue_redraw()


# ------------------------------------------------------------------ источники

func _add_node(d: Dictionary) -> void:
	var l := PointLight2D.new()
	l.texture = tex
	l.visible = enabled
	add_child(l)
	nodes.append(l)
	lights.append(d)
	_apply_light(nodes.size() - 1)


func _apply_light(i: int) -> void:
	var d: Dictionary = lights[i]
	var l: PointLight2D = nodes[i]
	l.position = d["pos"]
	l.color = d["color"]
	l.energy = d["energy"]
	l.texture_scale = d["size"]
	l.range_item_cull_mask = (CAT_LAYER | 1) if d["bg"] else CAT_LAYER


func _clear() -> void:
	for n in nodes:
		n.queue_free()
	nodes.clear()
	lights.clear()
	selected = -1


func add_light() -> void:
	var d: Dictionary = NEW_LIGHT.duplicate()
	d["pos"] = player.global_position + Vector2(0.0, -150.0)      # новый источник появляется над Фуки
	_add_node(d)
	selected = nodes.size() - 1
	_changed()
	_refresh_panel()


func remove_selected() -> void:
	if selected < 0:
		return
	nodes[selected].queue_free()
	nodes.remove_at(selected)
	lights.remove_at(selected)
	selected = mini(selected, nodes.size() - 1)
	_changed()
	_refresh_panel()


func _changed() -> void:
	dirty = true
	_say("Есть несохранённые изменения.")


# ------------------------------------------------------------------ файл настроек

func _path() -> String:
	return DIR + scene_key + ".json"


func _to_data() -> Dictionary:
	var arr: Array = []
	for d in lights:
		var c: Color = d["color"]
		arr.append({"x": d["pos"].x, "y": d["pos"].y, "color": [c.r, c.g, c.b], "energy": d["energy"], "size": d["size"], "flicker": d["flicker"], "bg": d["bg"]})
	return {"tone": [tone.r, tone.g, tone.b], "lights": arr}


func _from_data(data: Dictionary) -> void:
	_clear()
	var tn: Array = data.get("tone", [0.5, 0.57, 0.84])
	tone = Color(tn[0], tn[1], tn[2])
	for e in data.get("lights", []):
		var c: Array = e.get("color", [1, 1, 1])
		_add_node({"pos": Vector2(e.get("x", 0.0), e.get("y", 0.0)), "color": Color(c[0], c[1], c[2]), "energy": float(e.get("energy", 1.5)),
			"size": float(e.get("size", 1.5)), "flicker": float(e.get("flicker", 0.0)), "bg": bool(e.get("bg", false))})
	selected = 0 if nodes.size() > 0 else -1
	_apply_enabled()


func _load() -> void:
	var data: Dictionary = defaults
	if FileAccess.file_exists(_path()):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path()))
		if parsed is Dictionary:
			data = parsed
	_from_data(data)
	dirty = false


func save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		_say("Не получилось сохранить. Настройка света работает, когда игра запущена из Godot.")
		return
	f.store_string(JSON.stringify(_to_data(), "\t"))
	f.close()
	dirty = false
	_say("Сохранено: lighting/%s.json" % scene_key)


func revert() -> void:
	_load()
	_refresh_panel()
	_say("Возвращено то, что было сохранено.")


# ------------------------------------------------------------------ панель настройки

func _slider(box: Container, text: String, lo: float, hi: float, cb: Callable) -> HSlider:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(220.0, 22.0)
	s.value_changed.connect(cb)
	box.add_child(s)
	light_controls.append(s)
	return s


func _btn(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _build_panel() -> void:
	panel_layer = CanvasLayer.new()
	panel_layer.layer = 11
	add_child(panel_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 200.0)
	panel_layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	energy_slider = _slider(box, "Яркость", 0.0, 5.0, func(v: float): _set_param("energy", v))
	size_slider = _slider(box, "Размер пятна", 0.3, 6.0, func(v: float): _set_param("size", v))
	flicker_slider = _slider(box, "Мерцание", 0.0, 1.0, func(v: float): _set_param("flicker", v))
	var row := HBoxContainer.new()
	box.add_child(row)
	var cl := Label.new()
	cl.text = "Цвет  "
	cl.add_theme_font_size_override("font_size", 15)
	row.add_child(cl)
	color_button = ColorPickerButton.new()
	color_button.custom_minimum_size = Vector2(120.0, 26.0)
	color_button.edit_alpha = false
	color_button.focus_mode = Control.FOCUS_NONE
	color_button.color_changed.connect(func(c: Color): _set_param("color", c))
	row.add_child(color_button)
	light_controls.append(color_button)
	bg_check = CheckBox.new()
	bg_check.text = "Светит и на фон"
	bg_check.focus_mode = Control.FOCUS_NONE
	bg_check.add_theme_font_size_override("font_size", 15)
	bg_check.toggled.connect(func(on: bool): _set_param("bg", on))
	box.add_child(bg_check)
	light_controls.append(bg_check)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	box.add_child(row2)
	_btn(row2, "+ Источник", add_light)
	light_controls.append(_btn(row2, "Удалить", remove_selected))
	box.add_child(HSeparator.new())
	var row3 := HBoxContainer.new()
	box.add_child(row3)
	var tl := Label.new()
	tl.text = "Тон кошки  "
	tl.add_theme_font_size_override("font_size", 15)
	row3.add_child(tl)
	tone_button = ColorPickerButton.new()
	tone_button.custom_minimum_size = Vector2(90.0, 26.0)
	tone_button.edit_alpha = false
	tone_button.focus_mode = Control.FOCUS_NONE
	tone_button.color_changed.connect(func(c: Color):
		tone = c
		_apply_enabled()
		_changed())
	row3.add_child(tone_button)
	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	box.add_child(row4)
	_btn(row4, "Сохранить", save)
	_btn(row4, "Как было", revert)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(220.0, 0.0)
	status.text = "Тяните кружки мышью. Щелчок по кружку выбирает источник."
	box.add_child(status)


func _say(text: String) -> void:
	if status:
		status.text = text


func _set_param(key: String, value: Variant) -> void:
	if selected < 0:
		return
	lights[selected][key] = value
	_apply_light(selected)
	_changed()


func _refresh_panel() -> void:
	var has: bool = selected >= 0
	title.text = ("Источник %d из %d" % [selected + 1, nodes.size()]) if has else "Источников нет"
	for c in light_controls:
		if c is BaseButton:
			(c as BaseButton).disabled = not has
		elif c is Slider:
			(c as Slider).editable = has
	tone_button.color = tone
	if not has:
		return
	var d: Dictionary = lights[selected]
	energy_slider.set_value_no_signal(d["energy"])
	size_slider.set_value_no_signal(d["size"])
	flicker_slider.set_value_no_signal(d["flicker"])
	color_button.color = d["color"]
	bg_check.set_pressed_no_signal(d["bg"])


# ------------------------------------------------------------------ мышь: выбор и перетаскивание

func _draw_handles() -> void:
	var font: Font = ThemeDB.fallback_font
	for i in nodes.size():
		var p: Vector2 = lights[i]["pos"]
		var c: Color = lights[i]["color"]
		var active: bool = i == selected
		overlay.draw_arc(p, 128.0 * float(lights[i]["size"]), 0.0, TAU, 64, Color(1, 1, 1, 0.35 if active else 0.12), 1.5)   # край пятна
		overlay.draw_circle(p, HANDLE_R + 3.0, Color(0.05, 0.05, 0.08, 0.9))
		overlay.draw_circle(p, HANDLE_R, Color(1.0, 0.62, 0.1) if active else Color(1, 1, 1))
		overlay.draw_circle(p, HANDLE_R - 4.0, c)
		overlay.draw_string(font, p + Vector2(HANDLE_R + 6.0, 6.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func _pick(m: Vector2) -> int:
	var best: int = -1
	var best_d: float = HANDLE_R + 8.0
	for i in nodes.size():
		var d: float = (lights[i]["pos"] as Vector2).distance_to(m)
		if d <= best_d:
			best_d = d
			best = i
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not editing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = overlay.make_input_local(event).position
		if event.pressed:
			drag = _pick(m)
			if drag >= 0:
				selected = drag
				drag_off = (lights[drag]["pos"] as Vector2) - m
				_refresh_panel()
				get_viewport().set_input_as_handled()
		else:
			drag = -1
	elif event is InputEventMouseMotion and drag >= 0:
		var m2: Vector2 = overlay.make_input_local(event).position
		lights[drag]["pos"] = m2 + drag_off
		nodes[drag].position = lights[drag]["pos"]
		dirty = true
		_say("Источник %d: x %d, y %d" % [drag + 1, int(lights[drag]["pos"].x), int(lights[drag]["pos"].y)])
