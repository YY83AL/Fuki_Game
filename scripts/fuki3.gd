class_name Fuki3
extends Node2D
## Фуки (персонаж 2, «кукла»): голова, плащ и две ноги — сетки, которые гнутся по суставам
## (без швов), плащ — сетка точек с физикой. Разворот — короткая покадровая анимация.
## Рисунок смотрит вправо; влево отзеркаливается.
##
## Метод animate() вызывается из player.gd каждый кадр (тот же, что у fuki2.gd).

@export_group("Ходьба")
@export var cycle_seconds: float = 0.5            ## Секунд на полный цикл шагов при полной скорости (меньше — шаги чаще)
@export var leg_swing_deg: float = 26.0           ## Размах ног
@export var knee_bend_deg: float = 34.0           ## Сгиб колена при переносе ноги
@export var leg_spread: float = 0.5               ## Насколько ноги сведены к центру при коротких ногах (1 — как раньше, меньше — ближе друг к другу)
@export var leg_shorten: float = 3.0              ## Во сколько раз короче ноги, торчащие из-под плаща (1 — как раньше; кадры разворота подогнаны под 3)
@export var lean_deg: float = 1.6                 ## Покачивание корпуса
@export var forward_lean_deg: float = 2.5         ## Наклон вперёд на ходу
@export var head_bob_deg: float = 2.5             ## Покачивание головы в такт шагам
@export_group("Плащ")
@export var cape_wind: float = 130.0              ## Сила порывов ветра (пикселей)
@export var cape_idle_breeze: float = 0.22        ## Лёгкое колыхание плаща, когда Фуки стоит (0 — выключить)
@export var cape_step_kick: float = 45.0          ## Как сильно плащ качается в такт шагам
@export var cape_bounce: float = 0.06             ## Реакция плаща на подпрыгивание при шаге
@export var cape_hang_shift: float = 215.0        ## Насколько плащ «повисает» вниз, когда Фуки стоит
@export var cape_stiffness_top: float = 40.0      ## Жёсткость у плеч (больше — плащ жёстче)
@export var cape_stiffness_hem: float = 9.0       ## Жёсткость у подола (меньше — свободнее качается)
@export var cape_damping: float = 0.30            ## Затухание качания (0 — качается вечно)
@export var cape_pencil: bool = false             ## Плащ «закрашен цветным карандашом»
@export_range(0.0, 1.0) var cape_pencil_strength: float = 0.85   ## Сила карандашного эффекта (0 — выключен)
@export var cape_gust: float = 9000.0            ## Как сильно порыв ветра (кнопка 6) раздувает плащ
@export var cape_inertia: float = 0.85            ## Инерция: насколько плащ отстаёт при разгоне, остановке и прыжке (0 — плащ не реагирует)
@export var cape_air_lift: float = 0.05           ## Как сильно плащ взлетает вверх при падении и прижимается при подъёме
@export var cape_drag: float = 1.0                ## Насколько плащ отклоняется назад от скорости (1 — как на рисунке при полной скорости)
@export var full_speed: float = 380.0             ## Скорость персонажа в игре при полном ходе (должна совпадать с speed в player.gd)
@export_group("Шарф")
@export var scarf_enabled: bool = false           ## Белый шарфик на шее
@export var scarf_gust: float = 6000.0            ## Как сильно порыв ветра (кнопка 6) раздувает шарф
@export var scarf_wind: float = 150.0             ## Колыхание шарфа на ходу
@export var scarf_hang_shift: float = 100.0       ## Насколько шарф «повисает» вниз, когда Фуки стоит
@export var scarf_stiffness_top: float = 30.0     ## Жёсткость у шеи
@export var scarf_stiffness_hem: float = 7.0      ## Жёсткость у кончика (меньше — свободнее летает)
@export var scarf_damping: float = 0.22           ## Затухание качания шарфа
@export_group("Живость")
@export var blink_enabled: bool = true            ## Моргание
@export var breathe_amount: float = 0.014         ## Дыхание в стойке
@export var idle_head_sway_deg: float = 1.2       ## Лёгкое покачивание головы, когда стоит
@export var dust_enabled: bool = true             ## Облачко пыли при шаге
@export_group("Прочее")
@export var squash_on_land: float = 0.10          ## Приседание при приземлении
@export var use_turn_animation: bool = true       ## Проигрывать разворот при смене направления

