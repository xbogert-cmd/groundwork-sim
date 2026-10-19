extends Node3D
## Groundwork Sim prototype: dig a drainage channel, dump soil, watch the swamp drain.

const N := TerrainSim.N
const CELL := TerrainSim.CELL
const SIZE := (N - 1) * CELL
const SIM_DT := 0.01
const BUCKET_CAP := 1.4
const DIG_RATE := 1.1 ## m/s at the brush centre
const DUMP_RATE := 0.7
const DIG_RADIUS := 0.7
const DUMP_RADIUS := 1.0

var sim := TerrainSim.new()
var excavator: Excavator
var cam: Camera3D
var hud: Control
var sun: DirectionalLight3D

var cam_yaw := -PI * 0.5 - 0.35
var cam_pitch := 0.62
var cam_dist := 15.0
var cam_target := Vector3(18, 2, 24)

var aim := Vector3(22, 2, 24)
var aim_valid := false
var bucket_fill := 0.0
var sim_acc := 0.0
var frame := 0
var swamp_start := 1.0
var swamp_timer := 0.0
var rain_on := false

# input overrides, used by the scripted demo
var demo := false
var demo_dig := false
var demo_dump := false
var demo_aim := Vector3.ZERO
var dig_mult := 1.0

var _last_removed := 0.0
var _last_added := 0.0
var _ring: MeshInstance3D
var _dirt: GPUParticles3D
var _splash: GPUParticles3D
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _walls_mat: ShaderMaterial


func _ready() -> void:
	_build_world()
	sim.setup(TerrainGen.make())
	for m in [_terrain_mat, _water_mat, _walls_mat]:
		m.set_shader_parameter("state_tex", sim.state_view)
	_water_mat.set_shader_parameter("flux_tex", sim.flux_view)
	excavator.global_position = Vector3(23.5, 3.0, 29.0)
	excavator.rotation.y = -PI * 0.5
	if "--demo" in OS.get_cmdline_user_args():
		demo = true
		_demo.call_deferred()


# ---------------------------------------------------------------- world setup

func _grid_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(N * N)
	norms.resize(N * N)
	for j in N:
		for i in N:
			verts[j * N + i] = Vector3(i * CELL, 0.0, j * CELL)
			norms[j * N + i] = Vector3.UP
	idx.resize((N - 1) * (N - 1) * 6)
	var k := 0
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + N
			idx[k + 3] = a + 1
			idx[k + 4] = a + N + 1
			idx[k + 5] = a + N
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _wall_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var edges := [
		[Vector2(0, 0), Vector2(1, 0), Vector3(0, 0, -1)],
		[Vector2(0, SIZE), Vector2(1, 0), Vector3(0, 0, 1)],
		[Vector2(0, 0), Vector2(0, 1), Vector3(-1, 0, 0)],
		[Vector2(SIZE, 0), Vector2(0, 1), Vector3(1, 0, 0)],
	]
	for e in edges:
		var base := verts.size()
		for i in N:
			var p: Vector2 = e[0] + e[1] * (i * CELL)
			verts.append(Vector3(p.x, 0, p.y))
			verts.append(Vector3(p.x, 0, p.y))
			norms.append(e[2])
			norms.append(e[2])
			uvs.append(Vector2(i, 0))
			uvs.append(Vector2(i, 1))
		for i in N - 1:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _build_world() -> void:
	var aabb := AABB(Vector3(-1, -4, -1), Vector3(SIZE + 2, 12, SIZE + 2))
	_terrain_mat = _shader_mat("res://shaders/terrain.gdshader")
	var terrain := MeshInstance3D.new()
	terrain.mesh = _grid_mesh()
	terrain.material_override = _terrain_mat
	terrain.custom_aabb = aabb
	add_child(terrain)

	_water_mat = _shader_mat("res://shaders/water.gdshader")
	_water_mat.render_priority = 1
	var water := MeshInstance3D.new()
	water.mesh = _grid_mesh()
	water.material_override = _water_mat
	water.custom_aabb = aabb
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	_walls_mat = _shader_mat("res://shaders/walls.gdshader")
	var walls := MeshInstance3D.new()
	walls.mesh = _wall_mesh()
	walls.material_override = _walls_mat
	walls.custom_aabb = aabb
	add_child(walls)

	# ground plane under the diorama for contact shadow / base
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE + 14, 0.5, SIZE + 14)
	base.mesh = bm
	base.position = Vector3(SIZE * 0.5, -2.3, SIZE * 0.5)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.2, 0.17, 0.14)
	base.material_override = base_mat
	add_child(base)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.55, 0.88)
	sky_mat.sky_horizon_color = Color(0.82, 0.88, 0.92)
	sky_mat.ground_horizon_color = Color(0.75, 0.80, 0.78)
	sky_mat.ground_bottom_color = Color(0.45, 0.50, 0.50)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.92)
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 400.0
	add_child(cam)

	excavator = Excavator.new()
	add_child(excavator)

	# aim ring
	_ring = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	_ring.mesh = q
	var rs := Shader.new()
	rs.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
