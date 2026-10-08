extends CanvasLayer
## Эффекты кадра и мира (автозагрузка FX, работает на всех локациях).
## Кнопки сверху, свёрнуть/развернуть — кнопка «Эффекты». Клавиши: 1 свет, 2 тени, 3 свечение, Z тон, X виньетка, C зерно.
## Акварельного эффекта здесь нет — он будет добавлен отдельно.

const ROW_A := ["light", "shadows", "bloom", "grade", "vignette", "grain"]
const ROW_B := ["puddles", "beams", "moths", "haze", "dof", "paper"]
const ROW_C := ["storm", "shake", "aberr", "drops", "steam"]
const LABELS := {
	"light": "1 · Свет", "shadows": "2 · Тени", "bloom": "3 · Свечение",
	"grade": "Z · Тон", "vignette": "X · Виньетка", "grain": "C · Зерно",
	"puddles": "Лужи", "beams": "Лучи", "moths": "Мотыльки", "haze": "Дымка",
	"dof": "Глубина", "paper": "Бумага",
	"storm": "Молния", "shake": "Тряска", "aberr": "Аберрация", "drops": "Капли", "steam": "Пар",
}
const LAMP_COLOR := Color(1.0, 0.78, 0.50)
const LAMP_Y := 290.0
const LAMP_STEP := 640.0

var state := {      # при запуске всё выключено
	"light": false, "shadows": false, "bloom": false, "grade": false, "vignette": false, "grain": false,
	"puddles": false, "beams": false, "moths": false, "haze": false, "dof": false, "paper": false,
	"storm": false, "shake": false, "aberr": false, "drops": false, "steam": false,
}
var day_time := 0.5            # 0 закат … 0.5 вечер … 1 ночь
var buttons := {}
var panel_rows: Array[Control] = []
var rect: ColorRect
var mat: ShaderMaterial
var scene_ref: Node
var player: Node2D
var modulate_node: CanvasModulate
var lamps: Array[PointLight2D] = []
var lamp_pos: Array[Vector2] = []
var lamp_root: Node2D
var beams_root: Node2D
var moths: Node2D
var puddles: Node2D
var dust: CPUParticles2D
var steam: CPUParticles2D
var haze_layer: CanvasLayer
var haze_rects: Array[TextureRect] = []
var occluder: LightOccluder2D
var t := 0.0
var glow_tex: GradientTexture2D
var lamp_tex: GradientTexture2D     # широкий рассеянный свет фонариков
var flash := 0.0
var flash_queue: Array = []     # оставшиеся вспышки: [время до, сила]
var thunder_timer := -1.0
var storm_timer := 6.0
var thunder: AudioStreamPlayer
var shake_amp := 0.0
var aberr_pulse := 0.0
var was_air := false
var facing := 1.0
var steam_timer := 2.0
var lamp_k := 1.0       # множитель яркости фонариков (на светлых фонах меньше)
var clean := false      # белый лист: свечение отключено, иначе белое сливается


func _ready() -> void:
	layer = 9      # ниже меню (слой 10) и подсказок, чтобы кнопки не искажались
	process_mode = Node.PROCESS_MODE_ALWAYS
	glow_tex = _make_glow()
	lamp_tex = _make_glow(1.5, 0.6)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/post_fx.gdshader")
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)
	thunder = AudioStreamPlayer.new()
	thunder.stream = _make_thunder()
	thunder.volume_db = -6.0
	add_child(thunder)
	_build_ui()
	_apply_post()


func _make_glow(power: float = 2.2, peak: float = 1.0) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in 13:
		var u := float(i) / 12.0
		offs.append(u)
		cols.append(Color(1, 1, 1, peak * pow(1.0 - u, power)))
	g.offsets = offs
	g.colors = cols
	tex.gradient = g
	return tex


