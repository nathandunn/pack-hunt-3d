extends Node3D
##
## The 3D view: a flat plain, five deadfall patches, and one
## `MultiMeshInstance3D` per species.
##
## Two MultiMeshes and two draw calls for every animal on the field, whatever
## the count — the gait animation is a vertex-shader displacement driven by four
## floats of per-instance custom data (see `ui/animals.gdshader`). The only
## thing done per instance on the CPU is the transform, and the one part of the
## animation that has to be there: the vertical of a bound, because a leap moves
## the whole animal and its shadow.
##
## The field is 900 x 520 sim units and 1 unit is 0.25 m, so the plain is
## 225 m x 130 m. World space is metres: x = sim x * 0.25, z = sim y * 0.25,
## y up. That keeps the camera's numbers meaningful — a wolf is 1.2 m at the
## shoulder because it is 1.2 m at the shoulder.
##

const World := preload("res://scripts/world.gd")
const Energy := preload("res://scripts/energy.gd")
const Meshes := preload("res://scripts/meshes.gd")

const M := 0.25                       # metres per sim unit
const FIELD_M_W := World.FIELD_W * M
const FIELD_M_H := World.FIELD_H * M

## Units of travel per stride, per gait — the canvas build's `STRIDE`.
const STRIDE := [5.0, 9.0, 24.0, 30.0, 26.0, 11.0]
## Swing amplitude, in local mesh units, per gait.
const SWING := [0.34, 0.55, 1.05, 1.35, 1.15, 0.20]
## Footfall pattern per gait: walk, trot, gallop, sprint(gallop), bound, stot(bound).
const PATTERN := [0, 1, 2, 2, 3, 3]
## Body flex per gait.
const FLEX := [0.02, 0.05, 0.16, 0.22, 0.20, 0.03]
## Height of the leap, in metres, per gait.
const AIR := [0.0, 0.0, 0.10, 0.14, 1.05, 0.55]

const WOLF_TINT := Color(0.42, 0.38, 0.32)
const DEER_TINT := Color(0.60, 0.44, 0.27)

var wolves: MultiMeshInstance3D
var deer: MultiMeshInstance3D
var _frames: Array = []
var _cursor := 0.0


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/animals.gdshader")

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.043, 0.051, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.40, 0.34)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.07, 0.09, 0.06)
	e.fog_density = 0.0016
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	add_child(sun)

	_build_ground()
	wolves = _multimesh(Meshes.build(false), mat, WOLF_TINT)
	deer = _multimesh(Meshes.build(true), mat, DEER_TINT)


