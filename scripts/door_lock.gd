extends Node2D
## Кодовый замок на двери. Стоит в точке замка (мировые координаты).
## Рядом с дверью над замком появляется иконка «E в лапке». E — открыть панель с кнопками слева,
## WASD — двигать лапку по кнопкам, E — нажать кнопку, Q — закрыть. Подходит ЛЮБОЙ код из 4 цифр.

signal unlocked

static var opened: bool = false      ## Раз открыв замок, дверь больше не спрашивает код (пока игра не перезапущена)

@export var icon_offset: Vector2 = Vector2(34.0, -62.0)
@export var code_length: int = 4

var player: Node2D
var near: bool = false
var icon_alpha: float = 0.0
var t: float = 0.0
var panel_open: bool = false
var flash: float = 0.0          ## Подсветка замка при успехе (1) / ошибке (-1)

# --- панель ---
var layer: CanvasLayer
var root: Control
var cells: Array = []           # [{rect: Panel, label: Label, key: String}]
var sel := Vector2i(1, 1)
var code: String = ""
var slots: Array[Label] = []
var cursor: Node2D
var status: Label
const GRID := [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✔"]]
const CELL := Vector2(86.0, 70.0)
const GAP := 10.0


func _ready() -> void:
	z_index = 50
	_build_panel()


func set_near(v: bool) -> void:
	near = v


func _process(delta: float) -> void:
	t += delta
	icon_alpha = move_toward(icon_alpha, 1.0 if (near and not panel_open) else 0.0, delta * 4.0)
	flash = move_toward(flash, 0.0, delta * 1.5)
	if panel_open and cursor:
		var target := _cell_center(sel)
		cursor.position = cursor.position.lerp(target, 1.0 - exp(-delta * 18.0))
		cursor.rotation = lerp_angle(cursor.rotation, (target.x - cursor.position.x) * 0.002, 0.2)
	queue_redraw()


# ---------- рисование замка и иконки в мире ----------

static func draw_paw(ci: CanvasItem, c: Vector2, s: float, stroke: Color, fill: Color, width: float, letter: bool) -> void:
	# Контур кошачьей лапки: подушка + 4 пальца
	var shapes: Array = []
	shapes.append([c + Vector2(0, 9) * s, Vector2(24, 18) * s])
	shapes.append([c + Vector2(-23, -6) * s, Vector2(8, 10) * s])
	shapes.append([c + Vector2(-9, -19) * s, Vector2(8, 11) * s])
	shapes.append([c + Vector2(9, -19) * s, Vector2(8, 11) * s])
	shapes.append([c + Vector2(23, -6) * s, Vector2(8, 10) * s])
	for sh in shapes:
		var pts := PackedVector2Array()
		for i in 28:
			var a: float = TAU * i / 28.0
			pts.append(sh[0] + Vector2(cos(a) * sh[1].x, sin(a) * sh[1].y))
		ci.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		ci.draw_polyline(pts, stroke, width, true)
	if letter:
		var f: Font = ThemeDB.fallback_font
		var fs: int = int(round(26.0 * s))
		ci.draw_string(f, c + Vector2(-30.0 * s, 17.0 * s), "E", HORIZONTAL_ALIGNMENT_CENTER, 60.0 * s, fs, stroke)


func _draw() -> void:
	# корпус замка
	var plate := Rect2(Vector2(-13, -20), Vector2(26, 40))
	draw_rect(plate.grow(2.0), Color(0.62, 0.48, 0.2), true)
	draw_rect(plate, Color(0.14, 0.13, 0.16), true)
	var led: Color = Color(0.9, 0.35, 0.3)
	if flash > 0.0:
		led = Color(0.4, 0.95, 0.5)
	for i in 4:
		var on: bool = i < code.length() and panel_open
		var c: Color = led if (on or absf(flash) > 0.0) else Color(0.35, 0.2, 0.2)
		if flash < 0.0:
			c = Color(0.95, 0.25, 0.2)
		draw_circle(Vector2(-7.5 + i * 5.0, -14.0), 1.8, c)
	for r in 3:
		for k in 3:
			draw_rect(Rect2(Vector2(-8 + k * 6.5, -6 + r * 7.0), Vector2(4.5, 4.5)), Color(0.55, 0.55, 0.6), true)
	# иконка
	if icon_alpha > 0.01:
		var bob: float = sin(t * 3.0) * 3.0
		var pos: Vector2 = icon_offset + Vector2(0, bob)
		var a: float = icon_alpha
		var s: float = 0.85 + 0.15 * icon_alpha
		draw_paw(self, pos, s, Color(1, 1, 1, a), Color(0.08, 0.06, 0.1, 0.72 * a), 2.6, true)


# ---------- панель ----------

func _cell_center(g: Vector2i) -> Vector2:
	return root.get_node("Grid").position + Vector2(g.x * (CELL.x + GAP) + CELL.x * 0.5, g.y * (CELL.y + GAP) + CELL.y * 0.5)


func _build_panel() -> void:
	layer = CanvasLayer.new()
	layer.layer = 40
	layer.visible = false
	add_child(layer)
	root = Control.new()
	root.position = Vector2(40, 90)
	root.size = Vector2(340, 540)
	layer.add_child(root)
	var bg := Panel.new()
	bg.size = root.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.1, 0.92)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.62, 0.48, 0.2)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)
	# окошки для цифр
	for i in code_length:
		var l := Label.new()
		l.position = Vector2(30 + i * 68, 22)
		l.size = Vector2(56, 64)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 38)
		var ls := StyleBoxFlat.new()
		ls.bg_color = Color(0.02, 0.02, 0.03)
		ls.set_corner_radius_all(8)
		ls.set_border_width_all(2)
		ls.border_color = Color(0.35, 0.3, 0.2)
		l.add_theme_stylebox_override("normal", ls)
		root.add_child(l)
		slots.append(l)
	var grid := Control.new()
	grid.name = "Grid"
	grid.position = Vector2(25, 108)
	root.add_child(grid)
	for r in GRID.size():
		for c in 3:
			var p := Panel.new()
			p.position = Vector2(c * (CELL.x + GAP), r * (CELL.y + GAP))
			p.size = CELL
			grid.add_child(p)
			var l := Label.new()
			l.size = CELL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", 34)
			p.add_child(l)
			l.text = GRID[r][c]
			cells.append({"rect": p, "label": l, "key": GRID[r][c], "g": Vector2i(c, r)})
	status = Label.new()
	status.position = Vector2(0, 492)
	status.size = Vector2(340, 36)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	root.add_child(status)
	cursor = Node2D.new()
	cursor.z_index = 10
	cursor.draw.connect(func(): draw_paw(cursor, Vector2(0, 0), 0.8, Color(1, 1, 1), Color(0.95, 0.75, 0.2, 0.55), 2.4, false))
	root.get_node("Grid").add_child(cursor)
	_refresh()


