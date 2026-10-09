class_name VecPuppet
extends Node2D

signal pose_finished                ## Движение из редактора поз доиграло до конца
## Векторная кукла целиком, вид 3/4 (лицом вправо). Проба: пока только стоит и сгибает суставы,
## ходьбы, бега и плаща на физике у неё нет — этим по-прежнему занимается FukiPuppet.
##
## Откуда берётся: source/fuki_34_v01.svg (файл по ТЗ для иллюстратора) → tools/svg_to_puppet.py →
## fuki_34_parts.tscn. В той сцене все части лежат рядом, каждая стоит на своей точке вращения.
## Здесь из них собирается кукла:
##   • «кости» — невидимые узлы, вложенные друг в друга (таз → корпус → шея → голова …);
##   • сами части остаются лежать рядом в порядке «что выше, то и перекрывает» (STACK),
##     а каждая кость тянет свои части за собой (RemoteTransform2D).
## Начало координат куклы — точка земли между стопами. Единицы — как на листе: рост 1500.
##
## Кукла понимает позы из редактора поз (pose_editor): те же величины pose_* и те же файлы
## движений, что у FukiPuppet. Включается флагом pose_enabled; см. раздел «позы» внизу.

const PARTS: PackedScene = preload("res://vector_puppet/fuki_34_parts.tscn")
const ARC_OVERLAP := 0.04      ## На сколько (в радианах) дуга шва в локте заходит под соседние куски

## Кости: имя, родитель, точка вращения. «@hips» — середина между тазобедренными суставами.
const BONES := [
	["pelvis", "", "@hips"],
	["torso", "pelvis", "pivot_waist"],
	["neck", "torso", "pivot_neck"],
	["head", "neck", "pivot_head"],
	["ear_near", "head", "pivot_ear_near"],
	["ear_far", "head", "pivot_ear_far"],
	["eye_near", "head", "pivot_eye_near"],
	["eye_far", "head", "pivot_eye_far"],
	["arm_near_upper", "torso", "pivot_shoulder_near"],
	["arm_near_fore", "arm_near_upper", "pivot_elbow_near"],
	["paw_near", "arm_near_fore", "pivot_wrist_near"],
	["arm_far_upper", "torso", "pivot_shoulder_far"],
	["arm_far_fore", "arm_far_upper", "pivot_elbow_far"],
	["paw_far", "arm_far_fore", "pivot_wrist_far"],
	["leg_near_thigh", "pelvis", "pivot_hip_near"],
	["leg_near_shin", "leg_near_thigh", "pivot_knee_near"],
	["foot_near", "leg_near_shin", "pivot_ankle_near"],
	["leg_far_thigh", "pelvis", "pivot_hip_far"],
	["leg_far_shin", "leg_far_thigh", "pivot_knee_far"],
	["foot_far", "leg_far_shin", "pivot_ankle_far"],
]

## Какая кость двигает часть, если имя части не совпадает с именем кости.
const PART_BONE := {
	"sleeve_near_upper": "arm_near_upper", "sleeve_near_fore": "arm_near_fore",
	"sleeve_far_upper": "arm_far_upper", "sleeve_far_fore": "arm_far_fore",
	"boot_near_shaft": "leg_near_shin", "boot_near_foot": "foot_near",
	"boot_far_shaft": "leg_far_shin", "boot_far_foot": "foot_far",
	"coat_body": "torso",
	"nose": "head", "mouth": "head", "whiskers_near": "head", "whiskers_far": "head",
	"eye_near_white": "head", "eye_far_white": "head",
	"eye_near_pupil": "eye_near", "eye_far_pupil": "eye_far",
	"eyelid_near__half": "head", "eyelid_near__closed": "head",
	"eyelid_far__half": "head", "eyelid_far__closed": "head",
}

## Порядок отрисовки снизу вверх. В файле одежда лежит отдельным слоем поверх тела,
## а в кукле слои перемешаны: ближняя рука с рукавом — поверх плаща, голова — поверх всего.
const STACK := [
	"arm_far_upper", "arm_far_fore", "paw_far", "sleeve_far_upper", "sleeve_far_fore",
	"leg_far_thigh", "leg_far_shin", "foot_far", "boot_far_shaft", "boot_far_foot",
	"ear_far", "torso", "neck",
	"leg_near_thigh", "leg_near_shin", "foot_near", "boot_near_shaft", "boot_near_foot",
	"coat_body",
	"arm_near_upper", "arm_near_fore", "paw_near", "sleeve_near_upper", "sleeve_near_fore",
	"head", "ear_near",
	"eye_far_white", "eye_far_pupil", "eyelid_far__half", "eyelid_far__closed",
	"eye_near_white", "eye_near_pupil", "eyelid_near__half", "eyelid_near__closed",
	"nose", "mouth", "whiskers_far", "whiskers_near",
]
## Ближняя рука: пока опущена, лежит под головой; поднятая выше этого угла — рисуется поверх головы.
const ARM_FRONT_DEG := 75.0

