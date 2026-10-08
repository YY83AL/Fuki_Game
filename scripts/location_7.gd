extends Node2D
## Локация 7: ночной офис. Три слоя с параллаксом, камера следует за Фуки.
##   far  — город за окнами (самый дальний, движется медленнее всех);
##   mid  — стены, окна, стеллаж и тумба;
##   near — столы, компьютеры и стопки бумаг (на одной глубине с полом, по которому идёт Фуки).
## За окнами гроза: молнии сверкают сами, дождь включается кнопкой.
## Кошка за столом с исходной картинки лежит отдельной картинкой, её можно выключить галочкой.
## Клавиши: 4 — звуки, 5 или M — музыка, 7 — дождь за окном.

signal flash_started   ## Молния сверкнула (по этому сигналу играет гром)

const Transition = preload("res://scripts/transition.gd")
const ART := "res://assets/backgrounds/location_7/"
const ART_SCALE := 0.75          ## Картинки нарисованы в 1920 px, мир — 1440 px шириной
const WORLD_W := 1440.0
const FLOOR_Y := 690.0           ## Верх тёмной полосы пола
const PLAYER_SIZE := 0.55        ## Размер Фуки в офисе (было 0.48, увеличено на 15%)
const DESK_CAT_POS := Vector2(430.0, 668.0)   ## Место кошки за столом, в пикселях картинки
const FAR_SPEED := 0.45
const MID_SPEED := 0.85

## Слои: файл и насколько слой движется вместе с миром (1 — как пол, меньше — дальше и медленнее).
const LAYERS := [
	["far", FAR_SPEED],
	["mid", MID_SPEED],
	["near", 1.0],
]
## Стёкла окон по ширине, в пикселях картинки среднего слоя: [левый край, правый край].
const WINDOWS := [[1200.0, 1450.0], [1546.0, 1796.0]]
## Где на картинке города чистое небо: [левый край, правый край, самая низкая точка молнии].
const SKY_ZONES := [[1262.0, 1400.0, 360.0], [1505.0, 1602.0, 430.0]]

@export var show_desk_cat: bool = true          ## Показывать кошку за столом (с исходной картинки)
@export_group("Гроза за окном")
@export var lightning: bool = true              ## Молнии сверкают
@export var min_interval: float = 5.0           ## Минимальная пауза между молниями, секунды
@export var max_interval: float = 14.0          ## Максимальная пауза
@export var first_flash_delay: float = 3.0      ## Через сколько секунд после входа будет первая молния
@export var sky_flash_strength: float = 1.0     ## Насколько светлеет город за окном при вспышке (0 — не светлеет)
@export var room_flash_strength: float = 0.15   ## Насколько светлеет сама комната (0 — совсем не светлеет)

@onready var player: Player = $Player
var audio: AudioManager
var cam: Camera2D
var layers: Array = []           ## [узел, множитель движения, его обычное место по x]
var far_sprite: Sprite2D
var room_sprites: Array[Sprite2D] = []   ## Всё, что внутри комнаты: стены, мебель, кошка за столом
var desk_cat: Sprite2D
var rain_nodes: Array[CPUParticles2D] = []
var sky_light: ColorRect         ## Свет вспышки поверх города: прибавляется к картинке
var bolt_glow: Line2D
var bolt_core: Line2D
var flash: float = 0.0           ## Яркость вспышки сейчас: 0..1
var flash_timer: float = 0.0
var sounds_button: Button
var music_button: Button
var rain_button: Button


func _ready() -> void:
	set_meta("fx_no_puddles", true)   # в офисе луж нет
	player.x_min = 70.0
	player.x_max = WORLD_W - 90.0
	player.y_min = FLOOR_Y + 4.0
	player.y_max = FLOOR_Y + 6.0
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	player.position.y = FLOOR_Y + 5.0
	cam = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD_W)
	cam.limit_bottom = 720
	_build_layers()
	_build_bolt()
	flash_timer = first_flash_delay
	if Transition.spawn_x >= 0.0:
		player.position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	cam.make_current()
	cam.reset_smoothing()
	audio = AudioManager.new()
	audio.name = "Audio"
	audio.rain_db = -16.0             # дождь слышен через стекло, поэтому тише, чем на улице
	add_child(audio)
	var list: Array[Player] = [player]
	audio.setup(list, self)           # гром играет по сигналу flash_started
	_build_menu()
	Transition.add_scene_arrows(self, 1)
	Transition.fade_in(self)
	_update_layers()


