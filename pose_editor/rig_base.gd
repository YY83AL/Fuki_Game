extends RefCounted
## «Поводок» редактора поз: связывает редактор с конкретной куклой.
## Здесь то, что одинаково для любой куклы; сама кукла — в rig_fuki.gd и rig_vec.gd.

const FOOT_SNAP := 6.0            ## Ближе этого к полу (в единицах позы) стопа «прилипает» к нему

var puppet: Node2D


static func unwrap(old: float, new_value: float) -> float:
	return old + wrapf(new_value - old, -PI, PI)


## Рука из двух звеньев: по месту лапы находит поворот плеча и сгиб локтя.
## e0 — плечо → локоть в стойке, c0 — локоть → запястье в стойке, target — где должна быть лапа (от плеча).
## side — в какую сторону смотрит локоть (-1 или 1). Возвращает [поворот плеча, сгиб локтя].
static func solve_two_bone(e0: Vector2, c0: Vector2, target: Vector2, side: float) -> Array:
	var l1: float = e0.length()
	var l2: float = c0.length()
	var d: float = clampf(target.length(), absf(l1 - l2) + 1.0, l1 + l2 - 0.5)
	var base: float = target.angle()
	var alpha: float = acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var upper: float = base - side * alpha                 # плечо отклоняется от линии «плечо — лапа» в сторону локтя
	var a: float = upper - e0.angle()
	var elbow: Vector2 = Vector2.from_angle(upper) * l1
	var b: float = wrapf((Vector2.from_angle(base) * d - elbow).angle() - c0.angle() - a, -PI, PI)
	return [a, b]


## В какую сторону сейчас согнут локоть: -1 или 1.
static func elbow_side(e0: Vector2, c0: Vector2, elbow_value: float) -> float:
	var bend: float = wrapf(elbow_value + c0.angle() - e0.angle(), -PI, PI)
	return -1.0 if bend <= 0.0 else 1.0


## Ставит лапу в точку target (от плеча, в координатах родителя руки) и записывает углы в позу.
func place_paw(v: Dictionary, j: int, e0: Vector2, c0: Vector2, target: Vector2, side: float) -> void:
	var ak: String = "pose_arm_l" if j == 0 else "pose_arm_r"
	var ek: String = "pose_elbow_l" if j == 0 else "pose_elbow_r"
	var r: Array = solve_two_bone(e0, c0, target, side)
	v[ak] = unwrap(v[ak], r[0])
	v[ek] = r[1]


## Согнуть локоть в другую сторону, не сдвигая лапу.
func flip_arm(v: Dictionary, j: int, e0: Vector2, c0: Vector2) -> void:
	var a: float = v["pose_arm_l" if j == 0 else "pose_arm_r"]
	var b: float = v["pose_elbow_l" if j == 0 else "pose_elbow_r"]
	var target: Vector2 = e0.rotated(a) + c0.rotated(a + b)       # где лапа сейчас
	place_paw(v, j, e0, c0, target, -elbow_side(e0, c0, b))
