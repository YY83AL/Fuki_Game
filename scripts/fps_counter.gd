extends CanvasLayer
## Счётчик кадров в правом верхнем углу (автозагрузка FpsCounter).
## Работает всегда: на всех экранах, во время затемнений между сценами и на паузе.
## Цвет: зелёный — 55 кадров в секунду и больше, жёлтый — 30–54, красный — меньше 30.

const UPDATE_EVERY := 0.25      # как часто обновлять число, в секундах
const MARGIN_RIGHT := 12.0      # отступ от правого края экрана
const MARGIN_TOP := 52.0        # отступ сверху (ниже стрелки перехода между сценами)
const FONT_SIZE := 18

var label: Label
var timer := 0.0


func _ready() -> void:
	layer = 120      # поверх всего, даже поверх затемнения при переходе (слой 100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -MARGIN_RIGHT
	label.offset_right = -MARGIN_RIGHT
	label.offset_top = MARGIN_TOP
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	_refresh()


func _process(delta: float) -> void:
	timer += delta
	if timer >= UPDATE_EVERY:
		timer = 0.0
		_refresh()


func _refresh() -> void:
	var fps := int(round(Engine.get_frames_per_second()))
	label.text = "FPS %d" % fps
	var c := Color(0.45, 1.0, 0.45)
	if fps < 30:
		c = Color(1.0, 0.4, 0.35)
	elif fps < 55:
		c = Color(1.0, 0.9, 0.35)
	label.add_theme_color_override("font_color", c)
