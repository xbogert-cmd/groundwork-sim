class_name TerrainGen
extends RefCounted
## Starting level: gentle slope towards the open +x edge, a swamp pond at (15, 24) held back by a ridge at x~26.

const POND := Vector2(15.0, 24.0)
const POND_R := 8.0
const POND_LEVEL := 1.75
const RIDGE_X := 26.0


static func make(seed_v := 7) -> PackedFloat32Array:
	var n := TerrainSim.N
	var cell := TerrainSim.CELL
	var a := PackedFloat32Array()
	a.resize(n * n * 4)
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.05
	var fine := FastNoiseLite.new()
	fine.seed = seed_v + 1
	fine.frequency = 0.25
	for j in n:
		for i in n:
			var x := i * cell
			var z := j * cell
			var d := Vector2(x, z).distance_to(POND) / POND_R
			var s := 1.0 - smoothstep(0.0, 1.0, d)
			var calm := smoothstep(0.6, 1.6, d) # keep the pond rim clean so it holds water
			var h := 3.3 - 0.06 * x + noise.get_noise_2d(x, z) * 0.3 * calm + fine.get_noise_2d(x, z) * 0.03
			h -= 1.4 * s
			h += 0.9 * exp(-pow((x - RIDGE_X) / 3.0, 2.0))
			var k := (j * n + i) * 4
			a[k] = h
			a[k + 2] = clampf(s * 1.5, 0.0, 0.8) # muddy bottom
	_fill_pond(a)
	return a


## Flood fill from the pond centre up to POND_LEVEL. Returns false if it reached the map edge (a leak).
static func _fill_pond(a: PackedFloat32Array) -> bool:
	var n := TerrainSim.N
	var seen := PackedByteArray()
	seen.resize(n * n)
	var start := Vector2i(int(POND.x / TerrainSim.CELL), int(POND.y / TerrainSim.CELL))
	var stack: Array[Vector2i] = [start]
	var tight := true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n or seen[c.y * n + c.x] == 1:
			continue
		var k := (c.y * n + c.x) * 4
		if a[k] >= POND_LEVEL:
			continue
		seen[c.y * n + c.x] = 1
		a[k + 1] = POND_LEVEL - a[k]
		if c.x == 0 or c.y == 0 or c.x == n - 1 or c.y == n - 1:
			tight = false
		stack.append_array([c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)])
	return tight
