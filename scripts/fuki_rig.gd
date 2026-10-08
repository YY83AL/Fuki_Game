class_name FukiRig
extends Node2D
## Скелетная (cutout) анимация Фуки: голова, туловище, руки, ноги и хвост — отдельные
## части на «суставах» (узлы Node2D). Суставы поворачиваются кодом, получается бег,
## стойка и прыжок. Пробная версия: части вырезаны из готового рисунка.
##
## Все числа можно менять в Inspector, пока выбран узел FukiRig.

@export_group("Бег")
@export var cycle_speed: float = 12.0        ## Как быстро переставляет ноги при полной скорости (радиан в секунду)
@export var leg_swing_deg: float = 26.0      ## Размах ног, градусы
@export var arm_swing_deg: float = 28.0      ## Размах рук, градусы
@export var step_lift: float = 14.0          ## Насколько поднимается нога при шаге (пиксели рисунка)
@export var bounce: float = 9.0              ## Подпрыгивание корпуса при беге (пиксели рисунка)
@export var lean_deg: float = 4.0            ## Наклон корпуса вперёд при беге, градусы
@export var tail_wave_deg: float = 9.0       ## Размах хвоста при беге, градусы

@export_group("Стойка и прыжок")
@export var idle_front_leg_deg: float = 28.0 ## Насколько выпрямляется передняя нога, когда Фуки стоит
@export var jump_arm_deg: float = 45.0       ## Насколько руки взлетают вперёд при прыжке
@export var jump_leg_deg: float = 34.0       ## Размах ног в прыжке

@onready var tail: Node2D = $Tail
@onready var leg_back: Node2D = $LegBack
@onready var torso: Node2D = $Torso
@onready var arm_l: Node2D = $Torso/ArmL
@onready var arm_r: Node2D = $Torso/ArmR
@onready var head: Node2D = $Torso/Head
@onready var leg_front: Node2D = $LegFront

var rest: Dictionary = {}
var phi: float = 0.0
var run_blend: float = 0.0
var air_blend: float = 0.0
var idle_time: float = 0.0


func _ready() -> void:
	for n in [tail, leg_back, torso, leg_front]:
		rest[n] = n.position


## Вызывается из player.gd каждый кадр.
## speed_ratio: 0 — стоит, 1 — бежит на полной скорости.
## face: 1 — смотрит вправо, -1 — влево, 0 — не менять.
## in_air: Фуки в прыжке.
func animate(delta: float, speed_ratio: float, face: float, in_air: bool) -> void:
	if face != 0.0:
		scale.x = absf(scale.x) * face

	idle_time += delta
	run_blend = move_toward(run_blend, clampf(speed_ratio, 0.0, 1.0), delta * 8.0)
	air_blend = move_toward(air_blend, 1.0 if in_air else 0.0, delta * 10.0)
	if speed_ratio > 0.05:
		phi += delta * cycle_speed * speed_ratio

	var rb: float = run_blend
	var s: float = sin(phi)
	var c: float = cos(phi)
	var leg_a: float = deg_to_rad(leg_swing_deg)
	var arm_a: float = deg_to_rad(arm_swing_deg)

	# --- бег / стойка ---
	var bounce_y: float = -absf(c) * bounce * rb + sin(idle_time * 2.0) * 1.2 * (1.0 - rb)
	var torso_rot: float = deg_to_rad(lean_deg) * rb + sin(2.0 * phi) * deg_to_rad(1.5) * rb
	var head_rot: float = -deg_to_rad(lean_deg * 0.6) * rb + sin(2.0 * phi + 0.6) * deg_to_rad(2.5) * rb \
		+ sin(idle_time * 1.3) * deg_to_rad(1.5) * (1.0 - rb)
	var arm_l_rot: float = -arm_a * s * rb
	var arm_r_rot: float = arm_a * s * rb
	var leg_f_rot: float = -leg_a * s * rb + deg_to_rad(idle_front_leg_deg) * (1.0 - rb)
	var leg_b_rot: float = leg_a * s * rb
	var leg_f_dy: float = -maxf(0.0, c) * step_lift * rb
	var leg_b_dy: float = -maxf(0.0, -c) * step_lift * rb
	var tail_rot: float = -deg_to_rad(10.0) * rb + sin(phi + 1.2) * deg_to_rad(tail_wave_deg) * rb \
		+ sin(idle_time * 1.6) * deg_to_rad(7.0) * (1.0 - rb)

	# --- прыжок: поверх бега ---
	var a: float = air_blend
	torso_rot = lerpf(torso_rot, deg_to_rad(2.0), a)
	head_rot = lerpf(head_rot, deg_to_rad(-2.0), a)
	arm_l_rot = lerpf(arm_l_rot, -deg_to_rad(jump_arm_deg), a)
	arm_r_rot = lerpf(arm_r_rot, -deg_to_rad(jump_arm_deg * 0.8), a)
	leg_f_rot = lerpf(leg_f_rot, -deg_to_rad(jump_leg_deg), a)
	leg_b_rot = lerpf(leg_b_rot, deg_to_rad(jump_leg_deg * 0.9), a)
	leg_f_dy = lerpf(leg_f_dy, -6.0, a)
	leg_b_dy = lerpf(leg_b_dy, -10.0, a)
	tail_rot = lerpf(tail_rot, -deg_to_rad(25.0), a)
	bounce_y = lerpf(bounce_y, 0.0, a)

	torso.position = rest[torso] + Vector2(0.0, bounce_y)
	torso.rotation = torso_rot
	head.rotation = head_rot
	arm_l.rotation = arm_l_rot
	arm_r.rotation = arm_r_rot
	leg_front.position = rest[leg_front] + Vector2(0.0, leg_f_dy)
	leg_front.rotation = leg_f_rot
	leg_back.position = rest[leg_back] + Vector2(0.0, leg_b_dy)
	leg_back.rotation = leg_b_rot
	tail.position = rest[tail] + Vector2(0.0, bounce_y)
	tail.rotation = tail_rot
