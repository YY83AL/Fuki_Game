class_name Player
extends Node2D
## Героиня Фуки. Ходит клавишами A/D (или стрелками), прыгает на пробел.
## Работает на любой раскладке клавиатуры (в том числе русской),
## потому что проверяются физические клавиши.

@export var horizontal_only: bool = true   ## true: ходит только влево-вправо (A/D). false: ещё и вглубь (W/S)
@export var speed: float = 300.0           ## Скорость ходьбы, пикселей в секунду
@export var acceleration: float = 2600.0   ## Насколько быстро разгоняется и останавливается
@export var run_multiplier: float = 1.75    ## Во сколько раз быстрее бег (Shift), чем ходьба
@export var run_acceleration: float = 1300.0  ## Разгон до бега (меньше — дольше разгоняется)
@export var run_jump_boost: float = 1.12    ## Прыжок с разбега чуть выше (значит, летит дальше)
@export var air_acceleration: float = 700.0 ## Управление в воздухе (инерция разбега сохраняется)
@export var jump_speed: float = 720.0      ## Сила прыжка (чем больше, тем выше)
@export var jump_windup: float = 0.09     ## Присед перед прыжком, секунд (0 — прыжок мгновенный)
@export var gravity: float = 2200.0        ## Как быстро Фуки падает обратно
@export var x_min: float = 90.0            ## Левая граница локации
@export var x_max: float = 3014.0          ## Правая граница (задаётся в location.gd по ширине фона)
@export var y_min: float = 590.0           ## Дальний край пола (чуть ниже плинтуса)
@export var y_max: float = 700.0           ## Ближний край пола
@export var scale_back: float = 0.88       ## Размер Фуки у дальнего края пола
@export var scale_front: float = 1.08      ## Размер Фуки у ближнего края пола

var velocity: Vector2 = Vector2.ZERO
var walk_time: float = 0.0
var air_height: float = 0.0     ## Насколько Фуки сейчас выше пола (0 = стоит на полу)
var air_speed: float = 0.0      ## Вертикальная скорость в прыжке (вверх положительная)
var base_scale: float = 1.0
var air_max_speed: float = 0.0  ## Скорость по горизонтали, с которой Фуки оторвалась от земли
var jump_wind: float = -1.0     ## Сколько осталось до отрыва (<0 — прыжок не готовится)
var jump_wind_total: float = 0.09
var active: bool = true         ## Этим персонажем сейчас управляют (иначе он стоит на месте)

@onready var shadow: Polygon2D = $Shadow
var shadow_core: Sprite2D      # плотная тень прямо под ногами
var shadow_soft: Sprite2D      # широкая мягкая тень вокруг
@onready var body: Node2D = $Body
@onready var rig: Node2D = $Body/Fuki2 if has_node("Body/Fuki2") else $Body/Fuki3


func _ready() -> void:
	_build_shadow()


## Мягкая тень из двух размытых пятен вместо плоского тёмного овала.
func _build_shadow() -> void:
	shadow.polygon = PackedVector2Array()      # старый овал больше не рисуется
	shadow_soft = _make_blob(Color(0.05, 0.03, 0.02, 0.34), Vector2(250.0, 46.0))
	shadow_core = _make_blob(Color(0.04, 0.02, 0.02, 0.72), Vector2(118.0, 22.0))
	shadow.add_child(shadow_soft)
	shadow.add_child(shadow_core)


