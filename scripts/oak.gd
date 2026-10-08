extends Node2D
## Дуб на переднем плане: ствол стоит, крона качается на ветру (кнопка 6) и чуть дышит без ветра.
## Узел стоит в точке, где ствол касается земли.

@export var sway_deg: float = 4.0        ## Наклон кроны от сильного порыва
@export var crown_tint: Color = Color(0.82, 0.88, 0.92)   ## Затемнение, чтобы дерево сидело в ночи

var pivot: Node2D
var mat: ShaderMaterial
var t: float = 0.0


func _ready() -> void:
	var trunk := Sprite2D.new()
	trunk.texture = load("res://assets/oak/trunk.png")
	trunk.centered = false
	trunk.position = Vector2(-95.0, -430.0)
	trunk.modulate = crown_tint
	add_child(trunk)
	pivot = Node2D.new()
	pivot.position = Vector2(0.0, -360.0)       # там, где ствол входит в крону
	add_child(pivot)
	var crown := Sprite2D.new()
	crown.texture = load("res://assets/oak/crown.png")
	crown.centered = false
	crown.position = Vector2(-380.0, -410.0)
	crown.modulate = crown_tint
	mat = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/oak_leaves.gdshader")
	crown.material = mat
	pivot.add_child(crown)


func _process(delta: float) -> void:
	t += delta
	var g: float = Wind.gust * Wind.dir
	pivot.rotation = deg_to_rad(sway_deg * g * (1.0 + 0.2 * sin(t * 4.0)) + 0.35 * sin(t * 0.8))
	mat.set_shader_parameter("wind", g)