func _make_thunder() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 3
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	var y2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in n:
		var tt := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		y += (noise - y) * 0.06
		y2 += (y - y2) * 0.2
		var env := minf(tt / 0.04, 1.0) * exp(-tt * 1.15) * (0.65 + 0.35 * pow(sin(tt * 7.0), 2.0))
		var v := clampf(y2 * 5.0 * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 16
	add_child(ui)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.position.y = 56.0
	col.add_theme_constant_override("separation", 5)
	ui.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(head)
	var fold := Button.new()
	fold.text = "✦ Эффекты ▾"
	fold.toggle_mode = true
	fold.button_pressed = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.add_theme_font_size_override("font_size", 15)
	fold.toggled.connect(func(on: bool):
		fold.text = "✦ Эффекты ▾" if on else "✦ Эффекты ▸"
		for r in panel_rows:
			r.visible = on)
	head.add_child(fold)
	for names in [ROW_A, ROW_B, ROW_C]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		panel_rows.append(row)
		for n in names:
			var b := Button.new()
			b.text = LABELS[n]
			b.toggle_mode = true
			b.button_pressed = state[n]
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 15)
			_green_when_on(b)
			b.toggled.connect(_on_toggled.bind(n))
			row.add_child(b)
			buttons[n] = b
		if names == ROW_C:
			var lab := Label.new()
			lab.text = "  Закат"
			lab.add_theme_font_size_override("font_size", 15)
			lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			lab.add_theme_constant_override("outline_size", 5)
			row.add_child(lab)
			var sl := HSlider.new()
			sl.min_value = 0.0
			sl.max_value = 1.0
			sl.step = 0.01
			sl.value = day_time
			sl.custom_minimum_size = Vector2(130, 24)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sl.focus_mode = Control.FOCUS_NONE
			sl.value_changed.connect(func(v: float):
				day_time = v
				_apply_time())
			row.add_child(sl)
			var lab2 := Label.new()
			lab2.text = "Ночь"
			lab2.add_theme_font_size_override("font_size", 15)
			lab2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			lab2.add_theme_constant_override("outline_size", 5)
			row.add_child(lab2)


## Включённая кнопка — зелёный шрифт, выключенная — обычный.
func _green_when_on(b: Button) -> void:
	var green := Color(0.35, 1.0, 0.45)
	b.add_theme_color_override("font_pressed_color", green)
	b.add_theme_color_override("font_hover_pressed_color", green)
	b.add_theme_color_override("font_focus_color", green)


func _on_toggled(on: bool, n: String) -> void:
	state[n] = on
	_apply_post()
	_apply_world()
	if n == "storm" and on:
		storm_timer = 1.0


func _apply_post() -> void:
	for k in ["bloom", "grade", "vignette", "grain", "dof", "aberr", "drops", "paper"]:
		mat.set_shader_parameter(k, 1.0 if state[k] else 0.0)
	if clean:
		mat.set_shader_parameter("bloom", 0.0)


func _ambient() -> Color:
	var warm := Color(0.95, 0.76, 0.66)
	var eve := Color(0.58, 0.62, 0.76)
	var night := Color(0.28, 0.33, 0.56)
	return warm.lerp(eve, clampf(day_time * 2.0, 0.0, 1.0)).lerp(night, clampf(day_time * 2.0 - 1.0, 0.0, 1.0))


func _lamp_base() -> float:
	return lerpf(0.50, 1.15, day_time) * lamp_k


func _apply_time() -> void:
	if modulate_node:
		modulate_node.color = _ambient()


