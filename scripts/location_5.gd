extends Node2D
## Локация 5: вагон метро. Поезд едет: за окнами и над крышей плывёт тоннель (параллакс),
## внизу бегут шпалы, колёса крутятся, пассажиры чуть покачиваются.
## Фуки приходит из города справа; выход обратно в город — у правого края (клавиша E).
## Клавиши: 4 — звуки, 5 или M — музыка, 6 — порыв ветра.

const Transition = preload("res://scripts/transition.gd")
const CITY_SCENE := "res://scenes/location_4.tscn"
const CITY_SPAWN_X := 150.0     ## В городе Фуки появляется у левого края
const EXIT_X := 2290.0          ## Правее этого — можно выйти (E)
const PLAYER_SIZE := 0.72
const S := 720.0 / 544.0        ## Картинка 1952×544 растянута на высоту экрана
const SRC_W := 1952.0
const FLOOR_Y_MIN := 352.0      ## Пол вагона (в пикселях картинки)
const FLOOR_Y_MAX := 372.0
const TRAIN_SPEED := 700.0      ## Скорость шпал, px картинки в секунду (поезд едет влево)
const WHEEL_R := 50.0
const WHEELS := [Vector2(87, 445), Vector2(400, 445), Vector2(570, 445), Vector2(833, 445),
	Vector2(1005, 445), Vector2(1525, 445), Vector2(1700, 445)]

## Пассажиры: [x0, x1, верх, низ, амплитуда, частота, фаза, тип(0 стоит, 1 сидит, 2 петля)]
const PEOPLE := [
	[368, 445, 232, 350, 0.55, 0.9, 0.3, 1],
	[475, 545, 198, 370, 1.0, 0.8, 1.1, 0],
	[548, 610, 245, 335, 0.5, 1.1, 2.0, 1],
	[640, 684, 238, 340, 0.5, 0.95, 3.1, 1],
	[678, 730, 225, 340, 0.5, 1.2, 4.2, 1],
	[722, 784, 190, 372, 1.0, 0.85, 0.7, 0],
	[760, 832, 238, 345, 0.45, 1.0, 5.0, 1],
	[838, 890, 200, 360, 0.9, 0.9, 2.6, 0],
	[893, 944, 205, 372, 1.0, 0.8, 3.7, 0],
	[940, 978, 280, 365, 0.8, 1.15, 0.2, 0],
	[962, 1008, 190, 375, 1.0, 0.9, 4.8, 0],
	[1118, 1162, 208, 372, 1.0, 1.0, 1.9, 0],
	[1158, 1205, 218, 360, 0.9, 0.85, 5.6, 0],
	[1212, 1285, 200, 372, 1.1, 0.8, 2.4, 0],
	[1268, 1325, 212, 372, 1.0, 0.95, 0.9, 0],
	[1368, 1430, 198, 372, 1.0, 0.85, 3.3, 0],
	[1470, 1545, 262, 360, 0.5, 1.05, 4.4, 1],
	[1565, 1630, 210, 375, 1.0, 0.9, 1.5, 0],
	[1635, 1692, 200, 378, 1.0, 0.8, 5.3, 0],
	# петли-поручни
	[630, 654, 166, 206, 1.8, 1.3, 0.5, 2],
	[800, 824, 166, 206, 1.8, 1.1, 2.3, 2],
	[1420, 1444, 166, 206, 1.8, 1.2, 4.1, 2],
	[1508, 1532, 170, 202, 1.8, 1.0, 1.0, 2],
]

@onready var player: Player = $Player

var wind: Wind
var audio: AudioManager
var hint: Node2D
var cam: Camera2D
var world_w: float = SRC_W * S
var sounds_button: Button
var music_button: Button
var t: float = 0.0
var speed_k: float = 1.0
var far: Sprite2D
var near: Sprite2D
var track: Sprite2D
var train: Sprite2D
var wheels: Array[Sprite2D] = []
var scroll := {"far": 0.0, "near": 0.0, "track": 0.0}


func _ready() -> void:
	player.x_min = 430.0
	player.x_max = 2330.0
	player.y_min = FLOOR_Y_MIN * S
	player.y_max = FLOOR_Y_MAX * S
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	cam = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(world_w)
	cam.limit_bottom = 720
	_build_layers()
	if Transition.spawn_x >= 0.0:
		player.position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	cam.make_current()
	cam.reset_smoothing()
	wind = Wind.new()
	wind.name = "Wind"
	add_child(wind)
	wind.setup(null)
	audio = AudioManager.new()
	audio.name = "Audio"
	add_child(audio)
	var list: Array[Player] = [player]
	audio.setup(list, null)
	audio.call("set_rain", false)
	wind.gust_started.connect(func(): audio.call("play_wind"))
	_build_menu()
	hint = Transition.make_hint(self, "E — выйти в город")
	Transition.add_scene_arrows(self, 4)
	Transition.fade_in(self)


