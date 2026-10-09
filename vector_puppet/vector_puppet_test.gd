extends Node2D
## Проверка векторной куклы (вид 3/4), собранной из файла по ТЗ для иллюстратора.
## Запуск: открыть сцену vector_puppet/vector_puppet_test.tscn в Godot и запустить текущую сцену
## (на Mac — Cmd+R или кнопка с хлопушкой вверху справа).
##
## Слева — исходный рисунок, в середине — кукла из вектора, справа — она же в размере игры и крупным планом.
## Клавиши: 1 — стойка, 2 — суставы по очереди, 3 — все суставы вместе,
##          S — одежда, B — веки, P — точки вращения, A — сглаживание краёв, Пробел — пауза.

const BG := Color("83a0a8")              ## Фон как на исходном рисунке, чтобы сравнивать честно
const INK := Color(0.08, 0.1, 0.12)
const GROUND_Y := 640.0
const BIG := 0.40                        ## Кукла ростом 1500 единиц → 600 точек экрана
const GAME := 0.167                      ## Размер «как в игре»: 250 точек
const CLOSE := 0.8                       ## Крупный план
const REF_H := 656.0                     ## Рост кошки на исходном рисунке, точек
const REF_GROUND := Vector2(196.0, 693.0)

## Суставы для проверки «по очереди»: кость, подпись.
const JOINTS := [
	["head", "голова"], ["neck", "шея"], ["torso", "корпус"],
	["ear_near", "ближнее ухо"], ["ear_far", "дальнее ухо"],
	["arm_near_upper", "ближнее плечо"], ["arm_near_fore", "ближний локоть"], ["paw_near", "ближняя кисть"],
	["arm_far_upper", "дальнее плечо"], ["arm_far_fore", "дальний локоть"], ["paw_far", "дальняя кисть"],
	["leg_near_thigh", "ближнее бедро"], ["leg_near_shin", "ближнее колено"], ["foot_near", "ближняя стопа"],
	["leg_far_thigh", "дальнее бедро"], ["leg_far_shin", "дальнее колено"], ["foot_far", "дальняя стопа"],
]
const SWING := 45.0                      ## Проверка из ТЗ: каждая часть поворачивается на 45° в обе стороны
const SMALL_SWING := {"neck": 20.0, "torso": 15.0, "head": 25.0, "ear_near": 25.0, "ear_far": 25.0}

var puppets: Array[VecPuppet] = []
var mode: int = 1
var t: float = 0.0
var paused: bool = false
var smooth: bool = true
var show_pivots: bool = false
var lids: int = 0
var hint: Label
var joint_label: Label
var overlay: Node2D
var hidden_panels: Array[CanvasLayer] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var fx: Node = get_node_or_null("/root/FX")      # панель «Эффекты» из игры здесь мешает
	if fx:
		for child in fx.get_children():
			var panel := child as CanvasLayer
			if panel and panel.visible and panel.layer == 16:
				panel.visible = false
				hidden_panels.append(panel)

	var ref := Sprite2D.new()
	ref.texture = load("res://vector_puppet/ref_34.png")
	ref.centered = false
	var k: float = 1500.0 * BIG / REF_H
	ref.scale = Vector2(k, k)
	ref.position = Vector2(175.0, GROUND_Y) - REF_GROUND * k
	add_child(ref)
	_label(Vector2(95, 660), "Исходный рисунок")

	_add_puppet(Vector2(480.0, GROUND_Y), BIG, "Кукла из вектора")
	_add_puppet(Vector2(735.0, GROUND_Y), GAME, "Размер как в игре")
	# Крупный план живёт в своей рамке: всё, что выходит за неё, обрезается и не закрывает соседей.
	var frame := ColorRect.new()
	frame.color = BG.darkened(0.06)
	frame.position = Vector2(870.0, 70.0)
	frame.size = Vector2(410.0, 570.0)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_add_puppet(Vector2(1075.0, 1290.0) - frame.position, CLOSE, "", frame)
	_label(Vector2(1010, 660), "Крупный план")

	overlay = Node2D.new()
	overlay.z_index = 50
	overlay.draw.connect(_draw_pivots)
	add_child(overlay)
	joint_label = _label(Vector2(400, 52), "")
	joint_label.add_theme_font_size_override("font_size", 22)
	hint = _label(Vector2(20, 14), "")
	_update_hint()


