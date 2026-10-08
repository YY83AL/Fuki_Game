class_name FukiRed
extends Node2D
## Кукла красной кошки (вид 3/4, лицом вправо). Части: голова, плащ (торс), две руки, две ноги, два сапога.
## Лицо рисуется кодом поверх головы: моргание и эмоции (V — сменить эмоцию).
## Ноги тянутся от бедра к стопе («мягкий IK»), поэтому шаг, присед, сидение и прыжок получаются сами.
## Подключается к Player так же, как другие куклы: Player вызывает animate(delta, скорость, направление, в_воздухе).
##
## Клавиши (пока управляешь Фуки): W — смотреть вверх, X — смотреть вниз, S — присесть (держать),
## I — толкать (держать), F — помахать, G — ушиб, H — дрожь (вкл/выкл), J — испуг, T — сесть/встать,
## Y — бросок, U — поднять предмет, O — осмотреться, P — упасть и исчезнуть / вернуться.

@export var frame_scale: float = 0.44            ## Размер кошки (1 — как на рисунке, 0.44 ≈ как жёлтый кот)
@export var walk_cycle: float = 8.5              ## Скорость шагов при ходьбе, рад/с
@export var run_cycle: float = 14.0              ## Скорость шагов при беге
@export var walk_stride: float = 50.0            ## Размах шага при ходьбе (px рисунка)
@export var run_stride: float = 108.0            ## Размах шага при беге
@export var run_threshold: float = 1.25
@export var turn_seconds: float = 0.10
@export var crouch_seconds: float = 0.06         ## Присед перед прыжком
@export var land_seconds: float = 0.16
@export var keys_enabled: bool = true            ## Включить клавиши показа анимаций

signal action_started(name: String)
signal action_finished(name: String)

# --- геометрия (координаты рисунка относительно точки земли под ногами; рисунок 3/4, нарисован лицом вправо) ---
const HIP := Vector2(2.0, -179.0)            # центр бёдер (точка вращения плаща)
const HIP_L := Vector2(-21.0, -179.0)        # бедро левой (для зрителя) ноги
const HIP_R := Vector2(25.0, -179.0)
const ANKLE_L := Vector2(-24.0, -93.0)       # стопы в покое
const ANKLE_R := Vector2(35.0, -95.0)
const LEG_LEN := 86.0
const NECK := Vector2(-2.0, -256.0)          # относительно плаща
const SH_L := Vector2(-44.0, -231.0)         # плечи (относительно плаща)
const SH_R := Vector2(44.0, -228.0)
const TORSO_POS := Vector2(-114.0, -274.0)
const HEAD_POS := Vector2(-142.0, -225.0)
const ARM_L_POS := Vector2(-109.0, -17.0)
const ARM_R_POS := Vector2(-4.0, -11.0)
const LEG_L_POS := Vector2(-24.0, -8.0)
const LEG_R_POS := Vector2(-22.0, -8.0)
const BOOT_L_POS := Vector2(-33.0, -21.0)
const BOOT_R_POS := Vector2(-32.0, -19.0)
# глаза в пикселях картинки головы: центр, радиусы
const EYES := [Vector3(97.0, 154.0, 1.0), Vector3(210.0, 153.0, -1.0)]
const EYE_R := [Vector2(38.0, 36.0), Vector2(27.0, 33.0)]
const FUR := Color(0.988, 0.980, 0.968)

const REST := {
	"bx": 0.0, "by": 0.0, "up": 0.0, "tr": 0.0, "tsy": 1.0,
	"hr": 0.0, "hx": 0.0, "hy": 0.0, "hsx": 1.0,
	"ar": 0.0, "ar2": 0.0, "ax": 0.0, "ay": 0.0,
	"nfx": 0.0, "nfy": 0.0, "nfr": 0.0, "ffx": 0.0, "ffy": 0.0, "ffr": 0.0,
	"shake": 0.0, "alpha": 1.0, "tint": 0.0, "item": 0.0, "bang": 0.0,
}