const TX: float = 252.18
const GY: float = 861.50
const NECK := Vector2(372.0, 225.0)
var HIP: Array[Vector2] = [Vector2(153.04, 619.69), Vector2(361.44, 645.53)]
var KNEE: Array[Vector2] = [Vector2(127.71, 745.43), Vector2(415.75, 757.06)]
var ANKLE: Array[Vector2] = [Vector2(109.20, 837.32), Vector2(455.44, 838.55)]
var TIP: Array[Vector2] = [Vector2(104.33, 861.50), Vector2(465.89, 860.00)]
const LEG_BOX: Array[Rect2] = [Rect2(44.0, 605.5, 149.5, 260.0), Rect2(311.5, 632.5, 193.5, 231.5)]
const LEG_AXIS: Array[Vector2] = [Vector2(-0.1975, 0.9803), Vector2(0.4379, 0.8990)]
const LEG_LEN: Array[float] = [246.67, 238.55]
const A0: Array[float] = [-11.39, 25.97]
const T1: float = 0.52
const T2: float = 0.9
const CAPE_X0: float = 11.0
const CAPE_X1: float = 407.0
const CAPE_Y0: float = 199.0
const CAPE_Y1: float = 704.5

const R: int = 16
const C: int = 9
const LEG_COLS: int = 7
const LEG_ROWS: int = 34
const BLEND: float = 0.075                        # ширина «плавного» сгиба у колена и лодыжки (доля длины ноги)
const IDLE_PHASE_FRAME: int = 18
const JUMP_PHASE_FRAME: int = 7

@onready var flip: Node2D = $Flip
@onready var puppet: Node2D = $Flip/Puppet
@onready var turn_sprite: AnimatedSprite2D = $Turn
@onready var cape: Polygon2D = $Flip/Puppet/Cape
@onready var head_pivot: Node2D = $Flip/Puppet/HeadPivot
@onready var head: Sprite2D = $Flip/Puppet/HeadPivot/Head
@onready var blink: Node2D = $Flip/Puppet/HeadPivot/Blink
@onready var leg_nodes: Array[Polygon2D] = [$Flip/Puppet/LegBack, $Flip/Puppet/LegFront]
@onready var dust: Array[CPUParticles2D] = [$DustBack, $DustFront]

var base_scale: Vector2
var body_drop: float = 0.0       ## На сколько корпус опущен вниз (из-за коротких ног), в пикселях рисунка
var time: float = 0.0
var phase: float = 0.0           # фаза шага, радианы
var walking: bool = false
var stop_requested: bool = false
var move: float = 0.0            # сглаженная «скорость»: 0 — стоит, 1 — идёт (влияет на плащ)
var was_in_air: bool = false
var squash: float = 0.0
var run_k: float = 0.0           # 0 — идёт, 1 — бежит (шире шаг, сильнее наклон)
var facing: float = 1.0
var turning: bool = false
var turn_to: float = 1.0
var bob: float = 0.0
var prev_bob: float = 0.0
var prev_bob2: float = 0.0
var blink_timer: float = 2.5
var blink_left: float = 0.0
var contact: Array[bool] = [false, false]
var prev_pos: Vector2 = Vector2.ZERO
var have_prev: bool = false
var vel_w: Vector2 = Vector2.ZERO        # скорость в мире, сглаженная (пикселей/с)
var acc_w: Vector2 = Vector2.ZERO        # ускорение в мире (пикселей/с²)
var fwd: float = 0.0                     # скорость вперёд, доля от полной (может быть < 0)
var vy_tex: float = 0.0                  # вертикальная скорость в пикселях рисунка (вниз — положительная)

var leg_rest: Array[PackedVector2Array] = []
var leg_w: Array[PackedFloat32Array] = []   # веса: x — доля голени, y — доля стопы
var leg_verts: Array[PackedVector2Array] = []

# Плащ: сетка R×C. rest — исходные точки на рисунке, off/vel — смещение и скорость.
var rest: PackedVector2Array = PackedVector2Array()
var off: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()
var verts: PackedVector2Array = PackedVector2Array()