var parts: Node2D
var skeleton: Node2D
var bones: Dictionary = {}          ## имя кости → узел
var rest: Dictionary = {}           ## имя кости → место в стойке (от точки земли)
var part_nodes: Dictionary = {}     ## имя части → узел
var clothes_on: bool = true
var eyes_state: String = "open"
var bends: Array = []               ## швы рукавов в локтях: [{root, fore_bone, tangent, spans, meshes, angle}]
var near_arm: Array[Node2D] = []    ## части ближней руки с рукавом, снизу вверх
var near_arm_front: bool = false

# --- поза из редактора поз. Имена и смысл величин те же, что у FukiPuppet: один файл движения подходит обеим куклам.
const POSE_KEYS: Array[String] = [
	"pose_pelvis", "pose_torso", "pose_chest", "pose_head",
	"pose_arm_l", "pose_elbow_l", "pose_arm_r", "pose_elbow_r",
	"pose_foot_l", "pose_foot_l_rot", "pose_foot_r", "pose_foot_r_rot",
]
const POSE_DIR := "res://animations/fuki/"
const POSE_LEG := 178.0                     ## Длина ноги у FukiPuppet: в её единицах записаны сдвиги таза и стоп
const SIDES: Array[String] = ["near", "far"]
var pose_enabled: bool = false              ## true — кукла каждый кадр встаёт в позу из величин pose_*
var pose_pelvis: Vector2 = Vector2.ZERO     ## Таз: сдвиг (x — вперёд, y — вниз)
var pose_torso: float = 0.0                 ## Наклон всего корпуса от таза, радианы
var pose_chest: float = 0.0                 ## Наклон корпуса в талии
var pose_head: float = 0.0                  ## Наклон головы
var pose_arm_l: float = 0.0                 ## Ближняя рука: поворот в плече
var pose_elbow_l: float = 0.0               ## Ближняя рука: сгиб в локте
var pose_arm_r: float = 0.0                 ## Дальняя рука
var pose_elbow_r: float = 0.0
var pose_foot_l: Vector2 = Vector2.ZERO     ## Ближняя стопа: x — вперёд от своего места, y — высота над полом
var pose_foot_l_rot: float = 0.0            ## Наклон стопы (плюс — на носок, минус — на пятку)
var pose_foot_r: Vector2 = Vector2.ZERO     ## Дальняя стопа
var pose_foot_r_rot: float = 0.0
var pose_weight: float = 0.0                ## 0 — стойка, 1 — кукла целиком в позе
var pose_target: float = 0.0
var pose_in: float = 0.12
var pose_out: float = 0.25
var pose_player: AnimationPlayer
var pose_unit: float = 1.0                  ## Сколько единиц листа в одной единице позы
var legs_geo: Array = []                    ## По ноге: длины звеньев, углы в стойке, место щиколотки и носка


