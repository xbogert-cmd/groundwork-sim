class_name Excavator
extends Node3D
## Stylised excavator. Forward is -Z. The arm is a planar 2-bone IK towards the aimed ground point.

const BOOM := 3.6
const STICK := 2.7
const BUCKET := 1.0
const MIN_REACH := 2.0

var swing: Node3D
var boom: Node3D
var stick: Node3D
var bucket: Node3D
var soil: MeshInstance3D
var in_reach := false
var tip_world := Vector3.ZERO

var _tip_goal := Vector3.ZERO
var _phi := deg_to_rad(-60.0)
var _tilt := 0.0


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough := 0.55) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _ready() -> void:
	var yellow := Color(0.96, 0.70, 0.08)
	var dark_yellow := Color(0.80, 0.55, 0.06)
	var gray := Color(0.22, 0.23, 0.25)
	for sx in [-1.35, 1.35]:
		_box(self, Vector3(0.95, 0.8, 4.2), Vector3(sx, 0.4, 0), gray, 0.9)
		_box(self, Vector3(1.05, 0.25, 4.4), Vector3(sx, 0.12, 0), Color(0.12, 0.12, 0.13), 1.0)
	_box(self, Vector3(2.2, 0.4, 3.2), Vector3(0, 0.75, 0), Color(0.3, 0.3, 0.32))

	swing = Node3D.new()
	swing.position = Vector3(0, 0.95, 0)
	add_child(swing)
	_box(swing, Vector3(2.5, 1.0, 3.0), Vector3(0, 0.5, 0.1), yellow)
	_box(swing, Vector3(2.3, 0.9, 1.0), Vector3(0, 0.55, 1.7), dark_yellow) # counterweight
	_box(swing, Vector3(1.25, 1.25, 1.35), Vector3(-0.55, 1.5, -0.75), yellow) # cab
	_box(swing, Vector3(1.12, 0.75, 1.2), Vector3(-0.55, 1.55, -0.85), Color(0.35, 0.62, 0.78), 0.1) # glass
	_box(swing, Vector3(1.3, 0.1, 1.45), Vector3(-0.55, 2.15, -0.75), gray) # roof
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.12
	cyl.height = 0.8
	pipe.mesh = cyl
	pipe.position = Vector3(0.8, 1.3, 1.5)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = gray
	pipe.material_override = pm
	swing.add_child(pipe)

	boom = Node3D.new()
	boom.position = Vector3(0.45, 0.7, -1.55)
	swing.add_child(boom)
	_box(boom, Vector3(0.45, 0.55, BOOM), Vector3(0, 0, -BOOM * 0.5), yellow)
	stick = Node3D.new()
	stick.position = Vector3(0, 0, -BOOM)
	boom.add_child(stick)
	_box(stick, Vector3(0.32, 0.4, STICK), Vector3(0, 0, -STICK * 0.5), dark_yellow)
	bucket = Node3D.new()
	bucket.position = Vector3(0, 0, -STICK)
	stick.add_child(bucket)
	var steel := Color(0.35, 0.36, 0.38)
	_box(bucket, Vector3(0.95, 0.09, 0.85), Vector3(0, -0.28, -0.5), steel, 0.4) # floor
	_box(bucket, Vector3(0.95, 0.65, 0.09), Vector3(0, 0.0, -0.08), steel, 0.4) # back
	for sx in [-0.47, 0.47]:
		_box(bucket, Vector3(0.07, 0.5, 0.85), Vector3(sx, -0.05, -0.5), steel, 0.4)
	soil = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.5
	soil.mesh = sm
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.45, 0.30, 0.17)
	soil_mat.roughness = 1.0
	soil.material_override = soil_mat
	soil.position = Vector3(0, -0.2, -0.5)
	bucket.add_child(soil)
	set_fill(0.0)


func set_fill(f: float) -> void:
	soil.visible = f > 0.02
	soil.scale = Vector3(0.9, 0.2 + 0.9 * f, 0.9)


## mode: 0 hover, 1 dig, 2 dump. Returns true when the aimed point can be reached.
func update_arm(aim: Vector3, mode: int, dt: float) -> bool:
	var pivot := boom.global_position
	var flat := Vector2(aim.x - pivot.x, aim.z - pivot.z)
	var r := flat.length()
	if r > 0.3:
		var yaw := atan2(-flat.x, -flat.y)
		swing.global_rotation.y = lerp_angle(swing.global_rotation.y, yaw, 1.0 - exp(-7.0 * dt))

	var lift := 0.0
	var phi_goal := deg_to_rad(-60.0)
	match mode:
		1:
			lift = -0.1
			phi_goal = deg_to_rad(-62.0)
		2:
			lift = 1.2
			phi_goal = deg_to_rad(-120.0)
		_:
			lift = 0.9
			phi_goal = deg_to_rad(-50.0)
	_phi = lerp_angle(_phi, phi_goal, 1.0 - exp(-5.0 * dt))
	_tip_goal = _tip_goal.lerp(Vector3(r, aim.y + lift - pivot.y, 0), 1.0 - exp(-10.0 * dt))

	var tip := Vector2(_tip_goal.x, _tip_goal.y)
	var wrist := tip - BUCKET * Vector2(cos(_phi), sin(_phi))
	var d := wrist.length()
	var dmax := BOOM + STICK - 0.05
	in_reach = r >= MIN_REACH and d <= dmax
	d = clampf(d, absf(BOOM - STICK) + 0.1, dmax)
	var a := acos(clampf((BOOM * BOOM + d * d - STICK * STICK) / (2.0 * BOOM * d), -1.0, 1.0))
	var th1 := atan2(wrist.y, wrist.x) + a
	var elbow := BOOM * Vector2(cos(th1), sin(th1))
	var rel := wrist - elbow
	var th2 := atan2(rel.y, rel.x)
	boom.rotation.x = th1
	stick.rotation.x = th2 - th1
	bucket.rotation.x = _phi - th2
	tip_world = bucket.global_position + (-bucket.global_basis.z) * BUCKET
	return in_reach


## Sit on the terrain: height from the centre, pitch/roll from the slope under the tracks.
func align_to_ground(sim: TerrainSim) -> void:
	var f := -global_basis.z
	var rt := global_basis.x
	var p := global_position
	var hc := sim.ground_at(p.x, p.z)
	var hf := sim.ground_at(p.x + f.x * 2.0, p.z + f.z * 2.0)
	var hb := sim.ground_at(p.x - f.x * 2.0, p.z - f.z * 2.0)
	var hr := sim.ground_at(p.x + rt.x * 1.3, p.z + rt.z * 1.3)
	var hl := sim.ground_at(p.x - rt.x * 1.3, p.z - rt.z * 1.3)
	var h := (hc + hf + hb + hr + hl) / 5.0
	position.y = lerpf(position.y, h, 0.25)
	var pitch := atan2(hf - hb, 4.0)
	var roll := atan2(hl - hr, 2.6)
	var yaw := rotation.y
	rotation = Vector3(lerp_angle(rotation.x, pitch, 0.2), yaw, lerp_angle(rotation.z, roll, 0.2))