func _refresh() -> void:
	for i in slots.size():
		slots[i].text = code[i] if i < code.length() else ""
	for c in cells:
		var st := StyleBoxFlat.new()
		var is_sel: bool = c["g"] == sel
		st.bg_color = Color(0.32, 0.27, 0.15) if is_sel else Color(0.16, 0.15, 0.2)
		st.set_corner_radius_all(12)
		st.set_border_width_all(3 if is_sel else 1)
		st.border_color = Color(0.95, 0.8, 0.35) if is_sel else Color(0.3, 0.3, 0.38)
		c["rect"].add_theme_stylebox_override("panel", st)
		var col := Color(0.95, 0.95, 1.0)
		if c["key"] == "✔":
			col = Color(0.5, 0.95, 0.55)
		elif c["key"] == "⌫":
			col = Color(0.95, 0.6, 0.5)
		c["label"].add_theme_color_override("font_color", col)
	if cursor:
		cursor.position = cursor.position
	cursor.queue_redraw()


func open() -> void:
	if opened:
		unlocked.emit()
		return
	if panel_open:
		return
	panel_open = true
	code = ""
	sel = Vector2i(1, 1)
	status.text = "WASD — лапка · E — нажать · Q — выйти"
	layer.visible = true
	cursor.position = _cell_center(sel)
	if player:
		player.set("active", false)
	_refresh()


func close() -> void:
	panel_open = false
	layer.visible = false
	if player:
		player.set("active", true)


func _press() -> void:
	var key: String = GRID[sel.y][sel.x]
	if key == "⌫":
		code = code.substr(0, maxi(code.length() - 1, 0))
	elif key == "✔":
		if code.length() == code_length:
			opened = true
			flash = 1.0
			status.text = "Открыто!"
			status.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
			var tw := create_tween()
			tw.tween_interval(0.5)
			tw.tween_callback(func():
				close()
				unlocked.emit())
		else:
			flash = -1.0
			status.text = "Нужно ввести %d цифры" % code_length
			var tw2 := create_tween()
			var base: Vector2 = root.position
			for i in 4:
				tw2.tween_property(root, "position:x", base.x + (10 if i % 2 == 0 else -10), 0.04)
			tw2.tween_property(root, "position:x", base.x, 0.04)
	else:
		if code.length() < code_length:
			code += key
	_refresh()


func _input(event: InputEvent) -> void:
	if not panel_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_W, KEY_UP:
				sel.y = posmod(sel.y - 1, GRID.size())
			KEY_S, KEY_DOWN:
				sel.y = posmod(sel.y + 1, GRID.size())
			KEY_A, KEY_LEFT:
				sel.x = posmod(sel.x - 1, 3)
			KEY_D, KEY_RIGHT:
				sel.x = posmod(sel.x + 1, 3)
			KEY_E:
				_press()
			KEY_Q, KEY_ESCAPE:
				close()
		_refresh()
		get_viewport().set_input_as_handled()