## Анимации по кадрам: [время, {параметры}]; всё, что не указано, берётся из позы покоя.
const ACTIONS := {
	"hurt": {"dur": 0.9, "keys": [
		[0.00, {}],
		[0.06, {"tr": -14.0, "hr": -22.0, "hx": -6.0, "bx": -10.0, "ar": 25.0, "nfx": -10.0, "ffx": 8.0, "tint": 0.3}],
		[0.20, {"tr": -6.0, "hr": -10.0, "bx": -5.0, "ar": 15.0, "tint": 0.15, "by": 6.0}],
		[0.36, {"tr": 15.0, "hr": 24.0, "hy": 6.0, "by": 18.0, "tsy": 0.96, "ar": -10.0}],
		[0.55, {"tr": 10.0, "hr": 17.0, "hy": 4.0, "by": 12.0}],
		[0.90, {}]]},
	"pickup": {"dur": 2.3, "keys": [
		[0.00, {}],
		[0.25, {"tr": 20.0, "by": 30.0, "hr": 10.0, "ar": -5.0}],
		[0.60, {"tr": 50.0, "by": 82.0, "hr": 24.0, "hx": 8.0, "tsy": 0.94, "ar": -70.0, "nfx": 28.0, "ffx": -20.0}],
		[0.90, {"tr": 50.0, "by": 82.0, "hr": 24.0, "hx": 8.0, "tsy": 0.94, "ar": -70.0, "nfx": 28.0, "ffx": -20.0, "item": 1.0}],
		[1.30, {"tr": 22.0, "by": 40.0, "hr": 6.0, "ar": -78.0, "item": 1.0}],
		[1.70, {"tr": 2.0, "by": 0.0, "hr": -6.0, "ar": -60.0, "item": 1.0}],
		[2.05, {"ar": -56.0, "hr": -8.0, "item": 1.0}],
		[2.30, {"item": 1.0}]]},
	"throw": {"dur": 1.2, "keys": [
		[0.00, {"item": 1.0}],
		[0.28, {"tr": -10.0, "ar": 150.0, "hr": -6.0, "bx": -6.0, "nfx": -16.0, "ffx": 26.0, "item": 1.0}],
		[0.44, {"tr": 14.0, "ar": -120.0, "hr": 4.0, "bx": 8.0, "nfx": 30.0, "ffx": -22.0, "item": 0.0}],
		[0.60, {"tr": 12.0, "ar": -105.0, "bx": 8.0, "nfx": 30.0, "ffx": -22.0}],
		[1.20, {}]]},
	"startle": {"dur": 1.0, "keys": [
		[0.00, {}],
		[0.07, {"by": 28.0, "tsy": 0.94, "tr": 6.0}],
		[0.20, {"up": 62.0, "tr": -13.0, "hr": -10.0, "ar": -50.0, "nfy": -30.0, "ffy": -22.0, "nfx": 16.0, "ffx": -18.0, "bang": 1.0}],
		[0.38, {"up": 30.0, "tr": -10.0, "hr": -8.0, "ar": -35.0, "bang": 1.0}],
		[0.55, {"by": 14.0, "tsy": 0.95, "tr": -4.0, "bang": 1.0}],
		[0.75, {"bang": 1.0}],
		[1.00, {}]]},
	"death": {"dur": 3.4, "hold": true, "keys": [
		[0.00, {}],
		[0.10, {"tr": -14.0, "hr": -22.0, "hx": -6.0, "bx": -10.0, "ar": 25.0, "tint": 0.2}],
		[0.45, {"tr": -18.0, "hr": -30.0, "bx": -14.0, "tint": 0.2}],
		[0.90, {"by": 70.0, "tr": 22.0, "hr": 24.0, "tsy": 0.9, "nfx": 20.0, "ffx": -14.0, "tint": 0.25}],
		[1.40, {"by": 128.0, "tr": 62.0, "hr": 48.0, "hx": 12.0, "tsy": 0.8, "ar": -35.0, "nfx": 52.0, "ffx": 12.0, "nfy": 10.0, "tint": 0.35, "bx": 10.0}],
		[1.95, {"by": 150.0, "tr": 80.0, "hr": 62.0, "hx": 20.0, "tsy": 0.72, "ar": -30.0, "nfx": 56.0, "ffx": 14.0, "nfy": 10.0, "tint": 0.6, "bx": 16.0}],
		[2.60, {"by": 150.0, "tr": 80.0, "hr": 62.0, "hx": 20.0, "tsy": 0.72, "ar": -30.0, "nfx": 56.0, "ffx": 14.0, "nfy": 10.0, "tint": 1.0, "bx": 16.0, "alpha": 0.75}],
		[3.40, {"by": 150.0, "tr": 80.0, "hr": 62.0, "hx": 20.0, "tsy": 0.72, "ar": -30.0, "nfx": 56.0, "ffx": 14.0, "nfy": 10.0, "tint": 1.0, "bx": 16.0, "alpha": 0.0}]]},
}

