extends Node2D
## Редактор поз, уровень 1. В игру не входит: это рабочий инструмент автора игры.
## Запуск: открыть сцену pose_editor/pose_editor.tscn в Godot и нажать F6.
##
## Что умеет:
##   • тянуть мышью точки на суставах кошки — она встаёт в позу, плащ и рукава живут на физике;
##   • переключаться между игровой куклой (FukiPuppet) и векторной (VecPuppet): позы и файлы у них общие;
##   • хранить список поз и время между ними;
##   • показывать движение («Играть») так, как оно будет выглядеть в игре: с входом из обычной стойки;
##   • сохранять движение в папку animations/fuki в родном формате Godot (Animation, файл .tres).
## Чего пока нет (это уровень 2): тени прошлой позы, зеркала, отмены действия, выбора вида перехода.
##
## Клавиши: Пробел — играть / стоп; F — согнуть локоть в другую сторону (навести мышь на лапу или локоть).

const ANIM_DIR := "res://animations/fuki/"
const RigFuki := preload("res://pose_editor/rig_fuki.gd")
const RigVec := preload("res://pose_editor/rig_vec.gd")
const PUPPET_NAMES: Array[String] = ["Игровая кукла", "Векторная кукла (проба)"]
const GROUND := Vector2(450.0, 655.0)         ## Точка на полу, где стоит кошка
const PANEL_W := 340.0
const KEY_EASE := -2.0                        ## Переход между позами: плавный разгон и торможение
const HANDLE_R := 9.0
const BG := Color("cfc3ae")

const HANDLE_NAMES := {
	"pelvis": "Таз", "waist": "Поясница: наклон корпуса", "neck": "Грудь", "head": "Голова",
	"elbow_0": "Локоть (ближняя рука)", "paw_0": "Лапа (ближняя рука)",
	"elbow_1": "Локоть (дальняя рука)", "paw_1": "Лапа (дальняя рука)",
	"foot_0": "Стопа (ближняя нога)", "toe_0": "Носок (ближняя нога)",
	"foot_1": "Стопа (дальняя нога)", "toe_1": "Носок (дальняя нога)",
}
const HANDLE_ORDER: Array[String] = ["foot_1", "toe_1", "elbow_1", "paw_1", "pelvis", "waist", "neck", "head", "foot_0", "toe_0", "elbow_0", "paw_0"]

var puppet: Node2D               ## Кукла на экране: FukiPuppet или VecPuppet
var rig                          ## «Поводок» к ней: где точки, что делать при перетаскивании (rig_fuki.gd, rig_vec.gd)
var kind: int = 0                ## 0 — игровая кукла, 1 — векторная
var puppet_list: OptionButton
var overlay: Node2D
var poses: Array = []            ## [{ "v": словарь позы, "time": секунд до следующей позы }]
var cur: int = 0
var playing: bool = false
var play_time: float = 0.0
var play_len: float = 0.0
var dirty: bool = false
var handle_pos: Dictionary = {}  ## имя точки → место на экране
var hover: String = ""
var drag: String = ""
var drag_off: Vector2 = Vector2.ZERO
var hidden_panels: Array[CanvasLayer] = []
var play_id: int = 0             ## Номер показа: чтобы старый показ не остановил новый
var asked: String = ""           ## О чём редактор уже предупредил (несохранённые изменения)