# Шарф: повязка на шее (почти неподвижная) и свободный конец — сетка SC_R×SC_C с той же физикой, что у плаща.
const SC_R: int = 10
const SC_C: int = 4
const SC_ORIGIN := Vector2(341.0, 212.0)      # где конец шарфа выходит из-под повязки
const SC_LEN := Vector2(-130.0, 195.0)         # куда конец тянется, когда летит назад (как на бегу)
const SC_WIDTH: float = 42.0
var scarf_tail: Polygon2D
var scarf_wrap: Node2D
var s_rest: PackedVector2Array = PackedVector2Array()
var s_off: PackedVector2Array = PackedVector2Array()
var s_vel: PackedVector2Array = PackedVector2Array()
var s_verts: PackedVector2Array = PackedVector2Array()
var cape_acc: Vector2 = Vector2.ZERO


func _ready() -> void:
	base_scale = scale
	phase = TAU * IDLE_PHASE_FRAME / 24.0
	_build_cape()
	_build_scarf()
	_apply_pencil()
	for i in 2:
		_build_leg(i)
	_shorten_legs()
	_make_dust_texture()
	turn_sprite.animation_finished.connect(_on_turn_finished)
	_pose_legs(phase, 1.0)


func _make_dust_texture() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	for d in dust:
		d.texture = t
		d.color_ramp = fade


# ───────── построение сеток ─────────

func _build_leg(i: int) -> void:
	var box: Rect2 = LEG_BOX[i]
	var pts := PackedVector2Array()
	var w := PackedFloat32Array()
	for r in LEG_ROWS:
		for c in LEG_COLS:
			var p := Vector2(box.position.x + box.size.x * float(c) / (LEG_COLS - 1), box.position.y + box.size.y * float(r) / (LEG_ROWS - 1))
			pts.append(p)
			var t: float = ((p - HIP[i]).dot(LEG_AXIS[i])) / LEG_LEN[i]
			w.append(smoothstep(T1 - BLEND, T1 + BLEND, t))
			w.append(smoothstep(T2 - BLEND * 0.7, T2 + BLEND * 0.7, t))
	var tris: Array = []
	for r in LEG_ROWS - 1:
		for c in LEG_COLS - 1:
			var a: int = r * LEG_COLS + c
			tris.append(PackedInt32Array([a, a + 1, a + LEG_COLS]))
			tris.append(PackedInt32Array([a + LEG_COLS + 1, a + 1, a + LEG_COLS]))
	leg_rest.append(pts)
	leg_w.append(w)
	leg_verts.append(pts.duplicate())
	leg_nodes[i].polygon = leg_verts[i]
	leg_nodes[i].uv = pts
	leg_nodes[i].polygons = tris


func _build_cape() -> void:
	rest.resize(R * C)
	off.resize(R * C)
	vel.resize(R * C)
	verts.resize(R * C)
	for r in R:
		for c in C:
			var i: int = r * C + c
			rest[i] = Vector2(lerpf(CAPE_X0, CAPE_X1, float(c) / (C - 1)), lerpf(CAPE_Y0, CAPE_Y1, float(r) / (R - 1)))
			var xn: float = float(c) / (C - 1)
			off[i] = Vector2(lerpf(cape_hang_shift, cape_hang_shift * 0.09, xn) * pow(float(r) / (R - 1), 1.3), 0.0)   # плащ сразу висит, как у стоящей Фуки
			vel[i] = Vector2.ZERO
			verts[i] = rest[i] + off[i]
	var tris: Array = []
	for r in R - 1:
		for c in C - 1:
			var a: int = r * C + c
			tris.append(PackedInt32Array([a, a + 1, a + C]))
			tris.append(PackedInt32Array([a + C + 1, a + 1, a + C]))
	cape.polygon = verts
	cape.uv = rest
	cape.polygons = tris


# ───────── главный метод ─────────

