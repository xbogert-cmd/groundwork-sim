class_name TerrainSim
extends RefCounted
## Heightmap terrain + shallow water on the GPU (RenderingDevice compute).
## state texture (RGBA32F): r ground height, g water depth, b dirt mask, a unused.
## flux texture: r/g/b/a = water flow out of the cell towards +x / -x / +y(row) / -y(row), m^3/s.

const N := 192
const CELL := 0.25
const GROUPS := N / 8

var gravity := 9.81
var damp := 0.12
var repose_dry := deg_to_rad(38.0)
var repose_wet := deg_to_rad(24.0)
var slump_rate := 0.06
var slump_iters := 4
var rain := 0.0 ## m/s of water added everywhere
var open_east := true ## water that reaches the +x edge leaves the map
var outlet_drop := 0.2
var ground_floor := 0.0

var state_view := Texture2DRD.new()
var flux_view := Texture2DRD.new()
var ready_flag := false

var cpu_state := PackedFloat32Array() ## latest (slightly stale) async mirror of the state texture
var removed_m3 := 0.0 ## cumulative soil dug / dumped, from the GPU counters
var added_m3 := 0.0

var _rd: RenderingDevice
var _state: RID
var _tmp: RID
var _flux: RID
var _counters: RID
var _pipes := {}
var _shaders: Array[RID] = []
var _sets := {}
var _busy := false
var _last_removed := 0
var _last_added := 0
var _snap := PackedFloat32Array()
var _snap_counters := PackedInt32Array()


func setup(initial: PackedFloat32Array) -> void:
	cpu_state = initial.duplicate()
	RenderingServer.call_on_render_thread(_rt_setup.bind(initial))


func _img(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _make(shader_name: String, uniforms: Array[RDUniform]) -> void:
	var file: RDShaderFile = load("res://sim/%s.glsl" % shader_name)
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("%s: %s" % [shader_name, spirv.compile_error_compute])
		return
	var sh := _rd.shader_create_from_spirv(spirv)
	_shaders.append(sh)
	_pipes[shader_name] = _rd.compute_pipeline_create(sh)
	_sets[shader_name] = _rd.uniform_set_create(uniforms, sh, 0)


func _rt_setup(initial: PackedFloat32Array) -> void:
	_rd = RenderingServer.get_rendering_device()
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.width = N
	fmt.height = N
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
	var zeros := PackedByteArray()
	zeros.resize(N * N * 16)
	_state = _rd.texture_create(fmt, RDTextureView.new(), [initial.to_byte_array()])
	_tmp = _rd.texture_create(fmt, RDTextureView.new(), [zeros])
	_flux = _rd.texture_create(fmt, RDTextureView.new(), [zeros])
	var cz := PackedByteArray()
	cz.resize(16)
	_counters = _rd.storage_buffer_create(16, cz)

	var buf := RDUniform.new()
	buf.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf.binding = 1
	buf.add_id(_counters)
	_make("flux", [_img(0, _state), _img(1, _flux)])
	_make("water", [_img(0, _state), _img(1, _flux)])
	_make("slump", [_img(0, _state), _img(1, _tmp)])
	_make("tool", [_img(0, _state), buf])
	state_view.texture_rd_rid = _state
	flux_view.texture_rd_rid = _flux
	ready_flag = true


func release() -> void:
	RenderingServer.call_on_render_thread(_rt_release)


func _rt_release() -> void:
	ready_flag = false
	state_view.texture_rd_rid = RID()
	flux_view.texture_rd_rid = RID()
	for r in _sets.values() + _pipes.values() + _shaders + [_state, _tmp, _flux, _counters]:
		if r.is_valid():
			_rd.free_rid(r)


## tools: Array of {x, z (world metres), radius (m), amount (m at centre), mode ("dig"|"dump")}
func step(steps: int, dt: float, tools: Array = [], readback := false) -> void:
	RenderingServer.call_on_render_thread(_rt_step.bind(steps, dt, tools.duplicate(true), readback))


func _dispatch(shader_name: String, pc: PackedFloat32Array) -> void:
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipes[shader_name])
	_rd.compute_list_bind_uniform_set(cl, _sets[shader_name], 0)
	_rd.compute_list_set_push_constant(cl, pc.to_byte_array(), pc.size() * 4)
	_rd.compute_list_dispatch(cl, GROUPS, GROUPS, 1)
	_rd.compute_list_end()