uniform vec4 col : source_color = vec4(0.4, 1.0, 0.4, 1.0);
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.78, 0.84, d) * (1.0 - smoothstep(0.92, 0.98, d));
	float dot_ = 1.0 - smoothstep(0.04, 0.08, d);
	ALBEDO = col.rgb;
	ALPHA = (ring + dot_) * 0.9;
}"""
	var rm := ShaderMaterial.new()
	rm.shader = rs
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_dirt = _make_particles(Color(0.45, 0.3, 0.17), 60, 0.9, 0.09, 4.0, 3.0)
	_splash = _make_particles(Color(0.8, 0.93, 0.95), 50, 0.8, 0.06, 4.5, 5.0)

	var layer := CanvasLayer.new()
	hud = Control.new()
	hud.set_script(load("res://game/hud.gd"))
	layer.add_child(hud)
	add_child(layer)


func _make_particles(color: Color, amount: int, life: float, radius: float, speed: float, gravity: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -gravity * 3.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	return p


# ---------------------------------------------------------------- per frame

func _pick(mouse: Vector2) -> bool:
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	var t := 0.5
	var prev_t := 0.0
	while t < 160.0:
		var p := o + d * t
		if p.x >= 0 and p.z >= 0 and p.x <= SIZE and p.z <= SIZE and p.y < sim.ground_at(p.x, p.z):
			var lo := prev_t
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				var q := o + d * mid
				if q.y < sim.ground_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			aim = o + d * hi
			return true
		prev_t = t
		t += 0.25
	return false


func _process(dt: float) -> void:
	frame += 1
	dt = minf(dt, 0.05)
	_update_camera(dt)
	if not sim.ready_flag:
		return

	# --- input
	var want_dig := false
	var want_dump := false
	if demo:
		aim = demo_aim
		aim_valid = true
		want_dig = demo_dig
		want_dump = demo_dump
	else:
		aim_valid = _pick(get_viewport().get_mouse_position())
		want_dig = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		want_dump = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var drive := Input.get_axis(&"ui_down", &"ui_up") # arrow keys also work
		drive += float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
		var turn := float(Input.is_key_pressed(KEY_A)) - float(Input.is_key_pressed(KEY_D))
		turn += Input.get_axis(&"ui_right", &"ui_left")
		_drive(clampf(drive, -1, 1), clampf(turn, -1, 1), dt)

	# --- bucket accounting from the GPU counters
	bucket_fill = clampf(bucket_fill + (sim.removed_m3 - _last_removed) - (sim.added_m3 - _last_added), 0.0, BUCKET_CAP)
	_last_removed = sim.removed_m3
	_last_added = sim.added_m3

	# --- arm + tools
	var mode := 0
	if aim_valid:
		if want_dig and bucket_fill < BUCKET_CAP * 0.995:
			mode = 1
		elif want_dump and bucket_fill > 0.01:
			mode = 2
		var reach := excavator.update_arm(aim, mode, dt)
		_ring.visible = true
		_ring.global_position = aim + Vector3(0, 0.08, 0)
		var rad := DUMP_RADIUS if want_dump else DIG_RADIUS
		_ring.scale = Vector3(rad * 2.6, 1, rad * 2.6)
		(_ring.material_override as ShaderMaterial).set_shader_parameter("col", Color(0.4, 1.0, 0.4) if reach else Color(1.0, 0.35, 0.3))
		if not reach:
			mode = 0
	else:
		_ring.visible = false
		excavator.update_arm(excavator.global_position - excavator.global_basis.z * 4.0, 0, dt)

	var tools := []
	var active := false
	if mode == 1:
		tools.append({"x": aim.x, "z": aim.z, "radius": DIG_RADIUS, "amount": DIG_RATE * dig_mult * dt, "mode": "dig"})
		active = true
	elif mode == 2 and excavator.tip_world.distance_to(aim + Vector3(0, 1.2, 0)) < 1.0:
		tools.append({"x": aim.x, "z": aim.z, "radius": DUMP_RADIUS, "amount": DUMP_RATE * dt, "mode": "dump"})
		active = true
	var wet := aim_valid and sim.water_at(aim.x, aim.z) > 0.03
	_dirt.global_position = aim + Vector3(0, 0.2, 0)
	_dirt.emitting = active
	_splash.global_position = aim + Vector3(0, 0.1, 0)
	_splash.emitting = active and wet
	excavator.set_fill(bucket_fill / BUCKET_CAP)
	excavator.align_to_ground(sim)

	# --- simulation
	sim.rain = 0.004 if rain_on else 0.0
	sim_acc += dt
	var steps := mini(int(sim_acc / SIM_DT), 8)
	sim_acc = fmod(sim_acc, SIM_DT) if steps < 8 else 0.0
	sim.step(steps, SIM_DT, tools, frame % 4 == 0)

	# --- HUD
	swamp_timer += dt
	if swamp_timer > 0.4:
		swamp_timer = 0.0
		_update_swamp()
	hud.fill = bucket_fill / BUCKET_CAP
	hud.fill_m3 = bucket_fill
	hud.capacity = BUCKET_CAP
	hud.message = "Out of reach" if (aim_valid and not excavator.in_reach and (want_dig or want_dump)) else ""


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = clampf(cam_dist * 0.92, 6.0, 45.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clampf(cam_dist * 1.08, 6.0, 45.0)
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		cam_yaw -= e.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.006, 0.15, 1.35)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif e.keycode == KEY_U:
			rain_on = not rain_on


func _drive(fwd: float, turn: float, dt: float) -> void:
	excavator.rotation.y += turn * 1.1 * dt
	var f := -Vector3(excavator.global_basis.z.x, 0, excavator.global_basis.z.z).normalized()
	var p := excavator.global_position + f * fwd * 3.0 * dt
	p.x = clampf(p.x, 1.5, SIZE - 1.5)
	p.z = clampf(p.z, 1.5, SIZE - 1.5)
	excavator.global_position = p


func _update_camera(dt: float) -> void:
	var turn := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	cam_yaw += turn * 1.4 * dt
	var goal := excavator.global_position + Vector3(0, 1.5, 0)
	cam_target = cam_target.lerp(goal, 1.0 - exp(-4.0 * dt))
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	cam.global_position = cam_target + off
	cam.look_at(cam_target, Vector3.UP)


func _update_swamp() -> void:
	var s := sim.cpu_state
	if s.is_empty():
		return
	var v := 0.0
	var lim := TerrainGen.POND_R * 1.4
	for j in range(0, N, 2):
		for i in range(0, N, 2):
			var x := i * CELL
			var z := j * CELL
			if x < TerrainGen.RIDGE_X - 1.0 and Vector2(x, z).distance_to(TerrainGen.POND) < lim:
				v += s[(j * N + i) * 4 + 1]
	v *= CELL * CELL * 4.0
	if swamp_start < 0.0 or frame < 90:
		swamp_start = maxf(v, 0.001)
	hud.swamp = v / swamp_start
	hud.water_m3 = v


# ---------------------------------------------------------------- scripted demo

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://shots/")
	get_viewport().get_texture().get_image().save_png(dir + name + ".png")
	print("shot ", name)


func _teleport(p: Vector2, yaw: float) -> void:
	excavator.global_position = Vector3(p.x, sim.ground_at(p.x, p.y), p.y)
	excavator.rotation.y = yaw


func _demo_dig_to(spot: Vector2, depth: float, dump_at: Vector2) -> void:
	# dig at spot until the ground there is at depth (or timeout), dumping whenever the bucket is full
	var t0 := Time.get_ticks_msec()
	while sim.ground_at(spot.x, spot.y) > depth and Time.get_ticks_msec() - t0 < 12000:
		demo_aim = Vector3(spot.x, sim.ground_at(spot.x, spot.y), spot.y)
		demo_dump = false
		demo_dig = true
		await get_tree().process_frame
		if bucket_fill >= BUCKET_CAP * 0.97:
			demo_dig = false
			await _demo_dump(dump_at)


func _demo_dump(at: Vector2) -> void:
	demo_dig = false
	demo_aim = Vector3(at.x, sim.ground_at(at.x, at.y), at.y)
	await _wait(0.9)
	demo_dump = true
	var t0 := Time.get_ticks_msec()
	while bucket_fill > 0.03 and Time.get_ticks_msec() - t0 < 8000:
		demo_aim = Vector3(at.x, sim.ground_at(at.x, at.y), at.y)
		await get_tree().process_frame
	demo_dump = false
	await _wait(0.3)


func _demo() -> void:
	dig_mult = 2.5
	await _wait(2.5)
	cam_dist = 24.0
	cam_pitch = 0.75
	cam_yaw = -PI * 0.5 - 0.5
	await _wait(1.0)
	await _shot("01_start")
	cam_dist = 15.0
	cam_pitch = 0.6
	_teleport(Vector2(23.5, 29.0), -PI * 0.5)
	await _wait(1.5)
	var n_spots := 0
	for xi in 8:
		var x := 21.0 + xi * 0.8
		var depth := 1.15 - 0.03 * (x - 21.0)
		await _demo_dig_to(Vector2(x, 24.0), depth, Vector2(x, 27.0))
		n_spots += 1
		if xi == 3:
			demo_dig = false
			await _shot("02_digging")
	demo_dig = false
	await _wait(1.0)
	await _shot("03_trench_started")
	_teleport(Vector2(29.0, 29.0), -PI * 0.5)
	await _wait(1.0)
	for xi in 8:
		var x := 27.0 + xi * 0.8
		var depth := 1.0 - 0.03 * (x - 27.0)
		await _demo_dig_to(Vector2(x, 24.0), depth, Vector2(x, 27.5))
	demo_dig = false
	await _shot("04_trench_done")
	for t in 4:
		await _wait(8.0)
		await _shot("05_drain_%d" % t)
		print("swamp left %.0f%%" % (hud.swamp * 100.0))
	get_tree().quit()