## speed_ratio: 0 — стоит, 1 — идёт на полной скорости.
## face: 1 — вправо, -1 — влево, 0 — не менять.
func animate(delta: float, speed_ratio: float, face: float, in_air: bool) -> void:
	var real_delta: float = delta
	delta = minf(delta, 1.0 / 20.0)
	time += delta

	if face != 0.0 and face != facing and not turning:
		if use_turn_animation and not in_air:
			_start_turn(face)
		else:
			facing = face
			flip.scale.x = facing

	# Шаги: фаза бежит, пока Фуки идёт; при остановке доходит до позы «ноги вместе».
	if in_air:
		phase = TAU * JUMP_PHASE_FRAME / 24.0
		walking = false
		stop_requested = false
	else:
		if speed_ratio > 0.05:
			walking = true
			stop_requested = false
		elif walking:
			stop_requested = true
		if walking:
			var prev: float = phase
			phase = fposmod(phase + TAU * delta / cycle_seconds * maxf(0.5, speed_ratio), TAU)
			if stop_requested:
				var idle_phase: float = TAU * IDLE_PHASE_FRAME / 24.0
				if _crossed(prev, phase, idle_phase):
					phase = idle_phase
					walking = false
					stop_requested = false

	_measure_motion(real_delta)
	var run_target: float = clampf((speed_ratio - 1.0) / 0.75, 0.0, 1.0) if not in_air else run_k
	run_k += (run_target - run_k) * (1.0 - exp(-delta / 0.25))

	var move_target: float = 1.0 if (walking or in_air) else 0.0
	move += (move_target - move) * (1.0 - exp(-delta / 0.28))

	if not turning:
		_pose_legs(phase, move)
		_update_head(delta)
		_update_dust(in_air)
	_step_cape(delta)
	_step_scarf(delta)

	# Приземление: короткое приседание.
	if was_in_air and not in_air:
		squash = squash_on_land
	was_in_air = in_air
	squash = move_toward(squash, 0.0, delta * 0.8)
	var breathe: float = 0.0
	if not walking and not in_air and not turning:
		breathe = sin(time * 2.2) * breathe_amount
	scale = Vector2(base_scale.x * (1.0 + squash * 0.6), base_scale.y * (1.0 - squash + breathe))

	puppet.visible = not turning
	turn_sprite.visible = turning


## Скорость и ускорение берём из реального движения узла в мире (ходьба, прыжок, падение, разворот).
func _measure_motion(delta: float) -> void:
	var gp: Vector2 = global_position
	if not have_prev:
		prev_pos = gp
		have_prev = true
		return
	var raw: Vector2 = (gp - prev_pos) / maxf(delta, 0.0001)
	prev_pos = gp
	raw = raw.limit_length(2500.0)
	var k: float = 1.0 - exp(-delta / 0.035)
	var new_vel: Vector2 = vel_w.lerp(raw, k)
	acc_w = acc_w.lerp((new_vel - vel_w) / maxf(delta, 0.0001), 1.0 - exp(-delta / 0.03))
	acc_w = acc_w.limit_length(9000.0)
	vel_w = new_vel
	var gs: float = maxf(absf(global_scale.x), 0.05)
	fwd = clampf(vel_w.x * facing / maxf(full_speed, 1.0), -0.5, 1.8)
	vy_tex = vel_w.y / gs


func _crossed(a: float, b: float, target: float) -> bool:
	if b >= a:
		return a < target and b >= target
	return a < target or b >= target


# ───────── ноги ─────────

## Делает видимую часть ног короче: ноги сжимаются вдоль своей оси над стопой, а корпус (плащ, голова) опускается ниже.
func _shorten_legs() -> void:
	if leg_shorten <= 1.0:
		return
	var drop: float = (GY - CAPE_Y1) * (1.0 - 1.0 / leg_shorten)
	var k: float = (ANKLE[0].y - CAPE_Y1 - drop) / (ANKLE[0].y - CAPE_Y1)
	for i in 2:
		var axis: Vector2 = LEG_AXIS[i]
		var rest_pts: PackedVector2Array = leg_rest[i]
		# Короткие ноги ставим ближе к центру тела (целиком сдвигаем в сторону, форма не меняется).
		var shift := Vector2((leg_spread - 1.0) * (ANKLE[i].x - 257.0), 0.0)
		for j in rest_pts.size():
			rest_pts[j] += shift
		HIP[i] += shift
		KNEE[i] += shift
		ANKLE[i] += shift
		TIP[i] += shift
		for j in rest_pts.size():
			rest_pts[j] = _squeeze(rest_pts[j], ANKLE[i], axis, k)
		leg_rest[i] = rest_pts
		HIP[i] = _squeeze(HIP[i], ANKLE[i], axis, k)
		KNEE[i] = _squeeze(KNEE[i], ANKLE[i], axis, k)
	body_drop = drop
	cape.position.y += drop