## Позы, которые включаются плавно, пока клавиша зажата / режим включён
const HOLDS := {
	"crouch": {"by": 84.0, "tr": 16.0, "tsy": 0.9, "hr": 8.0, "hx": 4.0, "nfx": 34.0, "ffx": -20.0, "nfr": -4.0, "ffr": 4.0, "ar": -12.0},
	"lookup": {"hr": -30.0, "hy": -2.0, "tr": -3.0, "ar": 4.0},
	"lookdown": {"hr": 26.0, "hy": 7.0, "hx": 3.0, "tr": 4.0, "ar": -4.0},
	"push": {"tr": 22.0, "hr": -10.0, "ar": -88.0, "hx": 6.0},
	"shiver": {"tr": 8.0, "hr": 7.0, "hy": 5.0, "tsy": 0.98, "ar": -14.0},
	"sit": {"by": 150.0, "bx": -12.0, "tr": -3.0, "tsy": 0.98, "hr": -6.0, "ar": -38.0,
		"nfx": 108.0, "nfy": 56.0, "nfr": -78.0, "ffx": 90.0, "ffy": 62.0, "ffr": -80.0},
}

var flip: Node2D
var torso_n: Node2D
var head_n: Node2D
var arm_l_n: Node2D
var arm_r_n: Node2D
var leg_l_n: Node2D
var leg_r_n: Node2D
var boot_l_n: Node2D
var boot_r_n: Node2D
var torso: Sprite2D
var head: Sprite2D
var face: Node2D
var item_node: Polygon2D
var bang_label: Label
var mat: ShaderMaterial

var facing: float = 1.0
var turn_left: float = 0.0
var turn_from: float = 1.0
var phi: float = 0.0
var t: float = 0.0
var idle_t: float = 0.0
var gait_w: float = 0.0
var run_w: float = 0.0
var air_time: float = 0.0
var was_in_air: bool = false
var land_left: float = 0.0
var coat_drag: float = 0.0
var coat_drag_v: float = 0.0
var coat_lift: float = 0.0
var coat_lift_v: float = 0.0
var action: String = ""
var action_t: float = 0.0
var hold_w := {"crouch": 0.0, "lookup": 0.0, "lookdown": 0.0, "push": 0.0, "shiver": 0.0, "sit": 0.0}
var hold_on := {"shiver": false, "sit": false}
var dead: bool = false
var force_hold := {}              ## для тестов: принудительно включить зажимаемую позу

# лицо
const EMOS := ["neutral", "happy", "surprised", "sad", "angry", "crying"]
var emo_index: int = 0
var emo_override: String = ""
var blink_t: float = 2.5
var blink_left: float = 0.0
var tear_t: float = 0.0


func _tex(n: String) -> Texture2D:
	return load("res://assets/characters/red/%s.png" % n)


func _sprite(tex_name: String, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex(tex_name)
	s.centered = false
	s.position = pos
	return s


func _joint(parent: Node2D, tex_name: String, pos: Vector2) -> Node2D:
	var j := Node2D.new()
	parent.add_child(j)
	j.add_child(_sprite(tex_name, pos))
	return j


func _ready() -> void:
	flip = Node2D.new()
	flip.name = "Flip"
	add_child(flip)
	# порядок: ноги и сапоги, плащ, руки, голова
	leg_l_n = _joint(flip, "leg_l", LEG_L_POS)
	boot_l_n = _joint(flip, "boot_l", BOOT_L_POS)
	leg_r_n = _joint(flip, "leg_r", LEG_R_POS)
	boot_r_n = _joint(flip, "boot_r", BOOT_R_POS)
	torso_n = Node2D.new()
	flip.add_child(torso_n)
	torso = _sprite("torso", TORSO_POS)
	torso_n.add_child(torso)
	mat = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/coat_red.gdshader")
	mat.set_shader_parameter("y_top", 40.0)
	mat.set_shader_parameter("y_hem", 285.0)
	torso.material = mat
	arm_l_n = _joint(torso_n, "arm_l", ARM_L_POS)
	arm_r_n = _joint(torso_n, "arm_r", ARM_R_POS)
	# предмет в лапке (жёлтый шарик-ключ), цепляется к правой руке
	item_node = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * i / 20.0
		pts.append(Vector2(cos(a) * 15.0, sin(a) * 15.0))
	item_node.polygon = pts
	item_node.color = Color(0.98, 0.78, 0.22)
	item_node.position = Vector2(12.0, 160.0)
	item_node.visible = false
	arm_r_n.add_child(item_node)
	head_n = _joint(torso_n, "head", HEAD_POS)
	head = head_n.get_child(0)
	face = Node2D.new()
	face.position = HEAD_POS
	face.draw.connect(_draw_face)
	head_n.add_child(face)
	bang_label = Label.new()
	bang_label.text = "!!"
	bang_label.add_theme_font_size_override("font_size", 92)
	bang_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.22))
	bang_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.07))
	bang_label.add_theme_constant_override("outline_size", 14)
	bang_label.position = Vector2(30.0, -720.0)
	bang_label.visible = false
	add_child(bang_label)
	scale = Vector2(frame_scale, frame_scale)
	_apply(REST.duplicate())