func _exit_tree() -> void:
	for panel in hidden_panels:
		if is_instance_valid(panel):
			panel.visible = true
	VecMesh.set_smooth(true)


func _add_puppet(pos: Vector2, zoom: float, text: String, parent: Node = self) -> void:
	var p := VecPuppet.new()
	p.position = pos
	p.scale = Vector2(zoom, zoom)
	parent.add_child(p)
	puppets.append(p)
	if text != "":
		_label(Vector2(pos.x - 80.0, 660), text)


func _label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", INK)
	l.z_index = 60
	add_child(l)
	return l


func _update_hint() -> void:
	var m: String = ["", "стойка", "суставы по очереди", "все суставы вместе"][mode]
	var lid: String = ["открыты", "прищур", "закрыты"][lids]
	hint.text = "1 · 2 · 3 — режим: %s      S — одежда      B — веки: %s      P — точки вращения      A — сглаживание: %s      Пробел — пауза" % [m, lid, "вкл" if smooth else "выкл"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match int(event.physical_keycode):
			KEY_1, KEY_2, KEY_3:
				mode = int(event.physical_keycode) - KEY_0
				t = 0.0
			KEY_SPACE:
				paused = not paused
			KEY_S:
				for p in puppets:
					p.set_clothes(not p.clothes_on)
			KEY_B:
				lids = (lids + 1) % 3
				for p in puppets:
					p.set_eyes(["open", "half", "closed"][lids])
			KEY_P:
				show_pivots = not show_pivots
			KEY_A:
				smooth = not smooth
				VecMesh.set_smooth(smooth)
		_update_hint()


func _process(delta: float) -> void:
	if not paused:
		t += delta
	pose_at(t)
	overlay.queue_redraw()


## Поза в момент времени (вынесено отдельно, чтобы проверка могла поставить любой момент).
func pose_at(time: float) -> void:
	joint_label.text = ""
	for p in puppets:
		p.reset_pose()
	match mode:
		2:
			var period: float = 2.4                       # секунд на один сустав
			var i: int = int(time / period) % JOINTS.size()
			var bone: String = JOINTS[i][0]
			var amp: float = SMALL_SWING.get(bone, SWING)
			var a: float = amp * sin(TAU * time / period)
			for p in puppets:
				p.set_deg(bone, a)
			joint_label.text = "%s: %+.0f°" % [JOINTS[i][1], a]
		3:
			for p in puppets:
				p.set_deg("head", 10.0 * sin(time * 1.3))
				p.set_deg("torso", 5.0 * sin(time * 0.9))
				p.set_deg("ear_near", 12.0 * sin(time * 3.1))
				p.set_deg("ear_far", 12.0 * sin(time * 3.1 + 1.0))
				p.set_deg("arm_near_upper", 40.0 * sin(time * 1.7) + (95.0 if fmod(time, 12.0) > 8.0 else 0.0))   # иногда рука поднимается к голове
				p.set_deg("arm_near_fore", -35.0 + 35.0 * cos(time * 1.7))
				p.set_deg("paw_near", 20.0 * sin(time * 2.9))
				p.set_deg("arm_far_upper", -40.0 * sin(time * 1.7))
				p.set_deg("arm_far_fore", -35.0 - 35.0 * cos(time * 1.7))
				p.set_deg("leg_near_thigh", -28.0 * sin(time * 1.7))
				p.set_deg("leg_near_shin", 22.0 - 22.0 * cos(time * 1.7 + 0.6))
				p.set_deg("foot_near", 12.0 * sin(time * 1.7))
				p.set_deg("leg_far_thigh", 28.0 * sin(time * 1.7))
				p.set_deg("leg_far_shin", 22.0 + 22.0 * cos(time * 1.7 + 0.6))
				p.set_deg("foot_far", -12.0 * sin(time * 1.7))
				p.look(Vector2(14.0 * sin(time * 0.8), 0.0))


func _draw_pivots() -> void:
	if not show_pivots:
		return
	for p in puppets.slice(0, 2):                 # у крупного плана точки не рисуем: он обрезан рамкой
		for bone in p.bones.values():
			var pos: Vector2 = (bone as Node2D).global_position
			overlay.draw_circle(pos, 5.0, Color(0, 0, 0))
			overlay.draw_circle(pos, 3.5, Color(1, 0, 1))