func _squeeze(p: Vector2, ankle: Vector2, axis: Vector2, k: float) -> Vector2:
	var s: float = (p - ankle).dot(axis)
	if s >= 0.0:
		return p
	return p - axis * s * (1.0 - k)


func _rot_about(angle: float, c: Vector2) -> Transform2D:
	return Transform2D(angle, c - c.rotated(angle))


func _pose_legs(ph: float, mv: float) -> void:
	var tip_y: Array[float] = [0.0, 0.0]
	var tip_x: Array[float] = [0.0, 0.0]
	for i in 2:
		var p: float = ph + (PI if i == 0 else 0.0)
		var ang: float = leg_swing_deg * (1.0 + 0.3 * run_k) * sin(p)
		var d0: float = ang - A0[i]
		var v: float = cos(p)
		var flex: float = -(knee_bend_deg * (1.0 + 0.45 * run_k) * pow(maxf(0.0, v), 1.5)) + 5.0 * maxf(0.0, -v)
		var fa: float = -(d0 + flex) * 0.85 + 6.0 * maxf(0.0, v)
		var m1: Transform2D = _rot_about(-deg_to_rad(d0), HIP[i])
		var m2: Transform2D = m1 * _rot_about(-deg_to_rad(flex), KNEE[i])
		var m3: Transform2D = m2 * _rot_about(-deg_to_rad(fa), ANKLE[i])
		var src: PackedVector2Array = leg_rest[i]
		var w: PackedFloat32Array = leg_w[i]
		var out: PackedVector2Array = leg_verts[i]
		for k in src.size():
			var q: Vector2 = src[k]
			var a: Vector2 = m1 * q
			var b: Vector2 = m2 * q
			var c: Vector2 = m3 * q
			out[k] = a.lerp(b, w[k * 2]).lerp(c, w[k * 2 + 1])
		leg_verts[i] = out
		leg_nodes[i].polygon = out
		var tip: Vector2 = m3 * TIP[i]
		tip_y[i] = tip.y
		tip_x[i] = tip.x
	# Самая низкая стопа стоит на земле: так получается естественное покачивание корпуса.
	var low: float = maxf(tip_y[0], tip_y[1]) - GY
	bob = -low
	for i in 2:
		var on_floor: bool = (tip_y[i] - GY - low) > -4.0 and mv > 0.5
		if on_floor and not contact[i]:
			_footstep(i, tip_x[i])
		contact[i] = on_floor
	var lean: float = deg_to_rad(lean_deg) * sin(ph * 2.0) * mv - deg_to_rad(forward_lean_deg * (1.0 + 1.2 * run_k)) * mv
	var pivot := Vector2(256.0 - TX, 675.0 - GY + body_drop)   # бёдра
	puppet.rotation = -lean
	puppet.position = pivot - pivot.rotated(-lean) + Vector2(0.0, bob)


func _footstep(i: int, tip_x: float) -> void:
	if not dust_enabled or not walking:
		return
	var d: CPUParticles2D = dust[i]
	d.position = Vector2((tip_x - TX) * facing, 0.0)
	d.direction = Vector2(-facing, -0.35)
	d.restart()
	d.emitting = true


func _update_dust(_in_air: bool) -> void:
	pass


# ───────── голова и глаза ─────────

func _update_head(delta: float) -> void:
	var walk_amt: float = move
	var nod: float = deg_to_rad(head_bob_deg) * sin(phase * 2.0 + 0.7) * walk_amt
	var sway: float = deg_to_rad(idle_head_sway_deg) * sin(time * 0.9) * (1.0 - walk_amt)
	# голова компенсирует наклон корпуса и чуть запаздывает за ним
	head_pivot.rotation = nod + sway + puppet.rotation * 0.6
	head_pivot.position = Vector2(NECK.x - TX, NECK.y - GY + body_drop) + Vector2(0.0, -1.5 * sin(phase * 2.0 + 0.3) * walk_amt)
	var mat := head.material as ShaderMaterial
	mat.set_shader_parameter("phase", time * 3.0 + phase)
	mat.set_shader_parameter("amount", lerpf(0.9, 2.2, walk_amt) + Wind.gust * 2.5)
	# моргание
	if blink_enabled:
		if blink_left > 0.0:
			blink_left -= delta
			blink.visible = blink_left > 0.0
		else:
			blink.visible = false
			blink_timer -= delta
			if blink_timer <= 0.0:
				blink_left = 0.14
				blink_timer = randf_range(2.0, 5.5)
				if randf() < 0.18:
					blink_timer = 0.35     # иногда моргает дважды
	else:
		blink.visible = false