# ---------- лицо: моргание и эмоции ----------

func emotion() -> String:
	return emo_override if emo_override != "" else EMOS[emo_index]


func _draw_face() -> void:
	var emo: String = emotion()
	var blink: float = 0.0
	if blink_left > 0.0:
		blink = sin(clampf(1.0 - blink_left / 0.14, 0.0, 1.0) * PI)
	if emo == "closed":
		blink = 1.0
	var lines := Color(0.06, 0.05, 0.06)
	for i in 2:
		var e: Vector3 = EYES[i]
		var c := Vector2(e.x, e.y)
		var r: Vector2 = EYE_R[i]
		var inner: float = -e.z        # в какую сторону «внутренний» угол глаза (к носу)
		var cover := PackedVector2Array()
		var need_cover: bool = (blink > 0.5) or emo in ["happy", "squint", "closed"]
		if need_cover:
			# закрыть глаз цветом шерсти
			for k in 28:
				var a: float = TAU * k / 28.0
				cover.append(c + Vector2(cos(a) * (r.x + 7.0), sin(a) * (r.y + 7.0)))
			face.draw_colored_polygon(cover, FUR)
			if emo == "happy":
				face.draw_arc(c + Vector2(0, r.y * 0.45), r.x * 0.8, PI * 1.12, PI * 1.88, 18, lines, 5.0, true)
			elif emo == "squint":
				var d: float = 1.0 if i == 0 else -1.0       # «>» слева, «<» справа
				var p1 := c + Vector2(-d * r.x * 0.7, -r.y * 0.55)
				var p2 := c + Vector2(d * r.x * 0.7, 0.0)
				var p3 := c + Vector2(-d * r.x * 0.7, r.y * 0.55)
				face.draw_polyline(PackedVector2Array([p1, p2, p3]), lines, 5.0, true)
			else:
				face.draw_arc(c + Vector2(0, -r.y * 0.35), r.x * 0.8, PI * 0.12, PI * 0.88, 18, lines, 5.0, true)
		elif emo == "surprised":
			for k in 28:
				var a2: float = TAU * k / 28.0
				cover.append(c + Vector2(cos(a2) * (r.x + 6.0), sin(a2) * (r.y + 6.0)))
			face.draw_colored_polygon(cover, FUR)
			var big := PackedVector2Array()
			var pup := PackedVector2Array()
			for k in 32:
				var a3: float = TAU * k / 32.0
				big.append(c + Vector2(cos(a3) * (r.x + 4.0), sin(a3) * (r.y + 6.0)))
				pup.append(c + Vector2(cos(a3) * r.x * 0.50, sin(a3) * r.y * 0.62) + Vector2(inner * -2.0, 0))
			face.draw_colored_polygon(big, lines)
			var white := PackedVector2Array()
			for k in 32:
				var a4: float = TAU * k / 32.0
				white.append(c + Vector2(cos(a4) * (r.x + 0.5), sin(a4) * (r.y + 2.0)))
			face.draw_colored_polygon(white, Color(1, 1, 1))
			face.draw_colored_polygon(pup, lines)
		elif emo in ["sad", "angry", "crying"]:
			# верхнее веко наклонено: грусть — внутренние края вверх, злость — вниз
			var inner_up: float = 1.0 if emo != "angry" else -1.0
			var pa: Vector2 = c + Vector2(-inner * r.x * 1.35, r.y * (0.25 if inner_up > 0 else -0.65))    # внешний край
			var pb: Vector2 = c + Vector2(inner * r.x * 1.35, r.y * (-0.65 if inner_up > 0 else 0.25))      # внутренний край
			var ell := PackedVector2Array()
			for k in 32:
				var a5: float = TAU * k / 32.0
				ell.append(c + Vector2(cos(a5) * (r.x + 6.0), sin(a5) * (r.y + 6.0)))
			var dirv: Vector2 = (pb - pa).normalized()
			var up_n: Vector2 = Vector2(dirv.y, -dirv.x)       # нормаль «вверх» от линии века
			var hp := PackedVector2Array([pa - dirv * 200.0, pb + dirv * 200.0, pb + dirv * 200.0 + up_n * 200.0, pa - dirv * 200.0 + up_n * 200.0])
			var inter: Array = Geometry2D.intersect_polygons(ell, hp)
			var lid := PackedVector2Array()
			if inter.size() > 0:
				lid = inter[0]
			else:
				lid = PackedVector2Array([pa, pb, pb + up_n * 2.0, pa + up_n * 2.0])
			if lid.size() >= 3:
				face.draw_colored_polygon(lid, FUR)
			face.draw_line(pa, pb, lines, 5.0, true)
			if emo == "crying":
				var ph: float = fposmod(tear_t * 1.4 + i * 0.5, 1.0)
				var tx: float = c.x - inner * r.x * 0.2
				var ty: float = c.y + r.y * 0.8 + ph * 62.0
				face.draw_circle(Vector2(tx, ty), 7.0 * (1.0 - ph * 0.5), Color(0.55, 0.78, 0.95, 1.0 - ph * 0.8))
				face.draw_circle(Vector2(tx + inner * 2.0, c.y + r.y * 0.9), 5.0, Color(0.55, 0.78, 0.95, 0.7))


