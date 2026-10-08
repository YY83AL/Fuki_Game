extends Node2D
## Локация 6: чистый белый лист. Фуки идёт по чёрной линии, нарисованной гуашью.
## Клавиши: 4 — звуки, 5 или M — музыка. Фон серо-бежевый (#CFC3AE), чтобы эффекты света работали.

const Transition = preload("res://scripts/transition.gd")
const WORLD_W := 2560.0
const PLAYER_SIZE := 0.72        ## Как на локациях 2–5
const LINE_Y := 650.0           ## Центр линии по высоте экрана

@onready var player: Player = $Player
var audio: AudioManager
var wind: Wind
var sounds_button: Button
var music_button: Button


func _ready() -> void:
	set_meta("fx_no_puddles", true)   # лужи на чёрной линии не нужны
	set_meta("fx_lamp_k", 0.22)       # фон светлый — фонарики мягче
	player.x_min = 90.0
	player.x_max = WORLD_W - 90.0
	player.y_min = LINE_Y - 4.0
	player.y_max = LINE_Y + 0.0
	player.scale_back *= PLAYER_SIZE
	player.scale_front *= PLAYER_SIZE
	player.position.y = LINE_Y - 2.0
	if player.shadow_soft:
		player.shadow_soft.visible = false
	if player.shadow_core:
		player.shadow_core.modulate.a = 0.55
	var cam: Camera2D = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD_W)
	cam.limit_bottom = 720
	var bg := Sprite2D.new()
	bg.name = "White"
	bg.texture = load("res://assets/backgrounds/location_6/white.png")
	bg.centered = false
	bg.scale = Vector2(0.5, 0.5)
	bg.region_enabled = true
	bg.region_rect = Rect2(0, 0, WORLD_W * 2.0, 1440)
	add_child(bg)
	move_child(bg, 0)
	var line := Sprite2D.new()
	line.name = "GouacheLine"
	line.texture = load("res://assets/backgrounds/location_6/line.png")
	line.centered = false
	line.scale = Vector2(0.5, 0.5)
	line.position = Vector2(0, LINE_Y - 30.0)
	add_child(line)
	move_child(line, 1)
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
	Transition.add_scene_arrows(self, 0)
	Transition.fade_in(self)


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
	var wb := Button.new()
	wb.text = "6 · Ветер"
	wb.focus_mode = Control.FOCUS_NONE
	wb.add_theme_font_size_override("font_size", 20)
	wb.pressed.connect(wind.blow)
	bar.add_child(wb)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_4, KEY_KP_4:
				sounds_button.button_pressed = not sounds_button.button_pressed
			KEY_5, KEY_KP_5, KEY_M:
				music_button.button_pressed = not music_button.button_pressed
			KEY_6, KEY_KP_6:
				wind.blow()