func _ready() -> void:
	parts = PARTS.instantiate()
	add_child(parts)
	VecMesh.smooth_tree(parts)                    # многоугольники → фигуры со сглаженным краем
	var pivots: Dictionary = {}
	for m in parts.get_node("pivots").get_children():
		pivots[String(m.name)] = (m as Node2D).position
	pivots["@hips"] = (pivots["pivot_hip_near"] + pivots["pivot_hip_far"]) * 0.5

	skeleton = Node2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for b in BONES:
		var bone := Node2D.new()
		bone.name = b[0]
		rest[b[0]] = pivots[b[2]]
		if b[1] == "":
			skeleton.add_child(bone)
			bone.position = rest[b[0]]
		else:
			bones[b[1]].add_child(bone)
			bone.position = rest[b[0]] - rest[b[1]]
		bones[b[0]] = bone

	var index := 0
	for part_name in STACK:
		var node: Node2D = parts.get_node_or_null(part_name)
		if node == null:
			continue
		part_nodes[part_name] = node
		parts.move_child(node, index)
		index += 1
		var bone_name: String = PART_BONE.get(part_name, part_name)
		_drive(bones[bone_name], rest[bone_name], node, node.position)
		if part_name.begins_with("sleeve_") and part_name.ends_with("_fore") and node.has_meta("bend_spans"):
			index = _build_bend(part_name, node, index)
	for part_name in ["arm_near_upper", "arm_near_fore", "paw_near", "sleeve_near_upper", "sleeve_near_fore", "bend_near"]:
		var n: Node2D = parts.get_node_or_null(part_name)
		if n:
			near_arm.append(n)
	for side in SIDES:                            # размеры ног для поз
		var hip: Vector2 = pivots["pivot_hip_" + side]
		var knee: Vector2 = pivots["pivot_knee_" + side]
		var ankle: Vector2 = pivots["pivot_ankle_" + side]
		var toe: Vector2 = pivots.get("pivot_toe_" + side, ankle + Vector2(55.0, -ankle.y))
		legs_geo.append({
			"hip_off": hip - rest["pelvis"], "v1": knee - hip, "v2": ankle - knee,
			"l1": (knee - hip).length(), "l2": (ankle - knee).length(),
			"ankle": ankle, "foot_h": -ankle.y, "toe_dx": toe.x - ankle.x, "heel_dx": -0.5 * (toe.x - ankle.x),
		})
	pose_unit = -(pivots["pivot_hip_near"].y + pivots["pivot_hip_far"].y) * 0.5 / POSE_LEG
	set_eyes("open")


## Кость тянет узел за собой: узел остаётся лежать среди частей, но повторяет движение кости.
func _drive(bone: Node2D, bone_rest: Vector2, node: Node2D, node_rest: Vector2) -> void:
	var rt := RemoteTransform2D.new()
	rt.name = "to_" + String(node.name)
	rt.position = node_rest - bone_rest
	bone.add_child(rt)
	rt.remote_path = rt.get_path_to(node)


## Шов вдоль рукава проходит через локоть: между половинками рукава при сгибе дорисовывается дуга.
func _build_bend(part_name: String, fore: Node2D, index: int) -> int:
	var side: String = "near" if "near" in part_name else "far"
	var upper_bone: Node2D = bones["arm_%s_upper" % side]
	var root := Node2D.new()
	root.name = "bend_" + side
	root.set_meta("layer", "clothes")
	parts.add_child(root)
	parts.move_child(root, index)                 # сразу над низом рукава
	_drive(upper_bone, rest["arm_%s_upper" % side], root, fore.position)
	var spans: PackedFloat32Array = fore.get_meta("bend_spans")
	var meshes: Array[MeshInstance2D] = []
	for i in spans.size() / 5:
		var mi := MeshInstance2D.new()
		mi.material = VecMesh.material()
		root.add_child(mi)
		meshes.append(mi)
	bends.append({"root": root, "fore_bone": bones["arm_%s_fore" % side], "tangent": fore.get_meta("bend_tangent"), "spans": spans, "meshes": meshes, "angle": INF})
	return index + 1


## Повернуть кость. Угол в градусах от стойки; плюс — по часовой стрелке на экране.
func set_deg(bone_name: String, deg: float) -> void:
	bones[bone_name].rotation = deg_to_rad(deg)


## Вернуть все кости в стойку.
func reset_pose() -> void:
	for b in BONES:
		var bone: Node2D = bones[b[0]]
		bone.rotation = 0.0
		bone.scale = Vector2.ONE
		bone.position = rest[b[0]] if b[1] == "" else rest[b[0]] - rest[b[1]]


## Одежда вкл/выкл (под ней кошка нарисована целиком).
func set_clothes(on: bool) -> void:
	clothes_on = on
	for node in parts.get_children():
		if String(node.get_meta("layer", "")).begins_with("clothes"):
			(node as Node2D).visible = on


## Веки: "open" — глаза открыты, "half" — прищур, "closed" — закрыты.
func set_eyes(state: String) -> void:
	eyes_state = state
	for side in ["near", "far"]:
		for s in ["half", "closed"]:
			var lid: Node2D = part_nodes.get("eyelid_%s__%s" % [side, s])
			if lid:
				lid.visible = s == state


## Сдвиг зрачков от середины глаза, в единицах листа (взгляд).
func look(offset: Vector2) -> void:
	for side in ["near", "far"]:
		var name_: String = "eye_" + side
		bones[name_].position = rest[name_] - rest["head"] + offset