func _face_update(delta: float) -> void:
	tear_t += delta
	if blink_left > 0.0:
		blink_left -= delta
	else:
		blink_t -= delta
		if blink_t <= 0.0:
			blink_left = 0.14
			blink_t = randf_range(2.2, 5.5)
	face.queue_redraw()


# ---------- вспомогательное ----------

static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var r := {}
	for k in a:
		r[k] = lerpf(a[k], b[k], w)
	return r


static func _full(d: Dictionary) -> Dictionary:
	var r: Dictionary = REST.duplicate()
	for k in d:
		r[k] = d[k]
	return r


func _action_pose(name: String, tt: float) -> Dictionary:
	if name == "wave":
		var up: float = smoothstep(0.0, 0.25, tt) * (1.0 - smoothstep(2.0, 2.4, tt))
		var p := _full({})
		p["ar"] = lerpf(0.0, -140.0, up) + sin(tt * 14.0) * 16.0 * up
		p["hr"] = -6.0 * up + sin(tt * 3.0) * 2.0 * up
		p["tr"] = -2.0 * up
		p["hy"] = -2.0 * up
		return p
	if name == "lookaround":
		var p2 := _full({})
		var s1: float = sin(tt * 2.6)
		var e: float = smoothstep(0.0, 0.3, tt) * (1.0 - smoothstep(2.1, 2.6, tt))
		p2["hr"] = (-8.0 + 12.0 * s1) * e
		p2["hx"] = (6.0 * s1) * e
		p2["hsx"] = 1.0 - 0.14 * absf(s1) * e
		p2["tr"] = (1.5 * s1) * e
		p2["hy"] = (-2.0 * absf(s1)) * e
		return p2
	var def: Dictionary = ACTIONS[name]
	var keys: Array = def["keys"]
	if tt <= keys[0][0]:
		return _full(keys[0][1])
	for i in range(1, keys.size()):
		if tt <= keys[i][0]:
			var t0: float = keys[i - 1][0]
			var t1: float = keys[i][0]
			var u: float = smoothstep(0.0, 1.0, (tt - t0) / maxf(t1 - t0, 0.0001))
			return _mix(_full(keys[i - 1][1]), _full(keys[i][1]), u)
	return _full(keys[keys.size() - 1][1])


func _action_dur(name: String) -> float:
	if name == "wave":
		return 2.4
	if name == "lookaround":
		return 2.6
	return ACTIONS[name]["dur"]


func play(name: String) -> void:
	if dead and name != "death":
		return
	action = name
	action_t = 0.0
	action_started.emit(name)


func stop_action() -> void:
	if action != "":
		var n := action
		action = ""
		emo_override = ""
		action_finished.emit(n)


