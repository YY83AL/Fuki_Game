extends Node2D
## Локация 2: ночное пшеничное поле. Одна широкая картинка, камера следует за Фуки.
## Фуки приходит из дома справа; выход в дом — у правого края, выход к морю — у левого (клавиша E).
## Клавиши как в первой локации: 4 — звуки, 5 или M — музыка, 6 — порыв ветра, 7 — дождь, 8 — туман.

const Transition = preload("res://scripts/transition.gd")
const EXIT_MARGIN := 200.0     ## Правее (ширина − это) работает выход в дом
const HOUSE_SCENE := "res://scenes/location_1.tscn"
const HOUSE_SPAWN_X := 190.0   ## Где Фуки появится у двери в доме
const BEACH_SCENE := "res://scenes/location_3.tscn"
const BEACH_SPAWN_X := 1770.0  ## В сцене 3 Фуки приходит справа
const PLAYER_SIZE := 0.7       ## Фуки здесь на 30% меньше, чем в доме

@onready var player: Player = $Player

var wind: Wind
var fog: Fog
var audio: AudioManager
var indoor_rain: IndoorRain
var hint: Node2D
var world_w: float = 1920.0
var cam: Camera2D
var oak: Node2D
var grass_back: Node2D     ## Трава позади Фуки
var grass_front: Node2D    ## Трава перед Фуки (на переднем плане)
const OAK_BASE_X := 1700.0     ## Где стоит дуб на слое переднего плана (множитель 1.25)
const OAK_BASE_Y := 655.0
var layers: Array = []          ## [спрайт, насколько движется вместе с миром (1 = как мир, меньше — дальше, больше — ближе)]

## Слои фото для параллакса: файл, множитель движения, y, смещение картинки.
const LAYERS := [
	["sky", 0.1, 0.0],       # небо со звёздами и дальний лес — почти стоит на месте
	["field", 0.6, 377.0],   # поле
	["boards", 1.0, 492.0],  # настил, по которому ходит Фуки
	["front", 1.25, 560.0],  # колосья на переднем плане — быстрее всего
]
var sounds_button: Button
var music_button: Button
var rain_button: Button
var fog_button: Button


func _ready() -> void:
	var world_size := Vector2(world_w, 720.0)
	player.x_min = 90.0
	player.x_max = world_w - 90.0
	player.y_min = 520.0
	player.y_max = 560.0
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	cam = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(world_w)
	cam.limit_bottom = int(world_size.y)
	_build_layers()
	if Transition.spawn_x >= 0.0:
		player.position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	cam.make_current()
	cam.reset_smoothing()
	# Дождь: капли падают на настил и оставляют лужицы (по умолчанию выключен, клавиша 7).
	indoor_rain = IndoorRain.new()
	indoor_rain.name = "IndoorRain"
	indoor_rain.top_y = 0.0
	indoor_rain.floor_top = 520.0
	indoor_rain.floor_bottom = 560.0
	indoor_rain.enabled = false
	add_child(indoor_rain)
	var rain_front := Node2D.new()
	rain_front.name = "IndoorRainFront"
	rain_front.set_script(load("res://scripts/indoor_rain_front.gd"))
	add_child(rain_front)
	indoor_rain.setup(player, rain_front, world_size)
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
	_build_menu()
	hint = Transition.make_hint(self, "E — зайти в дом")
	Transition.add_scene_arrows(self, 1)
	Transition.fade_in(self)


func _build_layers() -> void:
	var first: int = 0
	for l in LAYERS:
		var sp := Sprite2D.new()
		sp.name = "Layer_" + l[0]
		sp.texture = load("res://assets/backgrounds/location_2/%s.jpg" % l[0])
		sp.centered = false
		sp.position.y = l[2]
		add_child(sp)
		move_child(sp, first)
		first += 1
		layers.append([sp, l[1]])
		if l[0] == "sky":
			# Мерцающие звёзды едут вместе с небом (картинка неба шире фото на 12 px слева).
			var stars := Node2D.new()
			stars.name = "Stars"
			stars.set_script(load("res://scripts/star_twinkle.gd"))
			stars.position.x = 12.0
			sp.add_child(stars)
	# Дуб на переднем плане: поверх Фуки, двигается быстрее мира (как колосья).
	oak = Node2D.new()
	oak.name = "Oak"
	oak.set_script(load("res://scripts/oak.gd"))
	oak.position.y = OAK_BASE_Y
	add_child(oak)
	# Высокая трава: низкая стена позади Фуки и высокие пучки спереди (двигается как передний план).
	grass_back = Node2D.new()
	grass_back.name = "GrassBack"
	grass_back.set_script(load("res://scripts/tall_grass.gd"))
	grass_back.set("count", 220)
	grass_back.set("h_min", 90.0)
	grass_back.set("h_max", 190.0)
	grass_back.set("width_px", world_w + 40.0)
	grass_back.set("seed_value", 3)
	grass_back.set("player", player)
	grass_back.position = Vector2(0.0, 585.0)
	add_child(grass_back)
	move_child(grass_back, 3)          # над настилом, под колосьями и Фуки
	grass_front = Node2D.new()
	grass_front.name = "GrassFront"
	grass_front.set_script(load("res://scripts/tall_grass.gd"))
	grass_front.set("count", 260)
	grass_front.set("h_min", 150.0)
	grass_front.set("h_max", 330.0)
	grass_front.set("width_px", world_w * 1.25 + 40.0)
	grass_front.set("base_color", Color(0.03, 0.07, 0.07))
	grass_front.set("tip_color", Color(0.20, 0.32, 0.22))
	grass_front.set("seed_value", 11)
	grass_front.set("player", player)
	grass_front.position = Vector2(0.0, 735.0)
	add_child(grass_front)
	_update_layers()


func _update_layers() -> void:
	var left: float = clampf(cam.get_screen_center_position().x - 640.0, 0.0, world_w - 1280.0)
	for l in layers:
		l[0].position.x = left * (1.0 - l[1])
	if oak:
		oak.position.x = OAK_BASE_X + left * (1.0 - 1.25)
	if grass_front:
		grass_front.position.x = left * (1.0 - 1.25)


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
	_update_layers()
	var at_right: bool = player.position.x > world_w - EXIT_MARGIN
	var at_left: bool = player.position.x < EXIT_MARGIN
	hint.visible = at_right or at_left
	hint.text = "E — зайти в дом" if at_right else "E — к морю"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if player.position.x > world_w - EXIT_MARGIN:
					Transition.go(self, HOUSE_SCENE, HOUSE_SPAWN_X)
				elif player.position.x < EXIT_MARGIN:
					Transition.go(self, BEACH_SCENE, BEACH_SPAWN_X)
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