## Слои ставятся под Фуки: город, дождь за стеклом, стены, кошка за столом и мебель.
func _build_layers() -> void:
	var index: int = 0
	for l in LAYERS:
		if l[0] == "near":
			desk_cat = _sprite("cat")
			desk_cat.name = "DeskCat"
			desk_cat.position = DESK_CAT_POS * ART_SCALE
			desk_cat.visible = show_desk_cat
			move_child(desk_cat, index)
			index += 1
			layers.append([desk_cat, l[1], desk_cat.position.x])   # кошка едет вместе с мебелью
			room_sprites.append(desk_cat)
		var sp := _sprite(l[0])
		sp.name = "Layer_" + l[0]
		move_child(sp, index)
		index += 1
		layers.append([sp, l[1], 0.0])
		if l[0] == "far":
			far_sprite = sp
			# Дождь идёт между городом и стеной, поэтому виден только в окнах.
			for r in [_rain("RainFar", 0.6, 230, 0.55, 0.4), _rain("RainNear", 0.78, 150, 1.0, 0.6)]:
				move_child(r, index)
				index += 1
		else:
			room_sprites.append(sp)


func _sprite(file: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(ART + file + ".png")
	sp.centered = false
	sp.scale = Vector2(ART_SCALE, ART_SCALE)
	add_child(sp)
	return sp


## Один слой дождя: капли-штрихи падают наискось по всей ширине окон.
func _rain(node_name: String, speed: float, amount: int, size: float, alpha: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.texture = load("res://assets/fx/raindrop.png")
	p.position = Vector2(1090.0, -30.0)
	p.amount = amount
	p.lifetime = 0.85
	p.preprocess = 1.0
	p.local_coords = true
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(430.0, 2.0)
	p.direction = Vector2(0.18, 1.0)
	p.spread = 2.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 860.0 * (0.8 + 0.2 * size)
	p.initial_velocity_max = 1080.0 * (0.8 + 0.2 * size)
	p.scale_amount_min = 0.55 * size
	p.scale_amount_max = 1.0 * size
	p.color = Color(0.78, 0.88, 1.0, alpha)
	p.emitting = false
	add_child(p)
	rain_nodes.append(p)
	layers.append([p, speed, p.position.x])
	return p


## Молния — ломаная линия на картинке города: яркая сердцевина и мягкое свечение вокруг.
func _build_bolt() -> void:
	sky_light = ColorRect.new()
	sky_light.name = "SkyLight"
	sky_light.size = far_sprite.texture.get_size()
	sky_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_light.color = Color(0, 0, 0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sky_light.material = add
	far_sprite.add_child(sky_light)
	bolt_glow = _bolt_line(14.0, Color(0.62, 0.75, 1.0, 0.3))
	bolt_core = _bolt_line(4.5, Color(0.95, 0.98, 1.0, 1.0))


func _bolt_line(width: float, color: Color) -> Line2D:
	var l := Line2D.new()
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.antialiased = true
	l.visible = false
	far_sprite.add_child(l)
	return l


func _set_rain(on: bool) -> void:
	for p in rain_nodes:
		p.emitting = on
	audio.call("set_rain", on)


## Насколько сейчас сдвинута камера от левого края мира.
func _camera_left() -> float:
	return clampf(cam.get_screen_center_position().x - 640.0, 0.0, WORLD_W - 1280.0)


## Чем дальше слой, тем меньше он сдвигается, когда камера едет за Фуки.
func _update_layers() -> void:
	var left: float = _camera_left()
	for l in layers:
		l[0].position.x = l[2] + left * (1.0 - l[1])


func _process(delta: float) -> void:
	_update_layers()
	if lightning:
		flash_timer -= delta
		if flash_timer <= 0.0:
			_strike()
			flash_timer = randf_range(min_interval, max_interval)
	_apply_flash()


## Вспышка: город за окном и капли становятся ярче, комната — чуть светлее, молния видна, пока вспышка сильная.
func _apply_flash() -> void:
	var k: float = flash * sky_flash_strength
	var s: float = 1.0 + 0.3 * k
	far_sprite.modulate = Color(s, s, s)
	sky_light.color = Color(0.26 * k / s, 0.33 * k / s, 0.5 * k / s)
	for p in rain_nodes:
		p.modulate = Color(1.0 + flash, 1.0 + flash, 1.0 + flash)
	var r: float = flash * room_flash_strength
	var room := Color(1.0 + 0.9 * r, 1.0 + 1.0 * r, 1.0 + 1.3 * r)
	for sp in room_sprites:
		sp.modulate = room
	var a: float = clampf((flash - 0.2) * 1.6, 0.0, 1.0)
	bolt_core.visible = a > 0.0
	bolt_glow.visible = a > 0.0
	# Картинка города на вспышке ярче обычного, поэтому саму молнию делаем во столько же раз темнее.
	bolt_core.modulate = Color(1.0 / s, 1.0 / s, 1.0 / s, a)
	bolt_glow.modulate = Color(1.0 / s, 1.0 / s, 1.0 / s, a)


func _strike() -> void:
	_place_bolt()
	flash_started.emit()
	# Молния мигает: резкая вспышка, провал, вторая вспышка и плавное затухание.
	var tw: Tween = create_tween()
	tw.tween_property(self, "flash", 1.0, 0.04)
	tw.tween_property(self, "flash", 0.25, 0.07)
	tw.tween_property(self, "flash", 0.9, 0.04)
	if randf() < 0.4:
		tw.tween_property(self, "flash", 0.15, 0.08)
		tw.tween_property(self, "flash", 0.7, 0.05)
	tw.tween_property(self, "flash", 0.0, 0.6).set_ease(Tween.EASE_OUT)


## Ставит молнию туда, где сейчас сквозь окно видно чистое небо.
func _place_bolt() -> void:
	# Насколько картинка города сдвинута относительно окон из-за параллакса (в пикселях картинки).
	var shift: float = _camera_left() * (MID_SPEED - FAR_SPEED) / ART_SCALE
	var spots: Array = []            # [левый край, правый край, низ]
	for w in WINDOWS:
		for z in SKY_ZONES:
			var a: float = maxf(w[0] - shift, z[0])
			var b: float = minf(w[1] - shift, z[1])
			if b - a >= 30.0:
				spots.append([a, b, z[2]])
	var x: float = 1330.0
	var bottom: float = 300.0
	if not spots.is_empty():
		var spot: Array = spots[randi() % spots.size()]
		x = randf_range(spot[0] + 10.0, spot[1] - 10.0)
		bottom = randf_range(spot[2] * 0.7, spot[2])
	var pts := PackedVector2Array()
	var steps: int = randi_range(7, 10)
	var px: float = x + randf_range(-30.0, 30.0)
	for i in steps + 1:
		var k: float = float(i) / steps
		px = lerpf(px, x, 0.35) + randf_range(-16.0, 16.0)
		pts.append(Vector2(px, lerpf(60.0, bottom, k) + randf_range(-6.0, 6.0)))
	bolt_core.points = pts
	bolt_glow.points = pts


func _toggle(bar: Container, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = GameSettings.get_for(text, on)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.toggled.connect(func(v: bool): GameSettings.set_for(text, v))
	b.toggled.connect(cb)
	bar.add_child(b)
	cb.call(b.button_pressed)      # применяем общее состояние к этой сцене
	return b


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 10.0
	bar.add_theme_constant_override("separation", 12)
	layer.add_child(bar)
	sounds_button = _toggle(bar, "4 · Звуки", true, func(on: bool): audio.call("set_sounds", on))
	music_button = _toggle(bar, "5 · Музыка", true, func(on: bool): audio.call("set_music", on))
	rain_button = _toggle(bar, "7 · Дождь", false, _set_rain)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_4, KEY_KP_4:
				sounds_button.button_pressed = not sounds_button.button_pressed
			KEY_5, KEY_KP_5, KEY_M:
				music_button.button_pressed = not music_button.button_pressed
			KEY_7, KEY_KP_7:
				rain_button.button_pressed = not rain_button.button_pressed