# ───────── плащ ─────────

func _step_cape(delta: float) -> void:
	var gs: float = maxf(absf(global_scale.x), 0.05)
	# Ускорение корпуса в рисунке: x — вперёд (по взгляду), y — вниз. Плащ «не хочет» двигаться вместе с телом.
	var a_local := Vector2(acc_w.x * facing, acc_w.y) / gs
	# собственное подпрыгивание корпуса при шаге
	var bob_acc: float = (bob - 2.0 * prev_bob + prev_bob2) / maxf(delta * delta, 0.000001)
	prev_bob2 = prev_bob
	prev_bob = bob
	a_local.y += clampf(bob_acc, -2000.0, 2000.0)
	a_local = a_local.limit_length(7000.0)
	cape_acc = a_local
	var subs: int = 3
	var h: float = delta / subs
	var hang: float = clampf(1.0 - fwd * cape_drag, 0.0, 1.4)      # 1 — плащ висит, 0 — отнесён назад, как на рисунке
	var breeze: float = maxf(clampf(fwd, 0.0, 1.6), cape_idle_breeze)
	var air: float = clampf(absf(vy_tex) / 1800.0, 0.0, 1.0)         # насколько Фуки сейчас летит
	var lift: float = clampf(-vy_tex * cape_air_lift, -110.0, 90.0)   # падает — плащ взлетает вверх, поднимается — прижимается
	var gust: float = Wind.gust
	for _s in subs:
		var new_off: PackedVector2Array = off.duplicate()
		for r in range(1, R):
			var s: float = float(r) / (R - 1)
			var w: float = lerpf(cape_stiffness_top, cape_stiffness_hem, s)
			for c in C:
				var i: int = r * C + c
				var xn: float = float(c) / (C - 1)
				var tgt := Vector2(lerpf(cape_hang_shift, cape_hang_shift * 0.09, xn) * pow(s, 1.3) * hang, lift * pow(s, 1.1))
				var o: Vector2 = off[i]
				var up: Vector2 = off[i - C]
				var dn: Vector2 = off[i + C] if r < R - 1 else o
				var lf: Vector2 = off[i - 1] if c > 0 else o
				var rt: Vector2 = off[i + 1] if c < C - 1 else o
				var nb: Vector2 = (up + dn + lf + rt) * 0.25
				var wind: float = sin(2.3 * time - 0.7 * c - 3.0 * s) + 0.6 * sin(4.1 * time + 1.3 - 1.1 * c)
				var flutter: float = sin(7.0 * time + 1.9 * c - 4.0 * s) * air
				var ext := Vector2(
					-cape_wind * wind * breeze * pow(s, 1.2) - cape_step_kick * sin(phase) * move * s,
					-90.0 * flutter * pow(s, 1.5))
				ext -= a_local * cape_inertia
				if gust > 0.001:
					# Порыв: сильный снос по ветру + быстрое трепетание полотна и подъём вверх.
					var gl: float = gust * Wind.dir * facing     # + вперёд по взгляду
					var flap: float = sin(7.0 * time - 1.1 * c - 2.6 * s)
					ext.x += cape_gust * pow(s, 1.1) * (gl * 0.9 + gust * 0.55 * flap)
					ext.y += cape_gust * gust * pow(s, 1.2) * (-0.45 + 0.4 * sin(6.0 * time + 1.7 * c - 3.0 * s))
				var a: Vector2 = -(w * w) * (o - tgt) - 2.0 * cape_damping * w * Vector2(vel[i].x, vel[i].y * 1.6) + 60.0 * (nb - o) + ext
				vel[i] += a * h
				vel[i] = vel[i].limit_length(2500.0)
				new_off[i] = o + vel[i] * h
		off = new_off
	for i in R * C:
		verts[i] = rest[i] + off[i]
	cape.polygon = verts


# ───────── разворот ─────────