func _player() -> Node:
	var p := get_parent()
	if p and p.get_parent():
		return p.get_parent()
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not keys_enabled:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var pl := _player()
	var active: bool = true
	if pl and pl.get("active") != null:
		active = pl.active
	if not active and not dead:
		return
	match event.physical_keycode:
		KEY_P:
			if dead:
				dead = false
				action = ""
				emo_override = ""
				if pl:
					pl.active = true
			else:
				play("death")
				dead = true
				if pl:
					pl.active = false
		KEY_F: play("wave")
		KEY_G: play("hurt")
		KEY_J: play("startle")
		KEY_Y: play("throw")
		KEY_U: play("pickup")
		KEY_O: play("lookaround")
		KEY_V: emo_index = (emo_index + 1) % EMOS.size()
		KEY_H: hold_on["shiver"] = not hold_on["shiver"]
		KEY_T: hold_on["sit"] = not hold_on["sit"]


# ---------- основная анимация ----------

func animate(delta: float, speed_ratio: float, face_dir: float, in_air: bool) -> void:
	t += delta
	if face_dir != 0.0 and face_dir != facing:
		if not in_air and turn_seconds > 0.0 and not dead:
			turn_from = facing
			turn_left = turn_seconds
		facing = face_dir
	var sx: float = facing
	if turn_left > 0.0 and not in_air:
		turn_left -= delta
		var k: float = 1.0 - clampf(turn_left / turn_seconds, 0.0, 1.0)
		var v: float = lerpf(turn_from, facing, k)
		sx = signf(v) * maxf(absf(v), 0.35)
	flip.scale.x = sx

	var pl := _player()
	var active: bool = true
	if pl and pl.get("active") != null:
		active = pl.active
	var want := {"crouch": false, "lookup": false, "lookdown": false, "push": false}
	if active and keys_enabled and not dead:
		want["crouch"] = Input.is_physical_key_pressed(KEY_S) and not in_air
		want["lookup"] = Input.is_physical_key_pressed(KEY_W)
		want["lookdown"] = Input.is_physical_key_pressed(KEY_X)
		want["push"] = Input.is_physical_key_pressed(KEY_I)
	if hold_on["sit"] and (speed_ratio > 0.2 or in_air):
		hold_on["sit"] = false
	want["shiver"] = hold_on["shiver"] and speed_ratio < 0.1 and not in_air
	want["sit"] = hold_on["sit"]
	for fk in force_hold:
		want[fk] = force_hold[fk]
	for k in hold_w:
		var target: float = 1.0 if want.get(k, false) else 0.0
		hold_w[k] = move_toward(hold_w[k], target, delta * (6.0 if k != "sit" else 3.5))

	var air_speed: float = 0.0
	if pl and pl.get("air_speed") != null:
		air_speed = pl.air_speed
	if in_air:
		if not was_in_air:
			air_time = 0.0
		air_time += delta
		land_left = land_seconds
	elif land_left > 0.0:
		land_left -= delta
	was_in_air = in_air

	var pose: Dictionary = _locomotion(delta, speed_ratio, in_air, air_speed)
	for k in hold_w:
		if hold_w[k] > 0.001:
			var target_pose: Dictionary = _full(HOLDS[k])
			if k == "push":
				target_pose = _push_pose(speed_ratio)
			elif k == "shiver":
				target_pose["shake"] = 2.4
			pose = _mix(pose, target_pose, hold_w[k])
	# выражение лица от действий
	emo_override = ""
	if hold_w["shiver"] > 0.5:
		emo_override = "sad"
	if action != "":
		action_t += delta
		var dur: float = _action_dur(action)
		var done: bool = action_t >= dur
		var aw_in: float = smoothstep(0.0, 0.07, action_t)
		var aw_out: float = 1.0
		if ACTIONS.has(action) and ACTIONS[action].get("hold", false):
			done = false
			action_t = minf(action_t, dur)
		else:
			aw_out = 1.0 - smoothstep(dur - 0.12, dur, action_t)
		var ap: Dictionary = _action_pose(action, minf(action_t, dur))
		pose = _mix(pose, ap, minf(aw_in, aw_out))
		var em: String = ACTION_EMO.get(action, "")
		if em != "":
			if action == "hurt" and action_t > 0.7:
				em = ""
			if action == "startle" and action_t > 0.8:
				em = ""
			emo_override = em
		if done:
			stop_action()
	_update_coat(delta, speed_ratio, air_speed, in_air)
	_face_update(delta)
	_apply(pose)


const ACTION_EMO := {"hurt": "squint", "startle": "surprised", "wave": "happy", "death": "closed", "throw": "", "pickup": ""}