func _rt_step(steps: int, dt: float, tools: Array, readback: bool) -> void:
	if not ready_flag:
		return
	for t in tools:
		_dispatch("tool", PackedFloat32Array([
			float(t.x) / CELL, float(t.z) / CELL, float(t.radius) / CELL, float(t.amount),
			ground_floor, CELL, float(N), 0.0 if t.mode == "dig" else 1.0]))
	for i in steps:
		_dispatch("flux", PackedFloat32Array([dt, gravity, CELL, damp, float(N), 1.0 if open_east else 0.0, outlet_drop, 0.0]))
		_dispatch("water", PackedFloat32Array([dt, CELL, float(N), rain]))
	if steps > 0 or not tools.is_empty():
		for i in slump_iters:
			_dispatch("slump", PackedFloat32Array([CELL, tan(repose_dry), tan(repose_wet), slump_rate, float(N), 0.0, 0.0, 0.0]))
			_rd.texture_copy(_tmp, _state, Vector3.ZERO, Vector3.ZERO, Vector3(N, N, 1), 0, 0, 0, 0)
	if readback and not _busy:
		_busy = true
		_rd.texture_get_data_async(_state, 0, _on_state)
		_rd.buffer_get_data_async(_counters, _on_counters)


func _on_state(data: PackedByteArray) -> void:
	cpu_state = data.to_float32_array()
	_busy = false


func _on_counters(data: PackedByteArray) -> void:
	var r := data.decode_u32(0)
	var a := data.decode_u32(4)
	removed_m3 += float((r - _last_removed) & 0xFFFFFFFF) / 1e7
	added_m3 += float((a - _last_added) & 0xFFFFFFFF) / 1e7
	_last_removed = r
	_last_added = a


## Blocking readback (tests): awaits until the render thread has produced the data.
func snapshot() -> PackedFloat32Array:
	_snap = PackedFloat32Array()
	RenderingServer.call_on_render_thread(_rt_snapshot)
	while _snap.is_empty():
		await Engine.get_main_loop().process_frame
	return _snap


## Exact cumulative [removed, added] soil volume in m^3 (blocking, tests).
func counters() -> Array:
	snapshot_counters_request()
	while _snap_counters.is_empty():
		await Engine.get_main_loop().process_frame
	return [float(_snap_counters[0] & 0xFFFFFFFF) / 1e7, float(_snap_counters[1] & 0xFFFFFFFF) / 1e7]


func snapshot_counters_request() -> void:
	_snap_counters = PackedInt32Array()
	RenderingServer.call_on_render_thread(_rt_counters)


func _rt_snapshot() -> void:
	_snap = _rd.texture_get_data(_state, 0).to_float32_array()


func _rt_counters() -> void:
	_snap_counters = _rd.buffer_get_data(_counters).to_int32_array()


# ---- CPU-side queries on the (stale) mirror, used for picking and the HUD ----

func _cell_at(i: int, j: int, ch: int) -> float:
	return cpu_state[(clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)) * 4 + ch]


func sample(x: float, z: float, ch: int) -> float:
	var fx := clampf(x / CELL, 0.0, N - 1.001)
	var fz := clampf(z / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(_cell_at(i, j, ch), _cell_at(i + 1, j, ch), tx),
		lerpf(_cell_at(i, j + 1, ch), _cell_at(i + 1, j + 1, ch), tx), tz)


func ground_at(x: float, z: float) -> float:
	return sample(x, z, 0)


func water_at(x: float, z: float) -> float:
	return sample(x, z, 1)


## Heights of ground + water, volumes in m^3 (works on any snapshot array).
static func ground_volume(s: PackedFloat32Array) -> float:
	var v := 0.0
	for k in range(0, s.size(), 4):
		v += s[k]
	return v * CELL * CELL


static func water_volume(s: PackedFloat32Array) -> float:
	var v := 0.0
	for k in range(0, s.size(), 4):
		v += s[k + 1]
	return v * CELL * CELL