func _reset_cape() -> void:
	_reset_scarf()
	for r in R:
		for c in C:
			var i: int = r * C + c
			var xn: float = float(c) / (C - 1)
			off[i] = Vector2(lerpf(cape_hang_shift, cape_hang_shift * 0.09, xn) * pow(float(r) / (R - 1), 1.3) * clampf(1.0 - fwd, 0.0, 1.0), 0.0)
			vel[i] = Vector2.ZERO


func _start_turn(new_face: float) -> void:
	turning = true
	turn_to = new_face
	turn_sprite.play(&"turn_left" if new_face < 0.0 else &"turn_right")


func _on_turn_finished() -> void:
	if not turning:
		return
	turning = false
	facing = turn_to
	flip.scale.x = facing
	_reset_cape()


# ───────── шарф ─────────

func _build_scarf() -> void:
	var origin_shift := Vector2(-TX, -GY)
	# Свободный конец
	scarf_tail = Polygon2D.new()
	scarf_tail.name = "ScarfTail"
	scarf_tail.position = origin_shift
	scarf_tail.texture = load("res://assets/characters/fuki3/scarf.png")
	puppet.add_child(scarf_tail)
	s_rest.resize(SC_R * SC_C)
	s_off.resize(SC_R * SC_C)
	s_vel.resize(SC_R * SC_C)
	s_verts.resize(SC_R * SC_C)
	var uv := PackedVector2Array()
	uv.resize(SC_R * SC_C)
	for r in SC_R:
		var t: float = float(r) / (SC_R - 1)
		for c in SC_C:
			var i: int = r * SC_C + c
			var xn: float = float(c) / (SC_C - 1) - 0.5
			var width: float = SC_WIDTH * lerpf(1.0, 0.85, t)
			s_rest[i] = SC_ORIGIN + SC_LEN * t + Vector2(xn * width, 0.0)
			uv[i] = Vector2(float(c) / (SC_C - 1) * 64.0, t * 256.0)
			s_vel[i] = Vector2.ZERO
	_reset_scarf()
	var tris: Array = []
	for r in SC_R - 1:
		for c in SC_C - 1:
			var a: int = r * SC_C + c
			tris.append(PackedInt32Array([a, a + 1, a + SC_C]))
			tris.append(PackedInt32Array([a + SC_C + 1, a + 1, a + SC_C]))
	scarf_tail.polygon = s_verts
	scarf_tail.uv = uv
	scarf_tail.polygons = tris
	# Повязка вокруг шеи: белая лента вдоль воротника
	scarf_wrap = Node2D.new()
	scarf_wrap.name = "ScarfWrap"
	scarf_wrap.position = origin_shift
	puppet.add_child(scarf_wrap)
	var a0 := Vector2(331.0, 204.0)
	var c0 := Vector2(366.0, 222.0)
	var b0 := Vector2(402.0, 252.0)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var steps: int = 14
	for k in steps + 1:
		var t: float = float(k) / steps
		var p: Vector2 = a0.lerp(c0, t).lerp(c0.lerp(b0, t), t)
		var tan_v: Vector2 = ((c0 - a0) * (1.0 - t) + (b0 - c0) * t).normalized()
		var n := Vector2(-tan_v.y, tan_v.x)
		var wdt: float = 14.0 + 10.0 * sin(PI * t) ** 0.7
		top.append(p - n * wdt)
		bottom.append(p + n * wdt)
	var outline := PackedVector2Array()
	outline.append_array(top)
	bottom.reverse()
	outline.append_array(bottom)
	var base := Polygon2D.new()
	base.polygon = outline
	base.color = Color(0.985, 0.985, 0.995)
	scarf_wrap.add_child(base)
	# тень снизу и складка сверху
	var low := PackedVector2Array()
	var mid := PackedVector2Array()
	for k in steps + 1:
		low.append(bottom[bottom.size() - 1 - k])
		mid.append(top[k].lerp(bottom[bottom.size() - 1 - k], 0.62))
	mid.reverse()
	var shadow := Polygon2D.new()
	var sh := PackedVector2Array()
	sh.append_array(low)
	sh.append_array(mid)
	shadow.polygon = sh
	shadow.color = Color(0.80, 0.84, 0.93, 0.85)
	scarf_wrap.add_child(shadow)
	var crease := Line2D.new()
	var cr := PackedVector2Array()
	for k in steps + 1:
		cr.append(top[k].lerp(bottom[bottom.size() - 1 - k], 0.38))
	crease.points = cr
	crease.width = 1.8
	crease.default_color = Color(0.78, 0.82, 0.92, 0.9)
	scarf_wrap.add_child(crease)
	var edge := Line2D.new()
	edge.points = top
	edge.width = 1.4
	edge.default_color = Color(0.72, 0.77, 0.9, 0.8)
	scarf_wrap.add_child(edge)
	scarf_tail.visible = scarf_enabled
	scarf_wrap.visible = scarf_enabled