func _push_pose(speed_ratio: float) -> Dictionary:
	var p: Dictionary = _full(HOLDS["push"])
	p["ar"] = -88.0 + sin(t * 8.0) * 4.0 * clampf(speed_ratio, 0.0, 1.0)
	p["ar2"] = -70.0
	p["nfx"] = 22.0 * sin(phi) * gait_w
	p["ffx"] = -22.0 * sin(phi) * gait_w
	p["nfy"] = -10.0 * maxf(0.0, cos(phi)) * gait_w
	p["ffy"] = -10.0 * maxf(0.0, -cos(phi)) * gait_w
	p["by"] = 8.0
	return p


func _locomotion(delta: float, speed_ratio: float, in_air: bool, air_speed: float) -> Dictionary:
	idle_t += delta
	var moving: bool = speed_ratio > 0.05 and not in_air
	gait_w = move_toward(gait_w, 1.0 if moving else 0.0, delta * 9.0)
	var want_run: float = smoothstep(run_threshold * 0.85, run_threshold * 1.15, speed_ratio)
	run_w = move_toward(run_w, want_run if moving else 0.0, delta * 7.0)
	if moving:
		phi += delta * lerpf(walk_cycle * clampf(speed_ratio, 0.5, 1.2), run_cycle * clampf(speed_ratio / 1.75, 0.6, 1.2), run_w)
	var p: Dictionary = _full({})
	var breathe: float = sin(idle_t * 2.1)
	var idle_k: float = 1.0 - gait_w
	p["tsy"] = 1.0 + 0.010 * breathe * idle_k
	p["hy"] = 1.0 * breathe * idle_k
	p["hr"] = sin(idle_t * 0.7) * 1.2 * idle_k
	p["ar"] = (sin(idle_t * 2.1 + 0.8) * 1.6) * idle_k
	p["ar2"] = (sin(idle_t * 2.1 + 2.0) * -1.6) * idle_k
	if gait_w > 0.001:
		var S: float = lerpf(walk_stride, run_stride, run_w)
		var lift: float = lerpf(20.0, 72.0, run_w)
		var sn: float = sin(phi)
		var cs: float = cos(phi)
		var sf: float = sin(phi + PI)
		var cf: float = cos(phi + PI)
		var nfx: float = S * sn
		var ffx: float = S * sf
		var nfy: float = -lift * maxf(0.0, cs)
		var ffy: float = -lift * maxf(0.0, cf)
		var drop: float = LEG_LEN - sqrt(maxf(LEG_LEN * LEG_LEN - minf(absf(nfx), 80.0) ** 2, 1.0))
		var by: float = drop * 0.9
		by += lerpf(0.0, -26.0 * absf(cs) + 6.0, run_w)
		var tr: float = lerpf(2.0, 13.0, run_w)
		var hr: float = lerpf(-1.5, -7.0, run_w) + sin(phi * 2.0) * lerpf(1.0, 2.0, run_w)
		var ar: float = lerpf(12.0, 30.0, run_w) * sn
		var nr: float = lerpf(14.0, 30.0, run_w) * maxf(0.0, -sn) - lerpf(8.0, 14.0, run_w) * maxf(0.0, sn) * maxf(0.0, cs) + lerpf(12.0, 18.0, run_w) * maxf(0.0, cs)
		var fr: float = lerpf(14.0, 30.0, run_w) * maxf(0.0, -sf) - lerpf(8.0, 14.0, run_w) * maxf(0.0, sf) * maxf(0.0, cf) + lerpf(12.0, 18.0, run_w) * maxf(0.0, cf)
		var w: Dictionary = {"nfx": nfx, "ffx": ffx, "nfy": nfy, "ffy": ffy, "by": by, "tr": tr,
			"hr": hr, "ar": -ar, "ar2": ar * 0.9, "nfr": nr, "ffr": fr, "hy": 0.0, "tsy": 1.0}
		for k in w:
			p[k] = lerpf(p[k], w[k], gait_w)
	if in_air:
		p = _mix(p, _air_pose(air_speed), 1.0)
	elif land_left > 0.0:
		var k2: float = clampf(land_left / land_seconds, 0.0, 1.0)
		var lj: Dictionary = _full({"by": 36.0, "tsy": 0.9, "tr": 12.0, "hr": 6.0, "nfx": 20.0, "ffx": -18.0, "ar": -14.0, "ar2": 14.0})
		p = _mix(p, lj, smoothstep(0.0, 1.0, k2))
	return p