var name_edit: LineEdit
var open_list: OptionButton
var pose_list: ItemList
var time_spin: SpinBox
var loop_check: CheckBox
var play_button: Button
var status: Label
var title: Label
var edit_controls: Array[Control] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var floor_line := Line2D.new()
	floor_line.points = PackedVector2Array([Vector2(40.0, GROUND.y), Vector2(1280.0 - PANEL_W - 40.0, GROUND.y)])
	floor_line.width = 3.0
	floor_line.default_color = Color(0.12, 0.11, 0.1)
	add_child(floor_line)

	# Панель «Эффекты» из игры здесь не нужна: прячем на время работы редактора.
	var fx: Node = get_node_or_null("/root/FX")
	if fx:
		for child in fx.get_children():
			var p := child as CanvasLayer
			if p and p.visible and p.layer == 16:
				p.visible = false
				hidden_panels.append(p)

	var fps: CanvasLayer = get_node_or_null("/root/FpsCounter") as CanvasLayer      # счётчик кадров ложится поверх панели
	if fps and fps.visible:
		fps.visible = false
		hidden_panels.append(fps)

	_set_puppet(0)

	overlay = Node2D.new()
	overlay.name = "Handles"
	overlay.z_index = 100
	overlay.draw.connect(_draw_handles)
	add_child(overlay)

	_build_panel()
	_new_animation()
	_refresh_open_list()


## Ставит на экран выбранную куклу. Позы остаются: у обеих кукол они записаны одними и теми же величинами.
func _set_puppet(new_kind: int) -> void:
	if puppet:
		remove_child(puppet)
		puppet.queue_free()
	kind = new_kind
	rig = RigVec.new() if kind == 1 else RigFuki.new()
	puppet = rig.make()
	puppet.position = GROUND
	add_child(puppet)
	move_child(puppet, 2)                 # над фоном и линией пола, под точками и подсказкой
	puppet.connect("pose_finished", _on_play_finished)
	hover = ""
	drag = ""
	handle_pos.clear()


func _on_puppet_selected(index: int) -> void:
	if index == kind:
		return
	_set_puppet(index)
	_say("На экране: %s. Позы те же, их можно сохранять и открывать на любой из кукол." % PUPPET_NAMES[index].to_lower())


func _exit_tree() -> void:
	for p in hidden_panels:
		if is_instance_valid(p):
			p.visible = true


# ------------------------------------------------------------------ панель справа

func _button(parent: Node, text: String, cb: Callable, in_edit_only: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	if in_edit_only:
		edit_controls.append(b)
	return b


func _label(parent: Node, text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _row(parent: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	parent.add_child(r)
	return r


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(1280.0 - PANEL_W, 0.0)
	panel.size = Vector2(PANEL_W, 720.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_label(box, "Редактор поз", 22)
	title = _label(box, "", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))

	puppet_list = OptionButton.new()
	puppet_list.focus_mode = Control.FOCUS_NONE
	for n in PUPPET_NAMES:
		puppet_list.add_item(n)
	puppet_list.item_selected.connect(_on_puppet_selected)
	box.add_child(puppet_list)
	edit_controls.append(puppet_list)

	_label(box, "Название движения")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "например: взмах"
	name_edit.text_changed.connect(func(_t: String): _mark_dirty())
	box.add_child(name_edit)
	edit_controls.append(name_edit)
	var r1 := _row(box)
	_button(r1, "Сохранить", _save)
	_button(r1, "Новое", _new_animation)
	open_list = OptionButton.new()
	open_list.focus_mode = Control.FOCUS_NONE
	open_list.item_selected.connect(_on_open_selected)
	box.add_child(open_list)
	edit_controls.append(open_list)

	box.add_child(HSeparator.new())
	_label(box, "Позы по порядку")
	pose_list = ItemList.new()
	pose_list.custom_minimum_size = Vector2(0.0, 118.0)
	pose_list.focus_mode = Control.FOCUS_NONE
	pose_list.item_selected.connect(_on_pose_selected)
	box.add_child(pose_list)
	edit_controls.append(pose_list)
	var r2 := _row(box)
	_button(r2, "+ Поза", _add_pose)
	_button(r2, "Удалить", _delete_pose)
	_button(box, "Эту позу — в обычную стойку", _reset_pose)

	var r3 := _row(box)
	_label(r3, "До следующей, с")
	time_spin = SpinBox.new()
	time_spin.min_value = 0.05
	time_spin.max_value = 10.0
	time_spin.step = 0.05
	time_spin.value = 0.3
	time_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_spin.value_changed.connect(_on_time_changed)
	r3.add_child(time_spin)
	edit_controls.append(time_spin)

	loop_check = CheckBox.new()
	loop_check.text = "Повторять по кругу"
	loop_check.focus_mode = Control.FOCUS_NONE
	loop_check.toggled.connect(func(_on: bool):
		_mark_dirty()
		_refresh_pose_list())
	box.add_child(loop_check)
	edit_controls.append(loop_check)

	box.add_child(HSeparator.new())
	play_button = _button(box, "▶  Играть (Пробел)", _toggle_play, false)
	play_button.add_theme_font_size_override("font_size", 20)

	status = _label(box, "", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(PANEL_W - 28.0, 0.0)
	# подсказка — под линией пола, чтобы не занимать место на панели
	var help := Label.new()
	help.text = "Тяните точки мышью. Стопы главнее таза: если нога не достаёт до своей точки, таз опускается сам.\nНосок вниз — стопа встаёт на носок, вверх — на пятку.   F — согнуть локоть в другую сторону (наведите мышь на лапу)."
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.15, 0.13, 0.11, 0.8))
	help.position = Vector2(40.0, GROUND.y + 12.0)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)


func _say(text: String) -> void:
	status.text = text


func _mark_dirty() -> void:
	dirty = true
	asked = ""
	_update_title()


func _update_title() -> void:
	title.text = "● есть несохранённые изменения" if dirty else "все изменения сохранены"
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3) if dirty else Color(1, 1, 1, 0.5))


