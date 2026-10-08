extends Node2D
## Локация 4: городская улица мегаполиса. Дорога идёт в горку вправо-вверх, камера поднимается вместе с Фуки.
## Слои с параллаксом и по горизонтали, и по вертикали; по дороге ездят машины.
## Фуки приходит справа (с вершины улицы); выход к морю — у правого края (клавиша E).
## Клавиши как в первой локации: 4 — звуки, 5 или M — музыка, 6 — порыв ветра, 7 — дождь, 8 — туман.

const Transition = preload("res://scripts/transition.gd")
const EXIT_MARGIN := 200.0     ## Правее (ширина − это) работает выход к морю
const BEACH_SCENE := "res://scenes/location_3.tscn"
const METRO_SCENE := "res://scenes/location_5.tscn"
const METRO_SPAWN_X := 2280.0   ## В метро Фуки заходит справа
const BEACH_SPAWN_X := 150.0   ## На пляже Фуки появится у левого края
const SLOPE := 0.2             ## Наклон дороги: на каждые 100 px вправо — 20 px вверх
const WORLD := Vector2(2600.0, 1300.0)
const PLAYER_SIZE := 0.7       ## Фуки здесь на 30% меньше, чем в доме

@onready var player: Player = $Player

var wind: Wind
var fog: Fog
var audio: AudioManager
var indoor_rain: IndoorRain
var hint: Node2D
var world_w: float = 2600.0
var cam: Camera2D
var layers: Array = []          ## [спрайт, множитель параллакса]
var cars: Node2D
var vignette_mat: ShaderMaterial

## Слои: файл, множитель параллакса (1 — как мир, меньше — дальше), расширение.
const LAYERS := [
	["sky", 0.08, "jpg"],    # небо
	["far", 0.3, "png"],     # далёкие башни в дымке
	["mid", 0.6, "png"],     # башни ближе
	["near", 1.0, "png"],    # дома, витрины, тротуар и дорога
	["front", 1.25, "png"],  # фонарные столбы и провода впереди
]
var sounds_button: Button
var music_button: Button
var rain_button: Button
var fog_button: Button


func _ground_y(x: float) -> float:
	return 1170.0 - SLOPE * x


func _ready() -> void:
	player.process_priority = -1      # сначала двигается Фуки, потом мы ставим её на склон
	process_priority = 5
	player.horizontal_only = true
	player.x_min = 90.0
	player.x_max = world_w - 90.0
	player.y_min = -5000.0            # высоту задаёт склон, а не клавиши W/S
	player.y_max = 5000.0
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	cam = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD.x)
	cam.limit_bottom = int(WORLD.y)
	player.position = Vector2(WORLD.x - 150.0, _ground_y(WORLD.x - 150.0))
	_build_layers()
	if Transition.spawn_x >= 0.0:
		player.position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	player.position.y = _ground_y(player.position.x)
	cam.make_current()
	cam.reset_smoothing()
	# Дождь: капли падают на настил и оставляют лужицы (по умолчанию выключен, клавиша 7).
	indoor_rain = IndoorRain.new()
	indoor_rain.name = "IndoorRain"
	indoor_rain.enabled = false
	add_child(indoor_rain)
	var rain_front := Node2D.new()
	rain_front.name = "IndoorRainFront"
	rain_front.set_script(load("res://scripts/indoor_rain_front.gd"))
	add_child(rain_front)
	indoor_rain.setup(player, rain_front, WORLD)
	wind = Wind.new()
	wind.name = "Wind"
	add_child(wind)
	wind.setup(null)
	fog = Fog.new()
	fog.name = "Fog"
	add_child(fog)
	fog.camera_source = player
	audio = AudioManager.new()
	audio.name = "Audio"
	add_child(audio)
	var list: Array[Player] = [player]
	audio.setup(list, null)
	audio.call("set_rain", false)
	wind.gust_started.connect(func(): audio.call("play_wind"))
	_build_vignette()
	_build_menu()
	hint = Transition.make_hint(self, "E — к морю")
	Transition.add_scene_arrows(self, 3)
	Transition.fade_in(self)


func _build_layers() -> void:
	var first: int = 0
	for l in LAYERS:
		var sp := Sprite2D.new()
		sp.name = "Layer_" + l[0]
		sp.texture = load("res://assets/backgrounds/location_4/%s.%s" % [l[0], l[2]])
		sp.centered = false
		add_child(sp)
		layers.append([sp, l[1]])
		if l[0] == "front":
			move_child(sp, -1)       # столбы — поверх Фуки и машин (потом поверх всего встанут дождь и туман)
		else:
			move_child(sp, first)
			first += 1
	# машины едут между домами и Фуки... и перед ней: ближняя к зрителю часть дороги
	cars = Node2D.new()
	cars.name = "Cars"
	cars.set_script(load("res://scripts/cars.gd"))
	add_child(cars)
	move_child(cars, first + 1)      # сразу после Фуки
	_update_layers()


func _update_layers() -> void:
	var c: Vector2 = cam.get_screen_center_position()
	var left: float = clampf(c.x - 640.0, 0.0, WORLD.x - 1280.0)
	var top: float = clampf(c.y - 360.0, 0.0, WORLD.y - 720.0)
	for l in layers:
		var f: float = l[1]
		l[0].position = Vector2(left * (1.0 - f), top * (1.0 - f))


func _build_vignette() -> void:
	## Тёмная виньетка по краям экрана; вокруг Фуки свет нормальный.
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = load("res://assets/shaders/vignette.gdshader")
	r.material = vignette_mat
	layer.add_child(r)


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
	rain_button = _toggle(bar, "7 · Дождь", false, _set_rain)
	fog_button = _toggle(bar, "8 · Туман", false, func(on: bool): fog.set_enabled(on))


func _set_rain(on: bool) -> void:
	indoor_rain.enabled = on
	audio.call("set_rain", on)


func _process(_delta: float) -> void:
	# Фуки стоит на склоне: высота по x, тело чуть наклонено вдоль дороги, а камера сама едет за ней вверх.
	player.position.y = _ground_y(player.position.x)
	player.rotation = lerp_angle(player.rotation, -atan(SLOPE) * 0.8, 0.2)
	_update_layers()
	# дождь падает вокруг Фуки на тротуар и дорогу
	indoor_rain.top_y = player.position.y - 700.0
	indoor_rain.floor_top = player.position.y - 40.0
	indoor_rain.floor_bottom = player.position.y + 260.0
	if vignette_mat:
		var sp: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0.0, -60.0 * PLAYER_SIZE / 0.56)
		vignette_mat.set_shader_parameter("center_px", sp)
	var at_right: bool = player.position.x > world_w - EXIT_MARGIN
	var at_left: bool = player.position.x < EXIT_MARGIN
	hint.visible = at_right or at_left
	hint.text = "E — к морю" if at_right else "E — в метро"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if player.position.x > world_w - EXIT_MARGIN:
					Transition.go(self, BEACH_SCENE, BEACH_SPAWN_X)
				elif player.position.x < EXIT_MARGIN:
					Transition.go(self, METRO_SCENE, METRO_SPAWN_X)
			KEY_4, KEY_KP_4:
				sounds_button.button_pressed = not sounds_button.button_pressed
			KEY_5, KEY_KP_5, KEY_M:
				music_button.button_pressed = not music_button.button_pressed
			KEY_6, KEY_KP_6:
				wind.blow()
			KEY_7, KEY_KP_7:
				rain_button.button_pressed = not rain_button.button_pressed
			KEY_8, KEY_KP_8:
				fog_button.button_pressed = not fog_button.button_pressed