func _air_pose(air_speed: float) -> Dictionary:
	if air_time < crouch_seconds:
		return _full({"by": 50.0, "tsy": 0.9, "tr": 14.0, "hr": 6.0, "nfx": 14.0, "ffx": -18.0, "ar": 18.0, "ar2": -18.0})
	var rise: float = smoothstep(-120.0, 380.0, air_speed)
	var fall: float = smoothstep(80.0, 520.0, -air_speed)
	var stretch: Dictionary = _full({"by": -12.0, "tr": 8.0, "hr": -6.0, "ar": -34.0, "ar2": 28.0, "nfx": -38.0, "nfy": -40.0, "nfr": 32.0, "ffx": -58.0, "ffy": -16.0, "ffr": 28.0})
	var tuck: Dictionary = _full({"by": -8.0, "tr": 6.0, "hr": -4.0, "ar": -42.0, "ar2": 32.0, "nfx": 22.0, "nfy": -74.0, "nfr": -12.0, "ffx": -24.0, "ffy": -60.0, "ffr": 12.0})
	var fallp: Dictionary = _full({"by": -6.0, "tr": 2.0, "hr": -2.0, "ar": -28.0, "ar2": 24.0, "nfx": 12.0, "nfy": -4.0, "nfr": -8.0, "ffx": -10.0, "ffy": 4.0, "ffr": 6.0})
	var base: Dictionary = _mix(tuck, stretch, smoothstep(0.35, 0.9, rise))
	return _mix(base, fallp, fall)


func _update_coat(delta: float, speed_ratio: float, air_speed: float, in_air: bool) -> void:
	var gust: float = Wind.gust * Wind.dir * facing
	var target: float = -speed_ratio * 16.0 + gust * 26.0
	coat_drag_v += ((target - coat_drag) * 90.0 - coat_drag_v * 9.0) * delta
	coat_drag += coat_drag_v * delta
	var lt: float = 0.0
	if in_air:
		lt = clampf(-air_speed / 700.0, -0.4, 1.0) * 30.0
	coat_lift_v += ((lt - coat_lift) * 80.0 - coat_lift_v * 8.0) * delta
	coat_lift += coat_lift_v * delta
	mat.set_shader_parameter("drag", coat_drag)
	mat.set_shader_parameter("lift", coat_lift)


func _apply(p: Dictionary) -> void:
	var shake_x: float = 0.0
	if p["shake"] > 0.0:
		shake_x = sin(t * 150.0) * p["shake"]
	var up: float = p["up"]
	var off := Vector2(p["bx"] + shake_x, p["by"] - up)
	torso_n.position = HIP + off
	torso_n.rotation = deg_to_rad(p["tr"])
	torso_n.scale = Vector2(1.0 + (1.0 - p["tsy"]) * 0.5, p["tsy"])
	head_n.position = NECK + Vector2(p["hx"], p["hy"])
	head_n.rotation = deg_to_rad(p["hr"])
	head_n.scale = Vector2(p["hsx"], 1.0)
	arm_r_n.position = SH_R + Vector2(p["ax"], p["ay"])
	arm_r_n.rotation = deg_to_rad(p["ar"])
	arm_r_n.scale.x = 1.0 + 0.8 * clampf(absf(p["ar"]) / 100.0, 0.0, 1.0)     # рука разворачивается к зрителю
	arm_l_n.position = SH_L
	arm_l_n.rotation = deg_to_rad(p["ar2"])
	item_node.visible = p["item"] > 0.5
	bang_label.visible = p["bang"] > 0.5
	# ноги: левая (для зрителя) — «ближняя» фаза nf, правая — ff
	_leg(leg_l_n, boot_l_n, HIP_L + off, ANKLE_L + Vector2(p["nfx"], p["nfy"] - up), p["nfr"])
	_leg(leg_r_n, boot_r_n, HIP_R + off, ANKLE_R + Vector2(p["ffx"], p["ffy"] - up), p["ffr"])
	var tn: float = p["tint"]
	flip.modulate = Color(lerpf(1.0, 0.78, tn), lerpf(1.0, 0.86, tn), lerpf(1.0, 0.92, tn), p["alpha"])


func _leg(leg_node: Node2D, boot_node: Node2D, hip: Vector2, foot: Vector2, boot_rot_deg: float) -> void:
	var v: Vector2 = foot - hip
	var len: float = maxf(v.length(), 1.0)
	leg_node.position = hip
	leg_node.rotation = atan2(-v.x, v.y)
	leg_node.scale = Vector2(1.0, clampf(len / LEG_LEN, 0.25, 1.5))
	boot_node.position = foot
	boot_node.rotation = deg_to_rad(boot_rot_deg)