func _refresh_pose_list() -> void:
	pose_list.clear()
	for i in poses.size():
		var last: bool = i == poses.size() - 1
		var what: String = "до следующей"
		if last:
			what = "до первой" if loop_check.button_pressed else "держится"
		pose_list.add_item("Поза %d   —   %.2f с %s" % [i + 1, float(poses[i]["time"]), what])
	cur = clampi(cur, 0, poses.size() - 1)
	pose_list.select(cur)
	time_spin.set_value_no_signal(float(poses[cur]["time"]))


func _refresh_open_list() -> void:
	open_list.clear()
	open_list.add_item("Открыть сохранённое…")
	var dir := DirAccess.open(ANIM_DIR)
	if dir:
		var names: Array[String] = []
		for f in dir.get_files():
			if f.ends_with(".tres"):
				names.append(f.trim_suffix(".tres"))
		names.sort()
		for n in names:
			open_list.add_item(n)
	open_list.select(0)


# ------------------------------------------------------------------ позы

## Не даёт случайно потерять несохранённую работу: первое нажатие только предупреждает.
func _may_discard(what: String) -> bool:
	if not dirty or asked == what:
		asked = ""
		return true
	asked = what
	_say("Есть несохранённые изменения. Нажмите ещё раз, чтобы продолжить без сохранения.")
	return false


func _new_animation() -> void:
	if not _may_discard("new"):
		return
	poses = [{"v": rig.neutral(), "time": 0.3}]
	cur = 0
	name_edit.text = ""
	loop_check.set_pressed_no_signal(false)
	dirty = false
	_update_title()
	_refresh_pose_list()
	_say("Новое движение. Первая поза — обычная стойка.")


func _on_pose_selected(index: int) -> void:
	cur = index
	time_spin.set_value_no_signal(float(poses[cur]["time"]))


func _add_pose() -> void:
	var copy := {"v": (poses[cur]["v"] as Dictionary).duplicate(true), "time": poses[cur]["time"]}
	poses.insert(cur + 1, copy)
	cur += 1
	_mark_dirty()
	_refresh_pose_list()
	_say("Добавлена поза %d — копия предыдущей. Меняйте её точками." % (cur + 1))


