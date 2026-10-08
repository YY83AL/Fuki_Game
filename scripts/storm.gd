extends Node2D
## Гроза: дождь за окнами (частицы Rain в сцене) и вспышки молний.
## Вспышка делает ярче улицу в окнах, капли дождя и слегка подсвечивает всю комнату.

@export var min_interval: float = 5.0            ## Минимальная пауза между молниями, секунды
@export var max_interval: float = 14.0           ## Максимальная пауза
@export var first_flash_delay: float = 3.0       ## Через сколько секунд после старта будет первая молния
@export var room_flash_strength: float = 0.22    ## Насколько светлеет вся комната при вспышке (0..1)
@export var window_flash_strength: float = 1.6   ## Насколько ярче становится улица в окнах
@export var street_color: Color = Color(0.68, 0.76, 0.95, 1.0)  ## Цвет улицы в обычное время (темнее и синее картинки)

signal flash_started   ## Молния сверкнула (по ней играет гром)

var flash: float = 0.0
var timer: float = 0.0

@onready var outside: Node2D = $"../Outside"
@onready var rain: Node2D = $"../Rain"
@onready var overlay: ColorRect = $"../Lightning/Flash"


func _ready() -> void:
	timer = first_flash_delay
	outside.modulate = street_color


func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		_strike()
		timer = randf_range(min_interval, max_interval)

	var b: float = 1.0 + flash * window_flash_strength
	outside.modulate = Color(street_color.r * b, street_color.g * b, street_color.b * b, 1.0)
	var r: float = 1.0 + flash
	rain.modulate = Color(r, r, r, 1.0)
	var c: Color = overlay.color
	c.a = flash * room_flash_strength
	overlay.color = c


func _strike() -> void:
	# Молния мигает: резкая вспышка, провал, вторая вспышка и плавное затухание.
	flash_started.emit()
	var tw: Tween = create_tween()
	tw.tween_property(self, "flash", 1.0, 0.04)
	tw.tween_property(self, "flash", 0.25, 0.07)
	tw.tween_property(self, "flash", 0.9, 0.04)
	if randf() < 0.4:
		tw.tween_property(self, "flash", 0.15, 0.08)
		tw.tween_property(self, "flash", 0.7, 0.05)
	tw.tween_property(self, "flash", 0.0, 0.6).set_ease(Tween.EASE_OUT)
