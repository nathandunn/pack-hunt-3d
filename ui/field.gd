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
const Palette := preload("res://scripts/palette.gd")

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

## Coat colours live in `scripts/palette.gd` with the contrast numbers that
## justify them; these two aliases exist so `scripts/preview.gd` and the tests
## can keep asking the renderer rather than the palette.
const WOLF_TINT := Palette.WOLF
const DEER_TINT := Palette.DEER

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
	e.background_color = Palette.SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Palette.AMBIENT
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Palette.FOG
	e.fog_density = 0.0016
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.15
	sun.light_color = Palette.SUN_LIGHT
	sun.shadow_enabled = true
	## The field is 225 m across and the camera sits 150 m off it, so the 100 m
	## default shadow range ended part way over the grass and the split boundary
	## crawled as the view moved. Cover the whole plain and the diagonal a
	## zoomed-out camera can see.
	sun.directional_shadow_max_distance = 420.0
	add_child(sun)

	_build_ground()
	wolves = _multimesh(Meshes.build(false), mat, Palette.WOLF)
	deer = _multimesh(Meshes.build(true), mat, Palette.DEER)


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
	##
	## Pin the visibility AABB to the whole plain plus headroom for a bounding
	## deer. A MultiMesh derives its AABB from the instance transforms it has
	## been given, which means the batch's bounds trail the simulation by a
	## frame and, at an instance count that changes every frame as deer escape,
	## can be stale enough for the frustum test to drop the entire batch. That
	## is the classic "the whole herd blinks out when I turn the camera", and
	## the fix is to stop asking: the animals never leave the field, so say so.
	##
	node.custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0),
		Vector3(FIELD_M_W + 16.0, 12.0, FIELD_M_H + 16.0))
	add_child(node)
	return node


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_M_W, FIELD_M_H)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Palette.GROUND
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
	gmat.albedo_color = Palette.GOAL
	gmat.emission_enabled = true
	gmat.emission = Palette.GOAL_GLOW
	gmat.emission_energy_multiplier = 0.5
	var gi := MeshInstance3D.new()
	gi.mesh = goal
	gi.material_override = gmat
	gi.position = Vector3((World.GOAL_X + 16.0) * M * 0.5, 0.02, FIELD_M_H * 0.5)
	add_child(gi)

	##
	## Deadfall: one MeshInstance3D per patch, five of them, static.
	##
	## Three surface materials rather than one `material_override`: the sides,
	## a top cap a step lighter, and the fallen trunks a step darker. That is
	## what gives the slab a visible top edge from the fixed 45-degree camera
	## instead of it reading as a rectangle painted on the grass.
	##
	var mats: Array[StandardMaterial3D] = []
	for c: Color in [Palette.OBSTACLE, Palette.OBSTACLE_TOP, Palette.OBSTACLE_TRUNK]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		mats.push_back(m)
	for i in range(World.OBSTACLES.size()):
		var o: PackedFloat64Array = World.OBSTACLES[i]
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.brush(o[2] * M, o[3] * M, i)
		for si in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(si, mats[si])
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
	_fill(wolves, f0["wolves"], f1["wolves"], t, Energy.WOLF, false)
	_fill(deer, f0["deer"], f1["deer"], t, Energy.DEER, true)


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
		sp: int, is_deer: bool) -> void:
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

		##
		## Fatigue washes the coat out rather than darkening it. The old code
		## multiplied the tint by as little as 0.55, which dropped a spent deer
		## from 4.19 : 1 against the grass to 2.31 : 1 — the animal was hardest
		## to see at the exact moment the chase is decided. `Palette.coat`
		## interpolates toward a spent tone of the same lightness instead.
		##
		var c: Color = Palette.coat(
			Palette.DEER if is_deer else Palette.WOLF,
			Palette.DEER_SPENT if is_deer else Palette.WOLF_SPENT,
			e["fatigue"])
		if dead:
			c = Palette.DEAD
		mm.set_instance_color(j, c)
		mm.set_instance_custom_data(j, Color(
			fposmod(phase, 1.0),
			0.0 if dead else SWING[gait],
			float(PATTERN[gait]),
			0.0 if dead else FLEX[gait]))
		j += 1
