extends Node
## Runs against the real GPU sim (needs a window; headless has no RenderingDevice).
## godot --path . res://tests/run_tests.tscn

const N := TerrainSim.N
const C := TerrainSim.CELL
var fails := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_water_settles()
	await _test_closed_ridge_holds()
	await _test_channel_drains()
	await _test_soil_slumps()
	await _test_dig_and_dump_accounting()
	await _test_real_level_is_stable()
	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func check(ok: bool, msg: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func blank(ground := 2.0) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(N * N * 4)
	for k in range(0, a.size(), 4):
		a[k] = ground
	return a


func new_sim(initial: PackedFloat32Array, open_east := false) -> TerrainSim:
	var s := TerrainSim.new()
	s.open_east = open_east
	s.setup(initial)
	while not s.ready_flag:
		await get_tree().process_frame
	return s


func run(s: TerrainSim, steps: int, dt := 0.01, tools: Array = []) -> PackedFloat32Array:
	var left := steps
	var first := true
	while left > 0: # batches keep each command buffer small
		var b := mini(left, 200)
		s.step(b, dt, tools if first else [])
		first = false
		left -= b
	return await s.snapshot()


func wet_surface_range(a: PackedFloat32Array) -> float:
	var lo := INF
	var hi := -INF
	for k in range(0, a.size(), 4):
		if a[k + 1] > 0.02:
			lo = minf(lo, a[k] + a[k + 1])
			hi = maxf(hi, a[k] + a[k + 1])
	return hi - lo


func _test_water_settles() -> void:
	print("water in a bowl settles flat and loses no volume")
	var a := blank(1.0)
	for j in range(80, 112):
		for i in range(80, 112):
			a[(j * N + i) * 4] = 0.2 # bowl in the middle
	for j in range(80, 90): # slug of water in one corner of the bowl
		for i in range(80, 90):
			a[(j * N + i) * 4 + 1] = 0.8
	var s := await new_sim(a)
	var v0 := TerrainSim.water_volume(a)
	var r := await run(s, 6000)
	var v1 := TerrainSim.water_volume(r)
	check(absf(v1 - v0) / v0 < 0.001, "volume conserved (%.3f -> %.3f m3)" % [v0, v1])
	check(wet_surface_range(r) < 0.03, "surface is level (spread %.4f m)" % wet_surface_range(r))
	var neg := false
	for k in range(1, r.size(), 4):
		if r[k] < 0.0 or is_nan(r[k]):
			neg = true
	check(not neg, "no negative / NaN depths")
	s.release()


func _ridge_world() -> PackedFloat32Array:
	# Pond (west) behind a ridge, downhill ground to the east.
	var a := blank()
	for j in N:
		for i in N:
			var x := i * C
			var h := 3.0 - 0.04 * x
			if x > 8.0 and x < 18.0 and j > 40 and j < 150:
				h -= 1.2
			if absf(x - 22.0) < 2.0:
				h += 1.0
			a[(j * N + i) * 4] = h
	for j in range(41, 149):
		for i in range(33, 71):
			var k := (j * N + i) * 4
			a[k + 1] = maxf(0.0, 2.0 - a[k])
	return a


func _pond_volume(a: PackedFloat32Array) -> float:
	var v := 0.0
	for j in N:
		for i in range(0, 80): # x < 20: the pond side of the ridge
			v += a[(j * N + i) * 4 + 1]
	return v * C * C


func _test_closed_ridge_holds() -> void:
	print("pond behind an intact ridge keeps its water")
	var a := _ridge_world()
	var s := await new_sim(a, true)
	var v0 := _pond_volume(a)
	var r := await run(s, 4000)
	var v1 := _pond_volume(r)
	check(absf(v1 - v0) / v0 < 0.005, "pond volume %.2f -> %.2f m3 after 40 s" % [v0, v1])
	s.release()


func _test_channel_drains() -> void:
	print("cutting a channel through the ridge drains the pond")
	var a := _ridge_world()
	for j in range(88, 96): # trench through the ridge, sloping gently downhill
		for i in range(70, N):
			var k := (j * N + i) * 4
			a[k] = minf(a[k], 1.1 - (i - 70) * 0.004)
	var s := await new_sim(a, true)
	var v0 := _pond_volume(a)
	var r := await run(s, 6000)
	var v1 := _pond_volume(r)
	check(v1 < v0 * 0.5, "pond fell from %.1f to %.1f m3 in 60 s" % [v0, v1])
	var out := TerrainSim.water_volume(r)
	check(out < TerrainSim.water_volume(a), "water left the map through the open edge")
	var neg := false
	for k in range(1, r.size(), 4):
		if r[k] < 0.0 or is_nan(r[k]):
			neg = true
	check(not neg, "no negative / NaN depths")
	s.release()


func _test_soil_slumps() -> void:
	print("a steep pile slumps to the angle of repose, soil volume conserved")
	var a := blank(1.0)
	for j in range(90, 102):
		for i in range(90, 102):
			a[(j * N + i) * 4] = 4.0 # 3 m tall pillar
	var s := await new_sim(a)
	var g0 := TerrainSim.ground_volume(a)
	for k in 300: # each step() call also runs the slump iterations, like one game frame
		s.step(1, 0.01)
	var r := await s.snapshot()
	var g1 := TerrainSim.ground_volume(r)
	check(absf(g1 - g0) / g0 < 1e-4, "ground volume %.3f -> %.3f" % [g0, g1])
	var max_slope := 0.0
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var h := r[(j * N + i) * 4]
			max_slope = maxf(max_slope, absf(h - r[(j * N + i + 1) * 4]) / C)
			max_slope = maxf(max_slope, absf(h - r[((j + 1) * N + i) * 4]) / C)
	check(max_slope < tan(deg_to_rad(38.0)) * 1.15, "steepest slope %.1f deg (limit 38)" % rad_to_deg(atan(max_slope)))
	check(r[(96 * N + 96) * 4] < 3.8, "pillar top came down from 4.0 (%.2f m)" % r[(96 * N + 96) * 4])
	s.release()


func _test_dig_and_dump_accounting() -> void:
	print("dig then dump: GPU counters match the change in ground volume")
	var a := blank(2.0)
	var s := await new_sim(a)
	var dig := [{"x": 24.0, "z": 24.0, "radius": 1.0, "amount": 0.5, "mode": "dig"}]
	var r := await run(s, 1, 0.01, dig)
	var c1: Array = await s.counters()
	var d1 := TerrainSim.ground_volume(r) - TerrainSim.ground_volume(a)
	check(absf(d1 + c1[0]) < 0.002 and c1[0] > 0.05, "dug %.4f m3, ground changed %.4f m3" % [c1[0], d1])
	var dump := [{"x": 30.0, "z": 24.0, "radius": 1.0, "amount": 0.3, "mode": "dump"}]
	r = await run(s, 1, 0.01, dump)
	var c2: Array = await s.counters()
	var d2 := TerrainSim.ground_volume(r) - TerrainSim.ground_volume(a)
	check(absf(d2 - (c2[1] - c2[0])) < 0.002 and c2[1] > 0.05, "net ground change %.4f = dumped %.4f - dug %.4f" % [d2, c2[1], c2[0]])
	s.release()


func _test_real_level_is_stable() -> void:
	print("the shipped level: swamp holds still, nothing blows up")
	var a := TerrainGen.make()
	var s := await new_sim(a, true)
	var v0 := TerrainSim.water_volume(a)
	var r := await run(s, 6000)
	var v1 := TerrainSim.water_volume(r)
	check(v0 > 20.0, "swamp starts with %.1f m3" % v0)
	check(absf(v1 - v0) / v0 < 0.01, "after 60 s: %.2f m3 (%.2f%% change)" % [v1, 100.0 * (v1 - v0) / v0])
	var bad := false
	for k in r.size():
		if is_nan(r[k]) or is_inf(r[k]):
			bad = true
	check(not bad, "no NaN / inf anywhere")
	s.release()
