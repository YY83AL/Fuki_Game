extends "res://pose_editor/rig_base.gd"
## Поводок для векторной куклы VecPuppet (проба: вид 3/4, без физики плаща).

const SCALE := 0.38                           ## Кукла ростом 1500 единиц → 570 точек экрана


func make() -> Node2D:
	var p := VecPuppet.new()
	p.scale = Vector2(SCALE, SCALE)
	p.pose_enabled = true
	puppet = p
	return p


func neutral() -> Dictionary:
	return VecPuppet.pose_neutral()


func frame(_delta: float, values: Dictionary, playing: bool) -> void:
	var p: VecPuppet = puppet
	if not playing:
		p.pose_hold(true)
		p.pose_apply(values)             # сама кукла встанет в позу в своём _process


func _arm(j: int) -> Array:
	var p: VecPuppet = puppet
	var s: String = VecPuppet.SIDES[j]
	var sh: Vector2 = p.rest["arm_%s_upper" % s]
	var el: Vector2 = p.rest["arm_%s_fore" % s]
	var wr: Vector2 = p.rest["paw_%s" % s]
	return [el - sh, wr - el]


func handles() -> Dictionary:
	var p: VecPuppet = puppet
	var h := {}
	h["pelvis"] = (p.bones["pelvis"] as Node2D).global_position
	h["waist"] = (p.bones["torso"] as Node2D).global_position
	h["neck"] = (p.bones["neck"] as Node2D).global_position
	h["head"] = (p.bones["head"] as Node2D).global_transform * Vector2(0.0, -330.0)
	for j in 2:
		var s: String = VecPuppet.SIDES[j]
		h["elbow_%d" % j] = (p.bones["arm_%s_fore" % s] as Node2D).global_position
		h["paw_%d" % j] = (p.bones["paw_%s" % s] as Node2D).global_position
		var foot: Node2D = p.bones["foot_%s" % s]
		var g: Dictionary = p.legs_geo[j]
		h["foot_%d" % j] = foot.global_position
		h["toe_%d" % j] = foot.global_transform * Vector2(g["toe_dx"], g["foot_h"])
	return h


func drag(v: Dictionary, id: String, m: Vector2) -> void:
	var p: VecPuppet = puppet
	var k: float = p.pose_unit
	var mf: Vector2 = p.global_transform.affine_inverse() * m          # мышь в координатах куклы: пол — y = 0
	var pelvis: Node2D = p.bones["pelvis"]
	var torso: Node2D = p.bones["torso"]
	match id:
		"pelvis":
			var d: Vector2 = (mf - p.rest["pelvis"]) / k
			v["pose_pelvis"] = Vector2(clampf(d.x, -90.0, 90.0), clampf(d.y, -150.0, 125.0))
		"waist":
			var a: float = (mf - pelvis.position).angle() - (p.rest["torso"] - p.rest["pelvis"]).angle()
			v["pose_torso"] = clampf(unwrap(v["pose_torso"], a), -0.7, 0.7)
		"neck":
			var q: Vector2 = pelvis.global_transform.affine_inverse() * m - torso.position
			var a2: float = q.angle() - (p.rest["neck"] - p.rest["torso"]).angle()
			v["pose_chest"] = clampf(unwrap(v["pose_chest"], a2), -0.8, 0.8)
		"head":
			var head: Node2D = p.bones["head"]
			var q2: Vector2 = (p.bones["neck"] as Node2D).global_transform.affine_inverse() * m - head.position
			v["pose_head"] = clampf(unwrap(v["pose_head"], q2.angle() + PI * 0.5), -0.9, 0.9)
		"elbow_0", "elbow_1":
			var j: int = int(id.right(1))
			var key: String = "pose_arm_l" if j == 0 else "pose_arm_r"
			var up: Node2D = p.bones["arm_%s_upper" % VecPuppet.SIDES[j]]
			var q3: Vector2 = torso.global_transform.affine_inverse() * m - up.position
			v[key] = unwrap(v[key], q3.angle() - (_arm(j)[0] as Vector2).angle())
		"paw_0", "paw_1":
			var j2: int = int(id.right(1))
			var up2: Node2D = p.bones["arm_%s_upper" % VecPuppet.SIDES[j2]]
			var target: Vector2 = torso.global_transform.affine_inverse() * m - up2.position
			var ec: Array = _arm(j2)
			place_paw(v, j2, ec[0], ec[1], target, elbow_side(ec[0], ec[1], float(v["pose_elbow_l" if j2 == 0 else "pose_elbow_r"])))
		"foot_0", "foot_1":
			var i: int = int(id.right(1))
			var fk: String = "pose_foot_l" if i == 0 else "pose_foot_r"
			var f: float = v[fk + "_rot"]
			var g: Dictionary = p.legs_geo[i]
			var zero: Vector2 = p.pose_ankle(i, Vector2.ZERO, f)        # где щиколотка при нулевых величинах
			var lift: float = clampf((zero.y - mf.y) / k, 0.0, 120.0)
			if lift < FOOT_SNAP:
				lift = 0.0
			var reach: float = (float(g["l1"]) + float(g["l2"])) * 0.9 / k
			var hip_x: float = (p.rest["pelvis"].x + (g["hip_off"] as Vector2).x - (g["ankle"] as Vector2).x) / k + (v["pose_pelvis"] as Vector2).x
			var x: float = clampf((mf.x - zero.x) / k, hip_x - reach, hip_x + reach)
			v[fk] = Vector2(x, lift)
		"toe_0", "toe_1":
			var i2: int = int(id.right(1))
			var rk: String = "pose_foot_l_rot" if i2 == 0 else "pose_foot_r_rot"
			var fk2: String = "pose_foot_l" if i2 == 0 else "pose_foot_r"
			var g2: Dictionary = p.legs_geo[i2]
			var flat: Vector2 = Vector2((g2["ankle"] as Vector2).x + (v[fk2] as Vector2).x * k, -float(g2["foot_h"]) - (v[fk2] as Vector2).y * k)
			var a3: float = (mf - flat).angle() - Vector2(g2["toe_dx"], g2["foot_h"]).angle()
			v[rk] = clampf(unwrap(v[rk], a3), -0.5, 1.1)


func flip_elbow(v: Dictionary, j: int) -> void:
	var ec: Array = _arm(j)
	flip_arm(v, j, ec[0], ec[1])
