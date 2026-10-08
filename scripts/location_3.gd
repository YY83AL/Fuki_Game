extends Node2D
## Локация 3: пляж и море на рассвете. Слои с параллаксом, камера следует за Фуки.
## Фуки приходит из поля справа; выход обратно в поле — у правого края (клавиша E). Шум прибоя играет сам.
## Клавиши как в первой локации: 4 — звуки, 5 или M — музыка, 6 — порыв ветра, 7 — дождь, 8 — туман.

const Transition = preload("res://scripts/transition.gd")
const EXIT_MARGIN := 200.0     ## Правее (ширина − это) работает выход в дом
const FIELD_SCENE := "res://scenes/location_2.tscn"
const FIELD_SPAWN_X := 150.0   ## Где Фуки появится в поле (у левого края)
const CITY_SCENE := "res://scenes/location_4.tscn"
const CITY_SPAWN_X := 2450.0   ## В городе Фуки появляется справа, на вершине улицы
const PLAYER_SIZE := 0.7       ## Фуки здесь на 30% меньше, чем в доме

@onready var player: Player = $Player

var wind: Wind
var fog: Fog
var audio: AudioManager
var indoor_rain: IndoorRain
var hint: Node2D
var world_w: float = 1920.0
var cam: Camera2D
var layers: Array = []          ## [спрайт, насколько движется вместе с миром (1 = как мир, меньше — дальше, больше — ближе)]

## Слои фото для параллакса: файл, множитель движения, y, смещение картинки.
const LAYERS := [
	["sky", 0.1, 0.0, "jpg", false],      # небо и солнце — почти стоят на месте
	["sea", 0.6, 322.0, "jpg", false],    # море и берег
	["glint", 0.1, 322.0, "png", true],   # солнечная дорожка на воде (едет вместе с небом, светится)
	["ground", 1.0, 492.0, "jpg", false], # песок под ногами
	["front", 1.25, 560.0, "jpg", false], # песок вблизи — быстрее всего
]
var sea_sound: AudioStreamPlayer
var prints: Node2D
var last_pos: Vector2 = Vector2.ZERO
var step_acc: float = 0.0
var step_side: float = 1.0
var sounds_button: Button
var music_button: Button
var rain_button: Button
var fog_button: Button


func _ready() -> void:
	var world_size := Vector2(world_w, 720.0)
	player.x_min = 90.0
	player.x_max = world_w - 90.0
	player.y_min = 500.0
	player.y_max = 640.0
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	cam = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(world_w)
	cam.limit_bottom = int(world_size.y)
	_build_layers()
	_setup_water()
	_setup_prints()
	if Transition.spawn_x >= 0.0:
		player.position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	cam.make_current()
	cam.reset_smoothing()
	# Дождь: капли падают на настил и оставляют лужицы (по умолчанию выключен, клавиша 7).
	indoor_rain = IndoorRain.new()
	indoor_rain.name = "IndoorRain"
	indoor_rain.top_y = 0.0
	indoor_rain.floor_top = 500.0
	indoor_rain.floor_bottom = 640.0
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
	audio.city_db = -80.0     # на пляже города не слышно
	add_child(audio)
	var list: Array[Player] = [player]
	audio.setup(list, null)
	audio.call("set_rain", false)
	wind.gust_started.connect(func(): audio.call("play_wind"))
	_build_menu()
	var waves: AudioStreamOggVorbis = load("res://assets/audio/waves.ogg")
	waves.loop = true
	sea_sound = AudioStreamPlayer.new()
	sea_sound.stream = waves
	sea_sound.volume_db = -80.0
	add_child(sea_sound)
	sea_sound.play()
	create_tween().tween_property(sea_sound, "volume_db", -9.0 if GameSettings.sounds else -80.0, 2.0)
	hint = Transition.make_hint(self, "E — вернуться в поле")
	Transition.add_scene_arrows(self, 2)
	Transition.fade_in(self)