func _apply_world() -> void:
	var lit: bool = state["light"]
	if modulate_node:
		modulate_node.visible = lit
	if lamp_root:
		lamp_root.visible = lit
	for l in lamps:
		l.shadow_enabled = state["shadows"]
	if beams_root:
		beams_root.visible = state["beams"] and lit
		beams_root.modulate.a = 0.45 if lamp_k < 0.9 else 1.0
	if dust:
		dust.visible = state["beams"]
	if moths:
		moths.visible = state["moths"] and lit
		moths.set_process(moths.visible)
	if puddles:
		puddles.visible = state["puddles"]
	if haze_layer:
		haze_layer.visible = state["haze"]
	if steam:
		steam.visible = state["steam"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var n := ""
		match int(event.physical_keycode):
			KEY_1: n = "light"
			KEY_2: n = "shadows"
			KEY_3: n = "bloom"
			KEY_Z: n = "grade"
			KEY_X: n = "vignette"
			KEY_C: n = "grain"
		if n != "":
			buttons[n].button_pressed = not buttons[n].button_pressed


func _process(delta: float) -> void:
	t += delta
	var sc := get_tree().current_scene
	if sc != scene_ref:
		scene_ref = sc
		_build_world(sc)
	_update_lamps(delta)
	_update_storm(delta)
	_update_player_fx(delta)
	_update_haze()
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("aberr_pulse", aberr_pulse if state["aberr"] else 0.0)


func _update_lamps(delta: float) -> void:
	var base := _lamp_base()
	for i in lamps.size():
		var fl := 0.05 * sin(t * 5.0 + i * 1.7) + 0.03 * sin(t * 13.0 + i)
		lamps[i].energy = base + fl + flash * 0.35 * lamp_k
	if modulate_node:
		modulate_node.color = _ambient().lerp(Color(0.85, 0.9, 1.0), flash * 0.22)


func _update_storm(delta: float) -> void:
	# Вспышки: очередь [задержка, сила].
	var next_queue: Array = []
	var peak := 0.0
	for f in flash_queue:
		f[0] -= delta
		if f[0] <= 0.0:
			peak = maxf(peak, f[1])
		else:
			next_queue.append(f)
	flash_queue = next_queue
	if peak > 0.0:
		flash = maxf(flash, peak)
		aberr_pulse = maxf(aberr_pulse, 0.45)
		shake_amp = maxf(shake_amp, 5.0 * peak) if state["shake"] else shake_amp
	flash = move_toward(flash, 0.0, delta * 3.2)
	aberr_pulse = move_toward(aberr_pulse, 0.0, delta * 2.5)
	if state["storm"]:
		storm_timer -= delta
		if storm_timer <= 0.0:
			storm_timer = randf_range(7.0, 16.0)
			flash_queue = [[0.0, 1.0], [0.12, 0.45], [0.26, 0.8]]
			thunder_timer = randf_range(0.5, 1.6)
	if thunder_timer >= 0.0:
		thunder_timer -= delta
		if thunder_timer < 0.0:
			thunder.pitch_scale = randf_range(0.85, 1.1)
			thunder.play()
			if state["shake"]:
				shake_amp = maxf(shake_amp, 4.0)


func _update_player_fx(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Тряска камеры при приземлении и громе.
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	var air: float = float(player.get("air_height"))
	var in_air := air > 6.0
	if was_air and not in_air and state["shake"]:
		shake_amp = maxf(shake_amp, 3.0)
		aberr_pulse = maxf(aberr_pulse, 0.5)
	was_air = in_air
	shake_amp = move_toward(shake_amp, 0.0, delta * 14.0)
	if cam:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amp if shake_amp > 0.01 else Vector2.ZERO
	# Направление взгляда и пар изо рта.
	var vx: float = float(player.get("velocity").x)
	if absf(vx) > 20.0:
		facing = signf(vx)
	if steam and steam.visible:
		steam_timer -= delta
		steam.position = Vector2(facing * 44.0, -286.0)
		steam.direction = Vector2(facing, -0.5)
		if steam_timer <= 0.0:
			steam_timer = randf_range(2.2, 3.4)
			steam.restart()
			steam.emitting = true
	# Пыль в лучах следует за Фуки.
	if dust:
		dust.global_position = Vector2(player.global_position.x, 400.0)


func _update_haze() -> void:
	if haze_layer == null or not haze_layer.visible or player == null:
		return
	var px: float = player.global_position.x
	var speeds := [0.10, 0.22, 0.38]
	for i in haze_rects.size():
		var r := haze_rects[i]
		var w := r.size.x
		var off := fposmod(-px * speeds[i] + t * (6.0 + 5.0 * i), w / 2.0)
		r.position.x = -off


func _build_world(sc: Node) -> void:
	lamps.clear()
	lamp_pos.clear()
	modulate_node = null
	lamp_root = null
	beams_root = null
	moths = null
	puddles = null
	dust = null
	steam = null
	occluder = null
	player = null
	clean = false
	_apply_post()
	if haze_layer:
		haze_layer.queue_free()
		haze_layer = null
		haze_rects.clear()
	if sc == null:
		return
	var pl: Node2D = sc.get_node_or_null("Player")
	if pl == null:
		return
	player = pl
	clean = sc.has_meta("fx_clean")
	lamp_k = float(sc.get_meta("fx_lamp_k", 1.0))
	_apply_post()
	if clean:
		return      # белый лист: без света, луж и тумана, только эффекты кадра
	var width: float = float(pl.get("x_max")) + 90.0
	# Освещение.
	modulate_node = CanvasModulate.new()
	modulate_node.name = "FXAmbient"
	modulate_node.color = _ambient()
	sc.add_child(modulate_node)
	lamp_root = Node2D.new()
	lamp_root.name = "FXLamps"
	sc.add_child(lamp_root)
	var x := LAMP_STEP * 0.5
	while x < width:
		_add_lamp(Vector2(x, LAMP_Y))
		x += LAMP_STEP
	# Силуэт Фуки для теней.
	var body: Node2D = pl.get_node_or_null("Body")
	occluder = LightOccluder2D.new()
	occluder.name = "FXOccluder"
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-34, -4), Vector2(-52, -110), Vector2(-40, -200), Vector2(-26, -250),
		Vector2(-38, -300), Vector2(-30, -350), Vector2(0, -364), Vector2(30, -350),
		Vector2(38, -300), Vector2(26, -250), Vector2(40, -200), Vector2(52, -110), Vector2(34, -4)])
	occluder.occluder = poly
	(body if body else pl).add_child(occluder)
	# Лужи: на полу, под Фуки (не на локациях с метой fx_no_puddles).
	if not sc.has_meta("fx_no_puddles"):
		puddles = load("res://scripts/fx_puddles.gd").new()
		puddles.name = "FXPuddles"
		sc.add_child(puddles)
		sc.move_child(puddles, pl.get_index())
		puddles.setup(pl, width, float(pl.get("y_min")), float(pl.get("y_max")), lamp_pos, str(sc.scene_file_path))
	# Мотыльки.
	moths = load("res://scripts/fx_moths.gd").new()
	moths.name = "FXMoths"
	sc.add_child(moths)
	moths.setup(pl, lamp_pos)
	# Пыль в лучах.
	dust = CPUParticles2D.new()
	dust.name = "FXDust"
	dust.amount = 70
	dust.lifetime = 7.0
	dust.preprocess = 7.0
	dust.texture = glow_tex
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(760, 230)
	dust.direction = Vector2(0.4, -0.3)
	dust.spread = 180.0
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 12.0
	dust.scale_amount_min = 0.012
	dust.scale_amount_max = 0.03
	dust.color = Color(1.0, 0.9, 0.7, 0.55)
	dust.light_mask = 0
	var dm := CanvasItemMaterial.new()
	dm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	dust.material = dm
	sc.add_child(dust)
	# Пар изо рта.
	steam = CPUParticles2D.new()
	steam.name = "FXSteam"
	steam.amount = 14
	steam.lifetime = 1.3
	steam.one_shot = true
	steam.emitting = false
	steam.explosiveness = 0.0
	steam.texture = glow_tex
	steam.initial_velocity_min = 10.0
	steam.initial_velocity_max = 26.0
	steam.spread = 20.0
	steam.gravity = Vector2(0, -8)
	steam.scale_amount_min = 0.03
	steam.scale_amount_max = 0.07
	steam.color = Color(0.92, 0.95, 1.0, 0.38)
	steam.light_mask = 0
	steam.z_index = 4
	sc.add_child(steam)
	# Дымка слоями (экранные слои над миром, но под туманом).
	_build_haze()
	_apply_world()