## Ближняя рука поверх головы (true) или под ней (false).
func set_near_arm_front(front: bool) -> void:
	if front == near_arm_front:
		return
	near_arm_front = front
	if front:
		for n in near_arm:
			parts.move_child(n, parts.get_child_count() - 2)      # наверх; последним остаётся узел pivots
	else:
		for n in near_arm:
			parts.move_child(n, part_nodes["head"].get_index())    # сразу под голову, в том же порядке


func _process(delta: float) -> void:
	if pose_enabled:
		_apply_pose(delta)
	set_near_arm_front(absf(rad_to_deg(bones["arm_near_upper"].rotation)) > ARM_FRONT_DEG)
	for b in bends:
		_update_bend(b)


func _update_bend(b: Dictionary) -> void:
	var angle: float = (b["fore_bone"] as Node2D).rotation
	if is_equal_approx(angle, b["angle"]):
		return
	b["angle"] = angle
	var tangent: Vector2 = b["tangent"]
	var spans: PackedFloat32Array = b["spans"]
	var meshes: Array = b["meshes"]
	var dir: float = signf(angle)
	var steps: int = maxi(2, int(ceil(absf(angle) / 0.1)))
	var from: float = -ARC_OVERLAP * dir
	var to: float = angle + ARC_OVERLAP * dir
	for i in meshes.size():
		var mi: MeshInstance2D = meshes[i]
		if absf(angle) < 0.01:
			mi.visible = false
			continue
		var lo: float = spans[i * 5]
		var hi: float = spans[i * 5 + 1]
		if angle * (lo + hi) >= 0.0:              # с внутренней стороны сгиба половинки сходятся сами
			mi.visible = false
			continue
		var col := Color(spans[i * 5 + 2], spans[i * 5 + 3], spans[i * 5 + 4])
		var pts := PackedVector2Array()
		for k in steps + 1:
			pts.append((tangent * hi).rotated(lerpf(from, to, float(k) / steps)))
		if is_zero_approx(lo):
			pts.append(Vector2.ZERO)
		else:
			for k in steps + 1:
				pts.append((tangent * lo).rotated(lerpf(to, from, float(k) / steps)))
		if is_zero_approx(hi):
			pts = PackedVector2Array([Vector2.ZERO])
			for k in steps + 1:
				pts.append((tangent * lo).rotated(lerpf(from, to, float(k) / steps)))
		mi.mesh = VecMesh.build(pts, PackedInt32Array(), PackedInt32Array([pts.size()]), col)
		mi.visible = mi.mesh != null


# ------------------------------------------------------------------ позы из редактора поз

## Стойка: с неё начинается любое новое движение.
static func pose_neutral() -> Dictionary:
	return {
		"pose_pelvis": Vector2.ZERO, "pose_torso": 0.0, "pose_chest": 0.0, "pose_head": 0.0,
		"pose_arm_l": 0.0, "pose_elbow_l": 0.0, "pose_arm_r": 0.0, "pose_elbow_r": 0.0,
		"pose_foot_l": Vector2.ZERO, "pose_foot_l_rot": 0.0, "pose_foot_r": Vector2.ZERO, "pose_foot_r_rot": 0.0,
	}


func pose_values() -> Dictionary:
	var d := {}
	for key in POSE_KEYS:
		d[key] = get(key)
	return d


func pose_apply(values: Dictionary) -> void:
	for key in POSE_KEYS:
		if values.has(key):
			set(key, values[key])


## Держать позу без перехода (так работает редактор поз). pose_hold(false) — сразу вернуть стойку.
func pose_hold(on: bool) -> void:
	if pose_player:
		pose_player.pause()
	pose_target = 1.0 if on else 0.0
	pose_weight = pose_target


## Проиграть движение: кукла плавно входит в него, а после конца сама возвращается в стойку.
func pose_play(anim: Animation, blend_in: float = 0.12, blend_out: float = 0.25) -> void:
	if anim == null:
		return
	pose_enabled = true
	if pose_player == null:
		pose_player = AnimationPlayer.new()
		pose_player.name = "PosePlayer"
		add_child(pose_player)
		pose_player.add_animation_library("", AnimationLibrary.new())
		pose_player.animation_finished.connect(_on_pose_anim_finished)
	var lib: AnimationLibrary = pose_player.get_animation_library("")
	pose_player.stop()
	if lib.has_animation("pose"):
		lib.remove_animation("pose")
	lib.add_animation("pose", anim)
	pose_in = blend_in
	pose_out = blend_out
	pose_target = 1.0
	pose_player.play("pose")
	pose_player.advance(0.0)