func _build_layers() -> void:
	var first: int = 0
	for l in LAYERS:
		var sp := Sprite2D.new()
		sp.name = "Layer_" + l[0]
		sp.texture = load("res://assets/backgrounds/location_3/%s.%s" % [l[0], l[3]])
		sp.centered = false
		sp.position.y = l[2]
		if l[4]:
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			sp.material = m
		add_child(sp)
		move_child(sp, first)
		first += 1
		layers.append([sp, l[1]])
	_update_layers()


## Анимация воды: рябь, бегущие гребни, прибой и мерцающая солнечная дорожка.
func _setup_water() -> void:
	for l in layers:
		var sp: Sprite2D = l[0]
		if sp.name == "Layer_sky":
			# Белые чайки летают в небе и вместе с ним сдвигаются при ходьбе.
			var birds := Node2D.new()
			birds.name = "Birds"
			birds.set_script(load("res://scripts/birds.gd"))
			sp.add_child(birds)
		elif sp.name == "Layer_sea":
			var m := ShaderMaterial.new()
			m.shader = load("res://assets/shaders/sea_waves.gdshader")
			sp.material = m
		elif sp.name == "Layer_glint":
			var m2 := ShaderMaterial.new()
			m2.shader = load("res://assets/shaders/glint.gdshader")
			sp.material = m2


## Следы на песке: лежат на земле (между слоями и Фуки), потом исчезают.
func _setup_prints() -> void:
	prints = Node2D.new()
	prints.name = "Footprints"
	prints.set_script(load("res://scripts/footprints.gd"))
	add_child(prints)
	move_child(prints, layers.size())
	last_pos = player.position


func _update_prints() -> void:
	var p: Vector2 = player.position
	if player.air_height > 0.5:        # в прыжке следов нет
		last_pos = p
		return
	step_acc += p.distance_to(last_pos)
	last_pos = p
	var s: float = player.base_scale
	if step_acc >= 70.0 * s:
		step_acc = 0.0
		step_side = -step_side
		var dir: float = signf(player.velocity.x) if absf(player.velocity.x) > 5.0 else 1.0
		prints.call("add_print", p + Vector2(0.0, step_side * 3.0 * s), dir, s, step_side)


func _update_layers() -> void:
	var left: float = clampf(cam.get_screen_center_position().x - 640.0, 0.0, world_w - 1280.0)
	for l in layers:
		l[0].position.x = left * (1.0 - l[1])


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
	sounds_button = _toggle(bar, "4 · Звуки", true, _set_sounds)
	music_button = _toggle(bar, "5 · Музыка", true, func(on: bool): audio.call("set_music", on))
	var wb := Button.new()
	wb.text = "6 · Ветер"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 20)
	wb.pressed.connect(wind.blow)
	bar.add_child(wb)
	rain_button = _toggle(bar, "7 · Дождь", false, _set_rain)
	fog_button = _toggle(bar, "8 · Туман", false, func(on: bool): fog.set_enabled(on))


func _set_sounds(on: bool) -> void:
	audio.call("set_sounds", on)
	if sea_sound:
		create_tween().tween_property(sea_sound, "volume_db", -9.0 if on else -80.0, 0.6)


func _set_rain(on: bool) -> void:
	indoor_rain.enabled = on
	audio.call("set_rain", on)


func _process(_delta: float) -> void:
	_update_layers()
	_update_prints()
	var at_right: bool = player.position.x > world_w - EXIT_MARGIN
	var at_left: bool = player.position.x < EXIT_MARGIN
	hint.visible = at_right or at_left
	hint.text = "E — вернуться в поле" if at_right else "E — в город"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if player.position.x > world_w - EXIT_MARGIN:
					Transition.go(self, FIELD_SCENE, FIELD_SPAWN_X)
				elif player.position.x < EXIT_MARGIN:
					Transition.go(self, CITY_SCENE, CITY_SPAWN_X)
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