func _reset_scarf() -> void:
	if s_off.is_empty():
		return
	for r in SC_R:
		var t: float = float(r) / (SC_R - 1)
		for c in SC_C:
			var i: int = r * SC_C + c
			s_off[i] = Vector2(scarf_hang_shift * pow(t, 1.3) * clampf(1.0 - fwd, 0.0, 1.0), 0.0)
			s_vel[i] = Vector2.ZERO
			s_verts[i] = s_rest[i] + s_off[i]


func _step_scarf(delta: float) -> void:
	if not scarf_enabled:
		scarf_tail.visible = false
		scarf_wrap.visible = false
		return
	scarf_tail.visible = true
	scarf_wrap.visible = true
	var a_local: Vector2 = cape_acc
	var subs: int = 3
	var h: float = delta / subs
	var hang: float = clampf(1.0 - fwd * cape_drag, 0.0, 1.4)
	var breeze: float = maxf(clampf(fwd, 0.0, 1.6), cape_idle_breeze)
	var air: float = clampf(absf(vy_tex) / 1800.0, 0.0, 1.0)
	var lift: float = clampf(-vy_tex * cape_air_lift, -110.0, 90.0)
	var gust: float = Wind.gust
	for _s in subs:
		var new_off: PackedVector2Array = s_off.duplicate()
		for r in range(1, SC_R):
			var s: float = float(r) / (SC_R - 1)
			var w: float = lerpf(scarf_stiffness_top, scarf_stiffness_hem, s)
			for c in SC_C:
				var i: int = r * SC_C + c
				var tgt := Vector2(scarf_hang_shift * pow(s, 1.3) * hang, lift * 0.8 * pow(s, 1.1))
				var o: Vector2 = s_off[i]
				var up: Vector2 = s_off[i - SC_C]
				var dn: Vector2 = s_off[i + SC_C] if r < SC_R - 1 else o
				var lf: Vector2 = s_off[i - 1] if c > 0 else o
				var rt: Vector2 = s_off[i + 1] if c < SC_C - 1 else o
				var nb: Vector2 = (up + dn + lf + rt) * 0.25
				var wind: float = sin(2.9 * time - 1.0 * c - 3.4 * s) + 0.6 * sin(5.1 * time + 0.8 - 1.3 * c)
				var flutter: float = sin(8.5 * time + 1.7 * c - 4.5 * s) * air
				var ext := Vector2(
					-scarf_wind * wind * breeze * pow(s, 1.1) - cape_step_kick * 0.5 * sin(phase) * move * s,
					-70.0 * flutter * pow(s, 1.4))
				ext -= a_local * cape_inertia * 0.9
				if gust > 0.001:
					var gl: float = gust * Wind.dir * facing
					var flap: float = sin(9.0 * time - 1.3 * c - 3.0 * s)
					ext.x += scarf_gust * pow(s, 1.1) * (gl * 0.9 + gust * 0.6 * flap)
					ext.y += scarf_gust * gust * pow(s, 1.2) * (-0.4 + 0.45 * sin(7.5 * time + 1.9 * c - 3.2 * s))
				var a: Vector2 = -(w * w) * (o - tgt) - 2.0 * scarf_damping * w * Vector2(s_vel[i].x, s_vel[i].y * 1.6) + 50.0 * (nb - o) + ext
				s_vel[i] += a * h
				s_vel[i] = s_vel[i].limit_length(2500.0)
				new_off[i] = o + s_vel[i] * h
		s_off = new_off
	for i in SC_R * SC_C:
		s_verts[i] = s_rest[i] + s_off[i]
	scarf_tail.polygon = s_verts


# ───────── карандашный эффект на плаще ─────────

func _apply_pencil() -> void:
	if not cape_pencil:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pencil.gdshader")
	mat.set_shader_parameter("strength", cape_pencil_strength)
	cape.material = mat