func _delete_pose() -> void:
	if poses.size() <= 1:
		_say("Последнюю позу удалить нельзя.")
		return
	poses.remove_at(cur)
	cur = mini(cur, poses.size() - 1)
	_mark_dirty()
	_refresh_pose_list()


func _reset_pose() -> void:
	poses[cur]["v"] = rig.neutral()
	_mark_dirty()


func _on_time_changed(value: float) -> void:
	poses[cur]["time"] = value
	_mark_dirty()
	_refresh_pose_list()


# ------------------------------------------------------------------ файл движения (формат Godot)

## Собирает движение Godot из списка поз: по одной дорожке на каждую величину позы.
func build_animation() -> Animation:
	var anim := Animation.new()
	var tracks := {}
	for key in FukiPuppet.POSE_KEYS:
		var ti: int = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(ti, NodePath(".:" + key))
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		anim.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
		tracks[key] = ti
	var time: float = 0.0
	for p in poses:
		for key in FukiPuppet.POSE_KEYS:
			anim.track_insert_key(tracks[key], time, p["v"][key], KEY_EASE)
		time += float(p["time"])
	anim.length = maxf(time, 0.05)
	anim.loop_mode = Animation.LOOP_LINEAR if loop_check.button_pressed else Animation.LOOP_NONE
	return anim


## Читает движение обратно в список поз. Поза ставится на каждый момент, где в файле есть ключ.
func read_animation(anim: Animation) -> void:
	var times: Array[float] = []
	var track_of := {}
	for ti in anim.get_track_count():
		var key: String = str(anim.track_get_path(ti).get_concatenated_subnames())
		if not FukiPuppet.POSE_KEYS.has(key):
			continue
		track_of[key] = ti
		for k in anim.track_get_key_count(ti):
			var tm: float = anim.track_get_key_time(ti, k)
			var known: bool = false
			for x in times:
				if absf(x - tm) < 0.001:
					known = true
			if not known:
				times.append(tm)
	times.sort()
	if times.is_empty():
		times.append(0.0)
	poses = []
	for i in times.size():
		var v: Dictionary = rig.neutral()
		for key in track_of:
			v[key] = anim.value_track_interpolate(track_of[key], times[i])
		var next_t: float = times[i + 1] if i + 1 < times.size() else anim.length
		poses.append({"v": v, "time": maxf(snappedf(next_t - times[i], 0.01), 0.05)})
	loop_check.set_pressed_no_signal(anim.loop_mode != Animation.LOOP_NONE)
	cur = 0


func _clean_name(text: String) -> String:
	var n: String = text.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		n = n.replace(ch, "")
	return n.replace(" ", "_")


func _save() -> void:
	var n: String = _clean_name(name_edit.text)
	if n == "":
		_say("Сначала введите название движения.")
		return
	name_edit.text = n
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ANIM_DIR))
	var path: String = ANIM_DIR + n + ".tres"
	var err: int = ResourceSaver.save(build_animation(), path)
	if err != OK:
		_say("Не получилось сохранить (ошибка %d). Редактор надо запускать из Godot, а не из готовой сборки игры." % err)
		return
	dirty = false
	_update_title()
	_refresh_open_list()
	_say("Сохранено: animations/fuki/%s.tres" % n)


