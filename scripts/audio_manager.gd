class_name AudioManager
extends Node
## Звук игры: спокойный джаз, дождь и город на фоне, мягкие шаги, прыжок и приземление, гром.
## Клавиша M — включить/выключить музыку. Все громкости можно менять здесь, в Инспекторе.

@export_group("Громкость (дБ, 0 = как в файле)")
@export var music_db: float = -9.0
@export var rain_db: float = -10.0
@export var city_db: float = -17.0
@export var steps_db: float = -8.0
@export var jump_db: float = -8.0
@export var thunder_db: float = -6.0
@export var wind_db: float = -5.0
@export_group("Шаги")
@export var step_distance: float = 95.0    ## Через сколько пикселей пути звучит один шаг

const DIR := "res://assets/audio/"

var players: Array[Player] = []
var current: Player
var music: AudioStreamPlayer
var rain: AudioStreamPlayer
var city: AudioStreamPlayer
var sfx: Array[AudioStreamPlayer] = []
var sfx_i: int = 0
var steps: Array[AudioStream] = []
var jump_s: AudioStream
var land_s: AudioStream
var wind_s: AudioStream
var thunder_s: Array[AudioStream] = []
var walked: float = 0.0
var foot_synced: Dictionary = {}
var was_air: Dictionary = {}
var music_on: bool = true
var sounds_on: bool = true       ## Звуки (шаги, прыжок, дождь, город, ветер, гром) включены
var rain_wanted: bool = true     ## Дождь включён клавишей 7


func setup(p: Array[Player], storm: Node) -> void:
	players = p
	for pl in players:
		was_air[pl] = false
		if pl.rig and pl.rig.has_signal("foot_down"):                # шаги звучат в момент касания стопы
			pl.rig.foot_down.connect(_on_foot.bind(pl))
			foot_synced[pl] = true
	if storm and storm.has_signal("flash_started"):
		storm.flash_started.connect(_on_flash)


func _ready() -> void:
	music = _loop("jazz", music_db)
	rain = _loop("rain", rain_db)
	city = _loop("city", city_db)
	for i in 6:
		var s := AudioStreamPlayer.new()
		add_child(s)
		sfx.append(s)
	for i in 4:
		steps.append(load(DIR + "step_%d.ogg" % i))
	jump_s = load(DIR + "jump.ogg")
	land_s = load(DIR + "land.ogg")
	wind_s = load(DIR + "wind.ogg")
	for i in 2:
		thunder_s.append(load(DIR + "thunder_%d.ogg" % i))


func _loop(file: String, db: float) -> AudioStreamPlayer:
	var st: AudioStreamOggVorbis = load(DIR + file + ".ogg")
	st.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	add_child(p)
	p.play()
	return p


## Музыка вкл/выкл (плавно).
func set_music(on: bool) -> void:
	music_on = on
	_fade(music, music_db if on else -80.0)


## Все остальные звуки вкл/выкл: шаги, прыжок, дождь, город, ветер, гром.
func set_sounds(on: bool) -> void:
	sounds_on = on
	if not on:
		for s in sfx:
			s.stop()
	_update_ambience()


func _update_ambience() -> void:
	_fade(rain, rain_db if (sounds_on and rain_wanted) else -80.0)
	_fade(city, city_db if sounds_on else -80.0)


func _fade(p: AudioStreamPlayer, db: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", db, 0.8)


func _play(stream: AudioStream, db: float, pitch: float = 1.0) -> void:
	if not sounds_on:
		return
	var s: AudioStreamPlayer = sfx[sfx_i]
	sfx_i = (sfx_i + 1) % sfx.size()
	s.stream = stream
	s.volume_db = db
	s.pitch_scale = pitch
	s.play()


func _process(delta: float) -> void:
	for pl in players:
		if not pl.active:
			was_air[pl] = pl.air_height > 0.0
			continue
		var air: bool = pl.air_height > 0.0
		if air and not was_air[pl]:
			_play(jump_s, jump_db, randf_range(0.97, 1.03))
		elif was_air[pl] and not air:
			_play(land_s, jump_db - 2.0, randf_range(0.97, 1.03))
		was_air[pl] = air
		if not air and not foot_synced.get(pl, false):
			var v: float = absf(pl.velocity.x)
			walked += v * delta
			if walked >= step_distance:
				walked = 0.0
				var k: float = clampf(v / pl.speed, 0.0, 1.0)
				_play(steps[randi() % steps.size()], steps_db - (1.0 - k) * 6.0, randf_range(0.94, 1.06))
		else:
			walked = step_distance * 0.5


## Звук шага в момент касания стопы (power — сила шага 0..1).
func _on_foot(side: int, power: float, pl: Player) -> void:
	if not pl.active or pl.air_height > 0.0:
		return
	var db: float = steps_db - (1.0 - power) * 6.0 - (1.5 if side == 1 else 0.0)
	_play(steps[randi() % steps.size()], db, randf_range(0.94, 1.06) + (0.02 if side == 1 else -0.02))


## Звук порыва ветра.
func play_wind() -> void:
	_play(wind_s, wind_db)


## Дождь включён или выключен (плавно).
func set_rain(on: bool) -> void:
	rain_wanted = on
	_update_ambience()


func _on_flash() -> void:
	# Гром приходит с задержкой после вспышки: чем дальше гроза, тем позже.
	await get_tree().create_timer(randf_range(0.6, 2.5)).timeout
	_play(thunder_s[randi() % thunder_s.size()], thunder_db, randf_range(0.92, 1.05))