func _multimesh(mesh: ArrayMesh, mat: ShaderMaterial, tint: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.set_meta("tint", tint)
	add_child(node)
	return node


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_M_W, FIELD_M_H)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.105, 0.135, 0.085)
	gm.roughness = 1.0
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = gm
	ground.position = Vector3(FIELD_M_W * 0.5, 0, FIELD_M_H * 0.5)
	add_child(ground)

	# the goal strip on the LEFT edge — the deer's whole objective
	var goal := PlaneMesh.new()
	goal.size = Vector2((World.GOAL_X + 16.0) * M, FIELD_M_H)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.35, 0.62, 0.34)
	gmat.emission_enabled = true
	gmat.emission = Color(0.18, 0.36, 0.17)
	gmat.emission_energy_multiplier = 0.5
	var gi := MeshInstance3D.new()
	gi.mesh = goal
	gi.material_override = gmat
	gi.position = Vector3((World.GOAL_X + 16.0) * M * 0.5, 0.02, FIELD_M_H * 0.5)
	add_child(gi)

	# deadfall: one MeshInstance3D per patch, five of them, static
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.20, 0.22, 0.12)
	bm.roughness = 1.0
	for i in range(World.OBSTACLES.size()):
		var o: PackedFloat64Array = World.OBSTACLES[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.brush(o[2] * M, o[3] * M, i)
		mi.material_override = bm
		mi.position = Vector3((o[0] + o[2] * 0.5) * M, 0.0, (o[1] + o[3] * 0.5) * M)
		add_child(mi)


func set_frames(f: Array) -> void:
	_frames = f
	_cursor = 0.0
	_apply()


func set_cursor(c: float) -> void:
	_cursor = c
	_apply()


func frame_count() -> int:
	return _frames.size()


func _apply() -> void:
	if _frames.is_empty():
		wolves.multimesh.instance_count = 0
		deer.multimesh.instance_count = 0
		return
	var i0: int = clampi(int(floor(_cursor)), 0, _frames.size() - 1)
	var i1: int = mini(i0 + 1, _frames.size() - 1)
	var t: float = _cursor - float(i0)
	var f0: Dictionary = _frames[i0]
	var f1: Dictionary = _frames[i1]
	_fill(wolves, f0["wolves"], f1["wolves"], t, Energy.WOLF, WOLF_TINT, false)
	_fill(deer, f0["deer"], f1["deer"], t, Energy.DEER, DEER_TINT, true)


##
## Where an animal at sim heading `h` is going, in world space.
##
## Sim space is 2D with x to the right and y downward; this view maps sim x onto
## world +X and sim y onto world +Z (see `M` above), so a heading advances along
## (cos h, 0, sin h). `world.gd` moves every animal by exactly `cos(h), sin(h)`
## times its speed, so this IS the velocity direction, not an approximation of
## one.
##
static func travel_dir(h: float) -> Vector3:
	return Vector3(cos(h), 0.0, sin(h))


##
## The instance basis for an animal travelling at sim heading `h`.
##
## The meshes in `meshes.gd` are built nose-toward -Z, which is Godot's forward,
## so the basis has to carry local -Z onto `travel_dir(h)`.
##
## `Basis(Vector3.UP, t)` sends (0, 0, -1) to (-sin t, 0, -cos t). Setting that
## equal to (cos h, 0, sin h) gives sin t = -cos h and cos t = -sin h, i.e.
## t = -h - PI/2.
##
## The build shipped `-h + PI/2`, which is that vector negated — every animal on
## the field faced exactly 180 degrees away from its travel. That is the whole
## of the "deer and wolves run backwards" report, and the reason it survived
## review is that a wolf pointing away from a deer it is closing on still looks
## purposeful in a still frame.
##
static func facing_basis(h: float) -> Basis:
	return Basis(Vector3.UP, -h - PI * 0.5)


func _fill(node: MultiMeshInstance3D, a: Array, b: Array, t: float,
		sp: int, tint: Color, is_deer: bool) -> void:
	var mm := node.multimesh
	var shown := 0
	for i in range(a.size()):
		if is_deer and a[i]["escaped"]:
			continue
		shown += 1
	if mm.instance_count != shown:
		mm.instance_count = shown
	var j := 0
	for i in range(a.size()):
		var e: Dictionary = a[i]
		if is_deer and e["escaped"]:
			continue
		var f: Dictionary = b[i]
		var x: float = lerpf(e["x"], f["x"], t) * M
		var z: float = lerpf(e["y"], f["y"], t) * M
		var gait: int = e["gait"]
		var phase: float = e["phase"] / STRIDE[gait]
		var dead: bool = is_deer and not e["alive"]

		# the vertical of a leap: whole-animal, so the shadow moves with it
		var air := 0.0
		if not dead and AIR[gait] > 0.0:
			air = AIR[gait] * maxf(0.0, sin(fposmod(phase, 1.0) * PI))

		var basis := facing_basis(e["h"])
		if dead:
			# topple onto the flank: a roll about the animal's own forward axis
			basis = basis.rotated(travel_dir(e["h"]), PI * 0.5)
		var tr := Transform3D(basis, Vector3(x, air, z))
		mm.set_instance_transform(j, tr)

		# fatigue darkens the coat: a spent animal reads as a spent animal
		var lit: float = 1.0 - 0.45 * e["fatigue"]
		var c := Color(tint.r * lit, tint.g * lit, tint.b * lit)
		if dead:
			c = Color(0.30, 0.18, 0.16)
		mm.set_instance_color(j, c)
		mm.set_instance_custom_data(j, Color(
			fposmod(phase, 1.0),
			0.0 if dead else SWING[gait],
			float(PATTERN[gait]),
			0.0 if dead else FLEX[gait]))
		j += 1