func _on_open_selected(index: int) -> void:
	if index <= 0:
		return
	var n: String = open_list.get_item_text(index)
	open_list.select(0)
	if not _may_discard("open " + n):
		return
	var anim: Animation = ResourceLoader.load(ANIM_DIR + n + ".tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	if anim == null:
		_say("Не получилось открыть «%s»." % n)
		return
	read_animation(anim)
	name_edit.text = n
	dirty = false
	_update_title()
	_refresh_pose_list()
	_say("Открыто: %s, поз: %d." % [n, poses.size()])


# ------------------------------------------------------------------ показ движения

func _toggle_play() -> void:
	if playing:
		_stop_play()
		return
	var anim: Animation = build_animation()
	playing = true
	play_id += 1
	play_time = 0.0
	play_len = anim.length
	drag = ""
	for c in edit_controls:
		_set_enabled(c, false)
	play_button.text = "■  Стоп (Пробел)"
	puppet.call("pose_hold", false)        # как в игре: движение начинается из обычной стойки
	puppet.call("pose_play", anim)


func _on_play_finished() -> void:
	if playing:
		var id: int = play_id
		await get_tree().create_timer(float(puppet.get("pose_out")) + 0.15).timeout     # даём кошке вернуться в обычную стойку
		if playing and id == play_id:
			_stop_play()


func _stop_play() -> void:
	playing = false
	for c in edit_controls:
		_set_enabled(c, true)
	play_button.text = "▶  Играть (Пробел)"
	_say("")


func _set_enabled(c: Control, on: bool) -> void:
	if c is BaseButton:
		(c as BaseButton).disabled = not on
	elif c is LineEdit:
		(c as LineEdit).editable = on
	elif c is SpinBox:
		(c as SpinBox).editable = on
	elif c is ItemList:
		c.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ каждый кадр

func _process(delta: float) -> void:
	if playing:
		play_time += delta
		var shown: float = fmod(play_time, play_len) if loop_check.button_pressed else minf(play_time, play_len)
		_say("Идёт показ: %.2f из %.2f с" % [shown, play_len])
	rig.frame(delta, poses[cur]["v"], playing)
	handle_pos = {} if playing else rig.handles()
	overlay.queue_redraw()


func _draw_handles() -> void:
	if playing:
		return
	for id in HANDLE_ORDER:
		if not handle_pos.has(id):
			continue
		var p: Vector2 = handle_pos[id]
		var far: bool = id.ends_with("_1")
		var r: float = HANDLE_R * (0.8 if far else 1.0)
		var active: bool = id == hover or id == drag
		var fill := Color(1.0, 0.62, 0.1) if active else (Color(0.75, 0.82, 0.9, 0.85) if far else Color(1, 1, 1, 0.95))
		overlay.draw_circle(p, r + 2.0, Color(0.08, 0.08, 0.1, 0.9))
		overlay.draw_circle(p, r, fill)
	var shown: String = drag if drag != "" else hover
	if shown != "" and handle_pos.has(shown):
		var font: Font = ThemeDB.fallback_font
		var text: String = HANDLE_NAMES[shown]
		var at: Vector2 = handle_pos[shown] + Vector2(16.0, -14.0)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		overlay.draw_rect(Rect2(at + Vector2(-6.0, -18.0), Vector2(w + 12.0, 26.0)), Color(0.08, 0.08, 0.1, 0.85))
		overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


# ------------------------------------------------------------------ мышь и клавиши

func _pick(m: Vector2) -> String:
	var best: String = ""
	var best_d: float = HANDLE_R + 7.0
	for id in HANDLE_ORDER:
		if handle_pos.has(id):
			var d: float = (handle_pos[id] as Vector2).distance_to(m)
			if d <= best_d:            # при равенстве выигрывает точка, нарисованная позже (ближняя к зрителю)
				best_d = d
				best = id
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			_toggle_play()
		elif event.physical_keycode == KEY_F and not playing:
			var id: String = drag if drag != "" else hover
			if id.begins_with("paw_") or id.begins_with("elbow_"):
				rig.flip_elbow(poses[cur]["v"], int(id.right(1)))
				_mark_dirty()
		return
	if playing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = overlay.make_input_local(event).position
		if event.pressed:
			get_viewport().gui_release_focus()
			drag = _pick(m)
			if drag != "":
				drag_off = (handle_pos[drag] as Vector2) - m
		else:
			drag = ""
	elif event is InputEventMouseMotion:
		var m2: Vector2 = overlay.make_input_local(event).position
		if drag != "":
			rig.drag(poses[cur]["v"], drag, m2 + drag_off)
			_mark_dirty()
		else:
			hover = _pick(m2)
