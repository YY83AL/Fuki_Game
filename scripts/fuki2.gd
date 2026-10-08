class_name Fuki2
extends Node2D
## Фуки (персонаж 2): векторная анимация — стойка, ходьба, прыжок и разворот.
## Кадры лежат в assets/characters/fuki2_hd/, анимации собраны в узле Sprite (SpriteFrames).
## Рисунок смотрит вправо; влево отзеркаливается.
## При смене направления проигрывается разворот (turn_left / turn_right).
##
## Метод animate() вызывается из player.gd каждый кадр.

@export var walk_fps_at_full_speed: float = 1.0   ## Множитель скорости кадров при полной скорости ходьбы
@export var breathe_amount: float = 0.012         ## Лёгкое «дыхание» в стойке (0 — выключить)
@export var squash_on_land: float = 0.10          ## Насколько Фуки приседает при приземлении (0 — выключить)
@export var use_turn_animation: bool = true       ## Проигрывать разворот при смене направления

@onready var sprite: AnimatedSprite2D = $Sprite

var time: float = 0.0
var was_in_air: bool = false
var squash: float = 0.0
var base_scale: Vector2
var facing: float = 1.0       ## Куда Фуки смотрит сейчас: 1 — вправо, -1 — влево
var turning: bool = false
var turn_to: float = 1.0


func _ready() -> void:
	base_scale = scale
	sprite.animation_finished.connect(_on_animation_finished)


## speed_ratio: 0 — стоит, 1 — бежит на полной скорости.
## face: 1 — вправо, -1 — влево, 0 — не менять.
func animate(delta: float, speed_ratio: float, face: float, in_air: bool) -> void:
	time += delta

	if face != 0.0 and face != facing and not turning:
		if use_turn_animation and not in_air:
			_start_turn(face)
		else:
			facing = face
			sprite.flip_h = facing < 0.0

	var target: StringName = &"idle"
	if in_air:
		target = &"jump"
	elif speed_ratio > 0.05:
		target = &"walk"

	if turning:
		sprite.speed_scale = 1.0
	else:
		if sprite.animation != target:
			sprite.play(target)
		if target == &"walk":
			sprite.speed_scale = maxf(0.4, speed_ratio) * walk_fps_at_full_speed
		else:
			sprite.speed_scale = 1.0

	# Приземление: короткое приседание.
	if was_in_air and not in_air:
		squash = squash_on_land
	was_in_air = in_air
	squash = move_toward(squash, 0.0, delta * 0.8)

	var breathe: float = 0.0
	if target == &"idle" and not turning:
		breathe = sin(time * 2.2) * breathe_amount
	scale = Vector2(base_scale.x * (1.0 + squash * 0.6), base_scale.y * (1.0 - squash + breathe))


func _start_turn(new_face: float) -> void:
	turning = true
	turn_to = new_face
	# Кадры разворота нарисованы для настоящего направления, поэтому без отзеркаливания.
	sprite.flip_h = false
	sprite.play(&"turn_left" if new_face < 0.0 else &"turn_right")


func _on_animation_finished() -> void:
	if not turning:
		return
	turning = false
	facing = turn_to
	sprite.flip_h = facing < 0.0
