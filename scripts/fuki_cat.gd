class_name FukiCat
extends Node2D
## Кот в жёлтом плаще: покадровая анимация вида сбоку (стойка, ходьба, бег, прыжок).
## Подключается к Player так же, как скелетные куклы: Player вызывает animate(delta, скорость, направление, в_воздухе).
## Кадры лежат в assets/characters/cat_side/side_00..17.png (все нарисованы лицом вправо, земля — в точке (150, 302)).

@export var frame_scale: float = 1.0            ## Размер кота (1 — как нарисовано)
@export var walk_fps: float = 9.0               ## Кадров в секунду при ходьбе (растёт со скоростью)
@export var run_fps: float = 14.0               ## Кадров в секунду на полном бегу
@export var run_threshold: float = 1.25         ## С какой скорости (в долях ходьбы) включается бег
@export var jump_up_seconds: float = 0.20       ## Сколько показывать «взлёт», потом «полёт»
@export var land_seconds: float = 0.12          ## Сколько показывать приземление
@export var breathe_amount: float = 0.012       ## Дыхание в стойке
@export var ground_x: float = 150.0             ## Точка земли в кадре (центр тени)
@export var ground_y: float = 302.0
@export var crouch_seconds: float = 0.05        ## Короткий присед перед прыжком
@export var turn_seconds: float = 0.10          ## Быстрый разворот при смене направления
@export var cloak_wind: bool = true             ## Плащ колышется от ветра (кнопка 6)
@export var cloak_amount: float = 20.0          ## Размах колыхания плаща (пикселей кадра)

const IDLE := 0
const WALK := [1, 2, 3, 4, 5]
const RUN := [6, 7, 8, 9, 10, 11, 12]
const CROUCH := 13
const JUMP_UP := 14
const JUMP_AIR := 15
const LAND := 16

var sprite: Sprite2D
var textures: Array[Texture2D] = []
var facing: float = 1.0
var t: float = 0.0
var anim_time: float = 0.0
var air_time: float = 0.0
var land_left: float = 0.0
var was_in_air: bool = false
var running: bool = false
var mat: ShaderMaterial
var turn_left: float = 0.0
var turn_from: float = 1.0


func _ready() -> void:
	for i in 18:
		textures.append(load("res://assets/characters/cat_side/side_%02d.png" % i))
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(-ground_x, -ground_y)
	sprite.texture = textures[IDLE]
	if cloak_wind:
		mat = ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/cat_cloak.gdshader")
		mat.set_shader_parameter("amount", cloak_amount)
		sprite.material = mat
	var holder := Node2D.new()
	holder.name = "Flip"
	add_child(holder)
	holder.add_child(sprite)
	scale = Vector2(frame_scale, frame_scale)


func animate(delta: float, speed_ratio: float, face: float, in_air: bool) -> void:
	t += delta
	if face != 0.0 and face != facing:
		if not in_air and turn_seconds > 0.0:
			turn_from = facing
			turn_left = turn_seconds
		facing = face
	var idx: int = IDLE
	var sx: float = facing
	if turn_left > 0.0 and not in_air:
		turn_left -= delta
		var k: float = 1.0 - clampf(turn_left / turn_seconds, 0.0, 1.0)
		# сжимаемся к линии и разворачиваемся (не уже 0.35, чтобы не было «листка»)
		var v: float = lerpf(turn_from, facing, k)
		sx = signf(v) * maxf(absf(v), 0.35)
	$Flip.scale.x = sx
	if in_air:
		if not was_in_air:
			air_time = 0.0
		air_time += delta
		idx = CROUCH if air_time < crouch_seconds else (JUMP_UP if air_time < crouch_seconds + jump_up_seconds else JUMP_AIR)
		land_left = land_seconds
	elif land_left > 0.0:
		land_left -= delta
		idx = LAND
	elif speed_ratio > 0.05:
		if running:
			running = speed_ratio > run_threshold * 0.92
		else:
			running = speed_ratio > run_threshold
		var frames: Array = RUN if running else WALK
		var fps: float = (run_fps * clampf(speed_ratio / 1.75, 0.6, 1.2)) if running else (walk_fps * clampf(speed_ratio, 0.5, 1.2))
		anim_time += delta * fps
		idx = frames[int(anim_time) % frames.size()]
	else:
		anim_time = 0.0
		running = false
		idx = IDLE
	was_in_air = in_air
	sprite.texture = textures[idx]
	# лёгкое дыхание в стойке (масштаб от земли)
	var breathe: float = 1.0 + breathe_amount * sin(t * 2.2) * (1.0 if idx == IDLE else 0.0)
	$Flip.scale.y = breathe
	if mat:
		mat.set_shader_parameter("wind", Wind.gust * Wind.dir * facing)