func _tex(name: String) -> Texture2D:
	return load("res://assets/backgrounds/location_5/%s.png" % name)


func _scroller(name: String, y: float, w: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = name
	sp.texture = _tex(name)
	sp.centered = false
	sp.scale = Vector2(S, S)
	sp.position.y = y
	sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sp.region_enabled = true
	sp.region_rect = Rect2(0, 0, w, sp.texture.get_height())
	add_child(sp)
	return sp


func _build_layers() -> void:
	var w_src: float = world_w / S + 400.0           # с запасом на параллакс
	far = _scroller("far", 0.0, w_src)
	near = _scroller("near", 0.0, w_src)
	# поезд
	train = Sprite2D.new()
	train.name = "Train"
	train.texture = _tex("train")
	train.centered = false
	train.scale = Vector2(S, S)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/passengers.gdshader")
	var boxes: Array[Vector4] = []
	var prms: Array[Vector4] = []
	for p in PEOPLE:
		boxes.append(Vector4(p[0], p[1], p[2], p[3]))
		prms.append(Vector4(p[4], p[5], p[6], p[7]))
	while boxes.size() < 32:
		boxes.append(Vector4())
		prms.append(Vector4())
	mat.set_shader_parameter("box", boxes)
	mat.set_shader_parameter("prm", prms)
	mat.set_shader_parameter("count", PEOPLE.size())
	train.material = mat
	add_child(train)
	# полоса путей перед колёсами
	track = _scroller("track", 488.0 * S, w_src)
	# вращающиеся «спицы» на колёсах
	for c in WHEELS:
		var sp := Sprite2D.new()
		sp.texture = _tex("spokes")
		sp.position = c * S
		sp.scale = Vector2(S, S)
		sp.z_index = 0
		add_child(sp)
		wheels.append(sp)
	# порядок: небо-стена, ближний тоннель, поезд, путь, колёса, потом Фуки (она добавлена в сцену раньше)
	var order: Array = [far, near, train, track]
	for i in order.size():
		move_child(order[i], i)
	for i in wheels.size():
		move_child(wheels[i], order.size() + i)
	_update_layers(0.0)


func _update_layers(delta: float) -> void:
	t += delta
	speed_k = 1.0 + 0.04 * sin(t * 0.35) + 0.02 * sin(t * 0.9)
	var left: float = clampf(cam.get_screen_center_position().x - 640.0, 0.0, world_w - 1280.0)
	# тоннель едет ВПРАВО (поезд едет влево)
	scroll["far"] = fposmod(scroll["far"] - 0.22 * TRAIN_SPEED * speed_k * delta, far.texture.get_width())
	scroll["near"] = fposmod(scroll["near"] - 0.9 * TRAIN_SPEED * speed_k * delta, near.texture.get_width())
	scroll["track"] = fposmod(scroll["track"] - TRAIN_SPEED * speed_k * delta, track.texture.get_width())
	_set_scroll(far, scroll["far"], left, 0.82)
	_set_scroll(near, scroll["near"], left, 0.93)
	_set_scroll(track, scroll["track"], left, 1.0)
	train.position.x = 0.0
	# лёгкая вибрация поезда (меньше пикселя)
	var vib: float = 0.5 * sin(t * 37.0) + 0.3 * sin(t * 23.0 + 1.0)
	train.position.y = vib
	for i in wheels.size():
		wheels[i].position.y = WHEELS[i].y * S + vib
		wheels[i].rotation -= TRAIN_SPEED * speed_k * delta / WHEEL_R


func _set_scroll(sp: Sprite2D, off: float, left: float, factor: float) -> void:
	# позиция спрайта едет с камерой с коэффициентом factor, а картинка сдвигается по region_rect
	sp.position.x = left * (1.0 - factor)
	sp.region_rect.position.x = -off


func _process(delta: float) -> void:
	_update_layers(delta)
	hint.visible = player.position.x > EXIT_X


func _toggle(bar: HBoxContainer, text: String, on: bool, cb: Callable) -> Button:
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
	var wb := Button.new()
	wb.text = "6 · Ветер"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 20)
	wb.pressed.connect(wind.blow)
	bar.add_child(wb)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if player.position.x > EXIT_X:
					Transition.go(self, CITY_SCENE, CITY_SPAWN_X)
			KEY_4, KEY_KP_4:
				sounds_button.button_pressed = not sounds_button.button_pressed
			KEY_5, KEY_KP_5, KEY_M:
				music_button.button_pressed = not music_button.button_pressed
			KEY_6, KEY_KP_6:
				wind.blow()
