extends "res://pose_editor/rig_base.gd"
## Поводок для игровой куклы FukiPuppet (растровые части, плащ и рукава на физике).

const SCALE := 0.85                           ## Кошка в редакторе крупнее, чем в игре
const TOE := Vector2(40.0, 24.0)              ## Носок относительно щиколотки, в точках листа


func make() -> Node2D:
	var p: FukiPuppet = load("res://scenes/fuki_puppet.tscn").instantiate()
	p.frame_scale = SCALE
	puppet = p
	return p


func neutral() -> Dictionary:
	return FukiPuppet.pose_neutral()


## Каждый кадр: в режиме правки кукла держит позу; во время показа ею управляет само движение.
func frame(delta: float, values: Dictionary, playing: bool) -> void:
	var p: FukiPuppet = puppet
	if not playing:
		p.pose_hold(true)
		p.pose_apply(values)
	p.animate(delta, 0.0, 1.0, false)


func _arm(j: int) -> Array:
	var sc = (puppet as FukiPuppet).sleeve_cloths[j]
	return [sc.elbow_pt as Vector2, (sc.cuff_rest - sc.elbow_pt) as Vector2]


## Места точек берутся с самой куклы, поэтому точка всегда сидит на суставе.
func handles() -> Dictionary:
	var p: FukiPuppet = puppet
	var h := {}
	h["pelvis"] = p.torso.global_position
	h["waist"] = p.chest.global_position
	h["neck"] = p.head.global_position
	h["head"] = p.head.global_transform * Vector2(0.0, -205.0)
	for j in 2:
		if j >= p.sleeve_cloths.size():
			continue
		var sl: Node2D = p.sleeves[j]
		var ec: Array = _arm(j)
		h["elbow_%d" % j] = sl.global_transform * ec[0]
		h["paw_%d" % j] = sl.global_transform * (ec[0] + (ec[1] as Vector2).rotated(p.sleeve_cloths[j].elbow_ang))
	for i in 2:
		h["foot_%d" % i] = p.feet[i].global_position
		h["toe_%d" % i] = p.feet[i].global_transform * TOE
	return h


func drag(v: Dictionary, id: String, m: Vector2) -> void:
	var p: FukiPuppet = puppet
	var flip_inv: Transform2D = p.flip.global_transform.affine_inverse()
	var mf: Vector2 = flip_inv * m                                   # мышь в координатах куклы: пол — y = 0
	match id:
		"pelvis":
			var d: Vector2 = mf - (FukiPuppet.HIP - Vector2(FukiPuppet.OX, FukiPuppet.OY))
			v["pose_pelvis"] = Vector2(clampf(d.x, -90.0, 90.0), clampf(d.y, -150.0, 125.0))
		"waist":
			var a: float = (mf - p.torso.position).angle() + PI * 0.5
			v["pose_torso"] = clampf(unwrap(v["pose_torso"], a), -0.7, 0.7)
		"neck":
			var q: Vector2 = p.torso.global_transform.affine_inverse() * m - FukiPuppet.WAIST
			var a2: float = q.angle() - (FukiPuppet.NECK - FukiPuppet.CH).angle()
			v["pose_chest"] = clampf(unwrap(v["pose_chest"], a2), -0.8, 0.8)
		"head":
			var q2: Vector2 = p.chest.global_transform.affine_inverse() * m - p.head.position
			v["pose_head"] = clampf(unwrap(v["pose_head"], q2.angle() + PI * 0.5), -0.9, 0.9)
		"elbow_0", "elbow_1":
			var j: int = int(id.right(1))
			var key: String = "pose_arm_l" if j == 0 else "pose_arm_r"
			var q3: Vector2 = p.chest.global_transform.affine_inverse() * m - p.sleeves[j].position
			v[key] = unwrap(v[key], q3.angle() - (_arm(j)[0] as Vector2).angle())
		"paw_0", "paw_1":
			var j2: int = int(id.right(1))
			var target: Vector2 = p.chest.global_transform.affine_inverse() * m - p.sleeves[j2].position
			var ec: Array = _arm(j2)
			place_paw(v, j2, ec[0], ec[1], target, elbow_side(ec[0], ec[1], float(v["pose_elbow_l" if j2 == 0 else "pose_elbow_r"])))
		"foot_0", "foot_1":
			var i: int = int(id.right(1))
			var fk: String = "pose_foot_l" if i == 0 else "pose_foot_r"
			var f: float = v[fk + "_rot"]
			var hip_x: float = (FukiPuppet.HIP_L.x if i == 0 else FukiPuppet.HIP_R.x) - FukiPuppet.OX
			var zero: Vector2 = p.pose_ankle(Vector2.ZERO, f)       # где щиколотка при нулевых величинах
			var up: float = clampf(zero.y - mf.y, 0.0, 120.0)
			if up < FOOT_SNAP:
				up = 0.0
			var px: float = (v["pose_pelvis"] as Vector2).x
			var x: float = clampf(mf.x - hip_x - zero.x, px - FukiPuppet.LEG_REACH * 0.9, px + FukiPuppet.LEG_REACH * 0.9)
			v[fk] = Vector2(x, up)
		"toe_0", "toe_1":
			var i2: int = int(id.right(1))
			var rk: String = "pose_foot_l_rot" if i2 == 0 else "pose_foot_r_rot"
			var fk2: String = "pose_foot_l" if i2 == 0 else "pose_foot_r"
			var hip_x2: float = (FukiPuppet.HIP_L.x if i2 == 0 else FukiPuppet.HIP_R.x) - FukiPuppet.OX
			# Угол считаем от щиколотки при ровной стопе: она не двигается, пока стопа перекатывается.
			var flat: Vector2 = Vector2(hip_x2 + (v[fk2] as Vector2).x, -FukiPuppet.FOOT_H - (v[fk2] as Vector2).y)
			var a3: float = (mf - flat).angle() - TOE.angle()
			v[rk] = clampf(unwrap(v[rk], a3), -0.5, 1.1)


func flip_elbow(v: Dictionary, j: int) -> void:
	var ec: Array = _arm(j)
	flip_arm(v, j, ec[0], ec[1])