func _make_blob(color: Color, size: Vector2) -> Sprite2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([color, Color(color.r, color.g, color.b, color.a * 0.45), Color(color.r, color.g, color.b, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	var sp := Sprite2D.new()
	sp.texture = t
	sp.scale = size / 128.0 * 2.0
	sp.position = Vector2(0.0, 4.0)
	return sp


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_9 and "stepped" in rig:             # 9: «на двойках» (12 кадров/с) вкл/выкл
			rig.stepped = not rig.stepped
		if event.physical_keycode == KEY_SPACE and active:
			if jump_windup <= 0.0:
				_jump()
			elif air_height <= 0.0 and air_speed <= 0.0 and jump_wind < 0.0:
				jump_wind_total = jump_windup * (0.6 if absf(velocity.x) > speed * 1.15 else 1.0)
				jump_wind = jump_wind_total


func _jump() -> void:
	if air_height <= 0.0:
		var running_fast: bool = absf(velocity.x) > speed * 1.15
		air_speed = jump_speed * (run_jump_boost if running_fast else 1.0)
		air_max_speed = maxf(speed, absf(velocity.x))


func _process(delta: float) -> void:
	var direction: Vector2 = _read_input()
	var running: bool = active and Input.is_physical_key_pressed(KEY_SHIFT)
	if air_height > 0.0 or air_speed > 0.0:
		# В воздухе скорость разбега сохраняется: отпустил кнопку — летишь дальше по инерции.
		if direction.x != 0.0:
			velocity.x = move_toward(velocity.x, direction.x * air_max_speed, air_acceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 120.0 * delta)
	else:
		var target_speed: float = speed * (run_multiplier if running else 1.0)
		var accel: float = acceleration
		if running and direction != Vector2.ZERO:
			accel = run_acceleration
		velocity = velocity.move_toward(direction * target_speed, accel * delta)
	position += velocity * delta
	position.x = clampf(position.x, x_min, x_max)
	position.y = clampf(position.y, y_min, y_max)
	if jump_wind >= 0.0:
		jump_wind -= delta
		if jump_wind < 0.0:
			_jump()
	_update_jump(delta)
	_update_depth_scale()
	_animate(delta)


func _read_input() -> Vector2:
	var d: Vector2 = Vector2.ZERO
	if not active:
		return d
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if not horizontal_only:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			d.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			d.y += 1.0
	return d.normalized()


func _update_jump(delta: float) -> void:
	if air_height > 0.0 or air_speed > 0.0:
		air_speed -= gravity * delta
		air_height += air_speed * delta
		if air_height <= 0.0:
			air_height = 0.0
			air_speed = 0.0


func _update_depth_scale() -> void:
	# Чем ближе к зрителю, тем крупнее персонаж.
	var t: float = inverse_lerp(y_min, y_max, position.y)
	base_scale = lerpf(scale_back, scale_front, t)
	body.scale = Vector2(base_scale, base_scale)
	# Тень остаётся на полу и уменьшается, пока Фуки в воздухе.
	var lift: float = clampf(air_height / 120.0, 0.0, 1.0)
	var shadow_scale: float = base_scale * (1.0 - 0.35 * lift)
	shadow.scale = Vector2(shadow_scale, shadow_scale)
	# На бегу тень вытягивается, в прыжке бледнеет, а при ходьбе чуть «дышит» в такт шагам.
	var run: float = clampf(absf(velocity.x) / speed, 0.0, run_multiplier)
	var step_ph: float = rig.phase if "phase" in rig else Time.get_ticks_msec() * 0.007
	var pulse: float = 1.0 + 0.07 * sin(step_ph * 2.0) * minf(run, 1.0)
	if "land_left" in rig:
		pulse *= 1.0 + 0.25 * clampf(rig.land_left / 0.26, 0.0, 1.0)
	if shadow_core:
		shadow_core.scale.x = 118.0 / 128.0 * 2.0 * (1.0 + 0.16 * run) * pulse
		shadow_soft.scale.x = 250.0 / 128.0 * 2.0 * (1.0 + 0.10 * run)
		shadow.modulate.a = 1.0 - 0.55 * lift


func _animate(delta: float) -> void:
	# Скелетная анимация живёт в fuki_rig.gd: здесь только передаём ей скорость и направление.
	var face: float = 0.0
	if velocity.x > 5.0:
		face = 1.0
	elif velocity.x < -5.0:
		face = -1.0
	var speed_ratio: float = clampf(velocity.length() / speed, 0.0, run_multiplier)
	if "anticipate" in rig:
		rig.anticipate = smoothstep(0.0, 1.0, 1.0 - jump_wind / maxf(jump_wind_total, 0.001)) if jump_wind >= 0.0 else 0.0
	rig.animate(delta, speed_ratio, face, air_height > 0.0)
	body.position.y = -air_height
