class_name ParallaxOutside
extends Node2D
## Параллакс за окнами: вид на улицу собран из четырёх слоёв (небо, дальние дома, ближние дома, кусты и фонари).
## Чем слой дальше, тем медленнее он «едет» за камерой, поэтому при ходьбе по комнате улица в окнах
## сдвигается относительно рам — получается глубина.
##
## Слои — дочерние узлы Sky, Far, Mid, Near. Число рядом — «скорость слоя» относительно камеры:
## 1 — стоит как стена комнаты (без параллакса), меньше — дальше от зрителя (0.7 — ближе, 0.97 — почти неподвижное небо).

@export var enabled: bool = true                      ## Выключить — вернётся старая плоская картинка улицы
@export var sky_speed: float = 0.97
@export var far_speed: float = 0.90
@export var mid_speed: float = 0.82
@export var near_speed: float = 0.70
@export var vertical_amount: float = 0.0              ## Параллакс по вертикали (0 — выключен; камера по вертикали почти не двигается)

@onready var old_flat: Sprite2D = $OldFlat
@onready var sky: Sprite2D = $Sky
@onready var far: Sprite2D = $Far
@onready var mid: Sprite2D = $Mid
@onready var near: Sprite2D = $Near


func _process(_delta: float) -> void:
	old_flat.visible = not enabled
	for n in [sky, far, mid, near]:
		n.visible = enabled
	if not enabled:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return
	var view: Vector2 = get_viewport_rect().size / cam.zoom
	var center: Vector2 = cam.get_screen_center_position()
	var left: float = maxf(center.x - view.x * 0.5, 0.0)
	var top: float = center.y - view.y * 0.5
	sky.position = Vector2(left * (1.0 - sky_speed), top * vertical_amount * (1.0 - sky_speed))
	far.position = Vector2(left * (1.0 - far_speed), top * vertical_amount * (1.0 - far_speed))
	mid.position = Vector2(left * (1.0 - mid_speed), top * vertical_amount * (1.0 - mid_speed))
	near.position = Vector2(left * (1.0 - near_speed), top * vertical_amount * (1.0 - near_speed))
