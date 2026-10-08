extends Node2D
## Локация 1: фон на всю ширину, листья на полу, Фуки, дождь в доме, ветер и звук.
## Камера следует за Фуки. Клавиши: 4 — звуки вкл/выкл, 5 (или M) — музыка вкл/выкл, 6 — порыв ветра, 7 — дождь вкл/выкл (за окнами, в доме и звук), 8 — туман вкл/выкл, M — музыка.

const Transition = preload("res://scripts/transition.gd")
const DOOR_X := 200.0          ## Левее этого места Фуки стоит у двери и может выйти (E)
const FIELD_SCENE := "res://scenes/location_2.tscn"
const FIELD_SPAWN_X := 1770.0   ## В поле Фуки приходит справа

var door_hint: Node2D
const DoorLockScript = preload("res://scripts/door_lock.gd")
var door_lock: Node2D
const LOCK_POS := Vector2(105.0, 300.0)   ## Где на двери висит кодовый замок

@onready var background: Sprite2D = $Background
@onready var leaves: Leaves = $Leaves
@onready var leaves_front: Node2D = $LeavesFront

var players: Array[Player] = []
var current: int = 0
var wind: Wind
var indoor_rain: IndoorRain
var rain_button: Button
var sounds_button: Button
var music_button: Button
var fog_button: Button
var fog: Fog
var audio: AudioManager
var rain_on: bool = true


func _ready() -> void:
	players = [$Player]
	var world_size: Vector2 = background.texture.get_size() * background.scale
	for p in players:
		p.x_max = world_size.x - 90.0
		# Камера не выходит за края картинки.
		var cam: Camera2D = p.get_node("Camera2D")
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(world_size.x)
		cam.limit_bottom = int(world_size.y)
	leaves.setup(players[0], leaves_front, world_size)
	# Дождь в доме: капли и лужи за Фуки, ближние капли поверх неё.
	indoor_rain = IndoorRain.new()
	indoor_rain.name = "IndoorRain"
	add_child(indoor_rain)
	move_child(indoor_rain, leaves.get_index() + 1)
	var rain_front := Node2D.new()
	rain_front.name = "IndoorRainFront"
	rain_front.set_script(load("res://scripts/indoor_rain_front.gd"))
	add_child(rain_front)
	move_child(rain_front, leaves_front.get_index() + 1)
	indoor_rain.setup(players[0], rain_front, world_size)
	wind = Wind.new()
	wind.name = "Wind"
	add_child(wind)
	wind.setup(get_node_or_null("Rain"))
	fog = Fog.new()
	fog.name = "Fog"
	add_child(fog)
	fog.camera_source = players[0]
	audio = AudioManager.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(players, get_node_or_null("Storm"))
	wind.gust_started.connect(func(): audio.call("play_wind"))
	_build_menu()
	if Transition.spawn_x >= 0.0:
		players[0].position.x = Transition.spawn_x
		Transition.spawn_x = -1.0
	_select(0)
	door_lock = DoorLockScript.new()
	door_lock.name = "DoorLock"
	door_lock.position = LOCK_POS
	door_lock.player = players[0]
	door_lock.unlocked.connect(func(): Transition.go(self, FIELD_SCENE, FIELD_SPAWN_X))
	add_child(door_lock)
	door_hint = Transition.make_hint(self, "E — выйти на улицу")
	Transition.add_scene_arrows(self, 0)
	Transition.fade_in(self)


func _process(_delta: float) -> void:
	door_hint.visible = false     # подсказку заменила иконка над замком
	door_lock.set_near(players[0].position.x < DOOR_X)


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
	var sb := Button.new()
	sb.text = "4 · Звуки"
	sb.toggle_mode = true
	sb.button_pressed = GameSettings.sounds
	sb.focus_mode = Control.FOCUS_NONE
	sb.add_theme_font_size_override("font_size", 20)
	sb.toggled.connect(func(on: bool): audio.call("set_sounds", on))
	bar.add_child(sb)
	sounds_button = sb
	var mb := Button.new()
	mb.text = "5 · Музыка"
	mb.toggle_mode = true
	mb.button_pressed = GameSettings.music
	mb.focus_mode = Control.FOCUS_NONE
	mb.add_theme_font_size_override("font_size", 20)
	mb.toggled.connect(func(on: bool): audio.call("set_music", on))
	bar.add_child(mb)
	music_button = mb
	var wb := Button.new()
	wb.text = "6 · Ветер"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 20)
	wb.pressed.connect(wind.blow)
	bar.add_child(wb)
	var rb := Button.new()
	rb.text = "7 · Дождь"
	rb.toggle_mode = true
	rb.button_pressed = GameSettings.rain
	rb.focus_mode = Control.FOCUS_NONE
	rb.add_theme_font_size_override("font_size", 20)
	rb.toggled.connect(_set_rain)
	bar.add_child(rb)
	rain_button = rb
	var fb := Button.new()
	fb.text = "8 · Туман"
	fb.toggle_mode = true
	fb.focus_mode = Control.FOCUS_NONE
	fb.add_theme_font_size_override("font_size", 20)
	fb.toggled.connect(func(on: bool): fog.set_enabled(on))
	bar.add_child(fb)
	fog_button = fb
	fb.button_pressed = GameSettings.fog
	# Общие настройки: запоминаем выбор игрока и применяем сохранённое состояние к этой сцене.
	sb.toggled.connect(func(v: bool): GameSettings.sounds = v)
	mb.toggled.connect(func(v: bool): GameSettings.music = v)
	rb.toggled.connect(func(v: bool): GameSettings.rain = v)
	fb.toggled.connect(func(v: bool): GameSettings.fog = v)
	audio.call("set_sounds", sb.button_pressed)
	audio.call("set_music", mb.button_pressed)
	_set_rain(rb.button_pressed)
	fog.set_enabled(fb.button_pressed)


func _set_rain(on: bool) -> void:
	rain_on = on
	indoor_rain.enabled = on
	var window_rain: Node = get_node_or_null("Rain")
	if window_rain:
		window_rain.visible = on
	audio.call("set_rain", on)


func _select(index: int) -> void:
	current = index
	for i in players.size():
		var p: Player = players[i]
		p.active = (i == index)
		var cam: Camera2D = p.get_node("Camera2D")
		cam.enabled = (i == index)
		if i == index:
			cam.make_current()
			cam.reset_smoothing()
	leaves.player = players[index]
	if indoor_rain:
		indoor_rain.player = players[index]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if players[0].position.x < DOOR_X:
					door_lock.open()
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