func _build_haze() -> void:
	haze_layer = CanvasLayer.new()
	haze_layer.layer = 2
	add_child(haze_layer)
	var cfg := [
		{"y": 330.0, "h": 150.0, "a": 0.16, "seed": 1},
		{"y": 420.0, "h": 190.0, "a": 0.20, "seed": 2},
		{"y": 520.0, "h": 230.0, "a": 0.18, "seed": 3},
	]
	for c in cfg:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.0045
		noise.seed = c["seed"]
		var img: Image = noise.get_seamless_image(2560, int(c["h"]), false, false, 0.1)
		img.convert(Image.FORMAT_RGBA8)
		var hh: int = img.get_height()
		for yy in hh:
			var bell: float = pow(sin(PI * float(yy) / float(hh - 1)), 1.6)
			for xx in img.get_width():
				var v: float = img.get_pixel(xx, yy).r
				var al: float = clampf((v - 0.38) / 0.45, 0.0, 1.0) * c["a"] * bell
				img.set_pixel(xx, yy, Color(0.78, 0.85, 0.97, al))
		var nt := ImageTexture.create_from_image(img)
		var tr := TextureRect.new()
		tr.texture = nt
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(2560, c["h"])
		tr.position = Vector2(0, c["y"])
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		haze_layer.add_child(tr)
		haze_rects.append(tr)


func _add_lamp(pos: Vector2) -> void:
	lamp_pos.append(pos)
	var l := PointLight2D.new()
	l.position = pos
	l.texture = lamp_tex
	l.texture_scale = 5.2
	l.color = LAMP_COLOR
	l.energy = 1.0
	l.shadow_enabled = state["shadows"]
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 8.0
	l.shadow_color = Color(0, 0, 0, 0.45)
	lamp_root.add_child(l)
	lamps.append(l)
	var cord := Line2D.new()
	cord.points = PackedVector2Array([Vector2(pos.x, 0), Vector2(pos.x, pos.y - 8)])
	cord.width = 2.0
	cord.default_color = Color(0.1, 0.08, 0.08, 0.7)
	lamp_root.add_child(cord)
	var orb := Sprite2D.new()
	orb.texture = glow_tex
	orb.position = pos
	orb.scale = Vector2(0.06, 0.06)
	orb.modulate = Color(1.0, 0.9, 0.65, 0.75)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	orb.material = m
	orb.light_mask = 0
	lamp_root.add_child(orb)
	# Конус света: узкий луч вниз с мягким краем.
	if beams_root == null:
		beams_root = Node2D.new()
		beams_root.name = "FXBeams"
		lamp_root.get_parent().add_child(beams_root)
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(8, 0), pos + Vector2(260, 400), pos + Vector2(-260, 400)])
	beam.vertex_colors = PackedColorArray([Color(1, 0.85, 0.55, 0.09), Color(1, 0.85, 0.55, 0.09), Color(1, 0.85, 0.55, 0.0), Color(1, 0.85, 0.55, 0.0)])
	beam.light_mask = 0
	var bm := CanvasItemMaterial.new()
	bm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = bm
	beams_root.add_child(beam)
