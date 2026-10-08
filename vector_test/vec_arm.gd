class_name VecArm
extends Node2D
## Пробная векторная рука. Части приходят из SVG (tools/svg_to_puppet.py делает из него
## сцену arm_parts.tscn), здесь они собираются в цепочку: плечо → локоть → запястье.
## Начало координат руки — плечевой сустав. Рука нарисована опущенной вниз.

const PARTS: PackedScene = preload("res://vector_test/arm_parts.tscn")
const ARC_OVERLAP := 0.04      ## На сколько (в радианах) дуга-перемычка заходит под соседние куски

@export var show_sleeve: bool = true            ## Показывать рукав поверх руки

var upper: Node2D          # плечо (крутится в плечевом суставе)
var fore: Node2D           # предплечье (крутится в локте)
var paw: Node2D            # кисть (крутится в запястье)
var sleeve_upper: Node2D   # верх рукава, едет вместе с плечом
var sleeve_fore: Node2D    # низ рукава, едет вместе с предплечьем

# Детали рукава, которые проходят через локоть (шов): между их половинками при сгибе
# дорисовывается дуга, иначе шов рвётся.
var bend_root: Node2D
var bend_tangent: Vector2
var bend_spans: PackedFloat32Array
var bend_meshes: Array[MeshInstance2D] = []
var bend_angle: float = INF


func _ready() -> void:
	var parts: Node2D = PARTS.instantiate()
	add_child(parts)
	VecMesh.smooth_tree(parts)                   # многоугольники → фигуры со сглаженным краем
	upper = parts.get_node("arm_near_upper")
	fore = parts.get_node("arm_near_fore")
	paw = parts.get_node("paw_near")
	sleeve_upper = parts.get_node_or_null("sleeve_near_upper")
	sleeve_fore = parts.get_node_or_null("sleeve_near_fore")
	# Места суставов на листе. Каждая часть уже стоит на своей оси.
	var shoulder: Vector2 = upper.position
	var elbow: Vector2 = fore.position
	var wrist: Vector2 = paw.position
	parts.position = -shoulder                   # плечо попадает в начало координат руки
	_attach(fore, upper, elbow - shoulder)
	_attach(paw, fore, wrist - elbow)
	if sleeve_upper and sleeve_fore:
		_attach(sleeve_fore, sleeve_upper, elbow - shoulder)
		_build_bend(elbow - shoulder)
	set_sleeve(show_sleeve)
	set_pose(0.0, 0.0, 0.0)


## Перевешивает часть на родителя, сохраняя её место.
func _attach(child: Node2D, parent: Node2D, offset: Vector2) -> void:
	child.get_parent().remove_child(child)
	parent.add_child(child)
	child.position = offset


func _build_bend(elbow_offset: Vector2) -> void:
	if not sleeve_fore.has_meta("bend_spans"):
		return
	bend_tangent = sleeve_fore.get_meta("bend_tangent")
	bend_spans = sleeve_fore.get_meta("bend_spans")
	bend_root = Node2D.new()
	bend_root.name = "Bend"
	bend_root.position = elbow_offset
	sleeve_upper.add_child(bend_root)            # после низа рукава, то есть поверх него
	for i in bend_spans.size() / 5:
		var mi := MeshInstance2D.new()
		mi.material = VecMesh.material()
		bend_root.add_child(mi)
		bend_meshes.append(mi)


func set_sleeve(on: bool) -> void:
	show_sleeve = on
	if sleeve_upper:
		sleeve_upper.visible = on


## Поза в градусах: рука вперёд-назад в плече, сгиб локтя (0 — прямая), кисть.
## «Вперёд» — в ту сторону, куда смотрит кошка (вправо).
func set_pose(shoulder_deg: float, elbow_deg: float, wrist_deg: float) -> void:
	upper.rotation = -deg_to_rad(shoulder_deg)
	fore.rotation = -deg_to_rad(elbow_deg)
	paw.rotation = -deg_to_rad(wrist_deg)
	if sleeve_upper and sleeve_fore:
		sleeve_upper.rotation = upper.rotation
		sleeve_fore.rotation = fore.rotation
		_update_bend(fore.rotation)


## Дуги между половинками деталей рукава: от линии сгиба до той же линии, повёрнутой на угол локтя.
func _update_bend(angle: float) -> void:
	if bend_meshes.is_empty() or is_equal_approx(angle, bend_angle):
		return
	bend_angle = angle
	var dir: float = signf(angle)
	var steps: int = maxi(2, int(ceil(absf(angle) / 0.1)))
	var from: float = -ARC_OVERLAP * dir
	var to: float = angle + ARC_OVERLAP * dir
	for i in bend_meshes.size():
		var mi: MeshInstance2D = bend_meshes[i]
		if absf(angle) < 0.01:
			mi.visible = false
			continue
		var lo: float = bend_spans[i * 5]
		var hi: float = bend_spans[i * 5 + 1]
		# Разрыв открывается только с наружной стороны сгиба. С внутренней половинки
		# находят друг на друга, там дуга не нужна.
		if angle * (lo + hi) >= 0.0:
			mi.visible = false
			continue
		var col := Color(bend_spans[i * 5 + 2], bend_spans[i * 5 + 3], bend_spans[i * 5 + 4])
		var pts := PackedVector2Array()
		for k in steps + 1:                          # дальняя от оси дуга
			pts.append((bend_tangent * hi).rotated(lerpf(from, to, float(k) / steps)))
		if is_zero_approx(lo):
			pts.append(Vector2.ZERO)                 # клин от самой оси
		else:
			for k in steps + 1:                      # ближняя дуга, в обратную сторону
				pts.append((bend_tangent * lo).rotated(lerpf(to, from, float(k) / steps)))
		if is_zero_approx(hi):                       # клин с другой стороны оси
			pts = PackedVector2Array([Vector2.ZERO])
			for k in steps + 1:
				pts.append((bend_tangent * lo).rotated(lerpf(from, to, float(k) / steps)))
		mi.mesh = VecMesh.build(pts, PackedInt32Array(), PackedInt32Array([pts.size()]), col)
		mi.visible = mi.mesh != null
