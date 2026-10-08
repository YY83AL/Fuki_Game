class_name VecMesh
extends RefCounted
## Превращает плоские многоугольники (Polygon2D из SVG) в фигуры со сглаженным краем.
## Godot в режиме Compatibility не умеет сглаживать края многоугольников сам,
## поэтому по краю каждой фигуры строится тонкая прозрачная кайма (см. vec_shape.gdshader).

const SHADER: Shader = preload("res://vector_test/vec_shape.gdshader")

static var _material: ShaderMaterial


## Общий материал для всех векторных фигур (один на игру).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## Включить или выключить сглаживание у всех фигур сразу.
static func set_smooth(on: bool) -> void:
	material().set_shader_parameter("feather", 1.0 if on else 0.0)


## Заменяет все Polygon2D внутри root на сглаженные фигуры. Возвращает, сколько заменено.
static func smooth_tree(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "Polygon2D", true, false):
		var poly: Polygon2D = node
		var pts: PackedVector2Array = poly.polygon
		if pts.size() < 3:
			continue
		var tris := PackedInt32Array()
		for t in poly.polygons:                       # готовые треугольники (фигуры с отверстиями)
			tris.append_array(t)
		var rings := PackedInt32Array([pts.size()])
		if poly.has_meta("rings"):
			rings = poly.get_meta("rings")
		var mesh := build(pts, tris, rings, poly.color)
		if mesh == null:
			continue                                   # не получилось — оставляем как есть
		var mi := MeshInstance2D.new()
		mi.name = poly.name
		mi.mesh = mesh
		mi.material = material()
		mi.position = poly.position
		mi.visible = poly.visible
		var parent := poly.get_parent()
		var index := poly.get_index()
		parent.remove_child(poly)
		poly.free()
		parent.add_child(mi)
		parent.move_child(mi, index)
		count += 1
	return count


## Строит фигуру с каймой. points — точки контура (сначала внешний контур, потом отверстия),
## rings — сколько точек в каждом контуре, tris — готовые треугольники или пусто.
static func build(points: PackedVector2Array, tris: PackedInt32Array, rings: PackedInt32Array, color: Color) -> ArrayMesh:
	var n := points.size()
	if tris.is_empty():
		tris = Geometry2D.triangulate_polygon(points)
		if tris.is_empty():
			return null
	# Направление «наружу» в каждой точке контура.
	var out_dir := PackedVector2Array()
	out_dir.resize(n)
	var start := 0
	for r in rings.size():
		var cnt: int = rings[r]
		var area := 0.0
		for i in cnt:
			var p := points[start + i]
			var q := points[start + (i + 1) % cnt]
			area += p.x * q.y - q.x * p.y
		var s := 1.0 if area > 0.0 else -1.0
		if r > 0:
			s = -s                                     # у отверстия «наружу» — это внутрь отверстия
		for i in cnt:
			var p0 := points[start + (i - 1 + cnt) % cnt]
			var p1 := points[start + i]
			var p2 := points[start + (i + 1) % cnt]
			var e0 := (p1 - p0).normalized()
			var e1 := (p2 - p1).normalized()
			var n0 := Vector2(e0.y, -e0.x) * s
			var n1 := Vector2(e1.y, -e1.x) * s
			var m := n0 + n1
			if m.length() < 0.001:
				m = n1
			m = m.normalized()
			out_dir[start + i] = m / maxf(m.dot(n1), 0.5)   # на углах кайма чуть длиннее, но не больше чем вдвое
		start += cnt

	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var solid := Color(color.r, color.g, color.b, 1.0)
	var clear := Color(color.r, color.g, color.b, 0.0)
	for i in n:                                        # непрозрачный ряд
		verts.append(points[i])
		uvs.append(out_dir[i])
		cols.append(solid)
	for i in n:                                        # прозрачный ряд (кайма)
		verts.append(points[i])
		uvs.append(out_dir[i])
		cols.append(clear)
	var idx := PackedInt32Array(tris)
	start = 0
	for r in rings.size():
		var cnt: int = rings[r]
		for i in cnt:
			var a := start + i
			var b := start + (i + 1) % cnt
			idx.append_array(PackedInt32Array([a, b, n + b, a, n + b, n + a]))
		start += cnt

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