## Проиграть движение по имени файла из папки animations/fuki (без «.tres»).
func play_pose(anim_name: String) -> bool:
	var path: String = POSE_DIR + anim_name + ".tres"
	if not ResourceLoader.exists(path):
		return false
	var anim: Animation = load(path) as Animation
	if anim == null:
		return false
	pose_play(anim)
	return true


func pose_stop() -> void:
	if pose_player:
		pose_player.pause()
	pose_target = 0.0


func _on_pose_anim_finished(_anim_name: StringName) -> void:
	pose_target = 0.0
	pose_finished.emit()


## Где окажется щиколотка ноги i (0 — ближняя, 1 — дальняя) в координатах куклы.
## Стопа перекатывается: на носок — вокруг носка, на пятку — вокруг пятки.
func pose_ankle(i: int, foot: Vector2, f: float) -> Vector2:
	var g: Dictionary = legs_geo[i]
	var xc: float = g["heel_dx"] * clampf(-f / 0.25, 0.0, 1.0) + g["toe_dx"] * clampf(f / 0.5, 0.0, 1.0)
	var rx: float = xc * cos(f) - g["foot_h"] * sin(f)
	var ry: float = xc * sin(f) + g["foot_h"] * cos(f)
	return Vector2(g["ankle"].x + foot.x * pose_unit + xc - rx, -ry - maxf(foot.y, 0.0) * pose_unit)


## Ставит кости по величинам pose_*. Ноги — обратной кинематикой: стопы главнее таза,
## если нога не достаёт до своей точки, таз опускается.
func _apply_pose(delta: float) -> void:
	if pose_weight != pose_target:
		var blend_time: float = pose_in if pose_target > pose_weight else pose_out
		pose_weight = move_toward(pose_weight, pose_target, delta / maxf(blend_time, 0.001))
	var w: float = smoothstep(0.0, 1.0, pose_weight)
	var k: float = pose_unit
	var body_rot: float = pose_torso * w
	var px: float = pose_pelvis.x * k * w
	var ty: float = pose_pelvis.y * k * w
	var feet: Array[Vector2] = [pose_foot_l * w, pose_foot_r * w]
	var rots: Array[float] = [pose_foot_l_rot * w, pose_foot_r_rot * w]
	var targets: Array[Vector2] = []
	for i in 2:
		var g: Dictionary = legs_geo[i]
		var a: Vector2 = pose_ankle(i, feet[i], rots[i])
		targets.append(a)
		var reach: float = g["l1"] + g["l2"] - 0.05
		var hip0: Vector2 = rest["pelvis"] + Vector2(px, 0.0) + (g["hip_off"] as Vector2).rotated(body_rot)
		var dx: float = clampf(a.x - hip0.x, -reach * 0.96, reach * 0.96)
		ty = maxf(ty, a.y - sqrt(reach * reach - dx * dx) - hip0.y)
	ty = minf(ty, 125.0 * k)
	var pelvis: Node2D = bones["pelvis"]
	pelvis.position = rest["pelvis"] + Vector2(px, ty)
	pelvis.rotation = body_rot
	bones["torso"].rotation = pose_chest * w
	bones["head"].rotation = pose_head * w
	bones["arm_near_upper"].rotation = pose_arm_l * w
	bones["arm_near_fore"].rotation = pose_elbow_l * w
	bones["arm_far_upper"].rotation = pose_arm_r * w
	bones["arm_far_fore"].rotation = pose_elbow_r * w
	for i in 2:
		var g: Dictionary = legs_geo[i]
		var side: String = SIDES[i]
		var hip: Vector2 = pelvis.position + (g["hip_off"] as Vector2).rotated(body_rot)
		var t: Vector2 = targets[i] - hip
		var l1: float = g["l1"]
		var l2: float = g["l2"]
		var d: float = clampf(t.length(), absf(l1 - l2) + 1.0, l1 + l2 - 0.01)
		var base: float = t.angle()
		var alpha: float = acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
		var upper: float = base - alpha                      # колено смотрит вперёд
		var knee: Vector2 = Vector2.from_angle(upper) * l1
		var lower: float = (Vector2.from_angle(base) * d - knee).angle()
		var th: float = upper - (g["v1"] as Vector2).angle()   # поворот бедра и голени в координатах куклы
		var sh: float = lower - (g["v2"] as Vector2).angle()
		bones["leg_%s_thigh" % side].rotation = th - body_rot
		bones["leg_%s_shin" % side].rotation = sh - th
		bones["foot_%s" % side].rotation = rots[i] - sh
