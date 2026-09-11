extends RefCounted
##
## Low-poly wolf and deer, built in code. Nothing is imported from outside this
## repo and no external asset is used: both animals are a handful of boxes
## welded into one `ArrayMesh` each, so a species is one `MultiMeshInstance3D`
## and one draw call at any animal count.
##
## The trick that makes that work with animation is where the gait lives. A
## MultiMesh gives every instance exactly one transform, so limbs cannot be
## posed per instance on the CPU. Instead every vertex carries, in UV2:
##
##   UV2.x  swing weight — 0 at the shoulder, 1 at the foot, 0 everywhere that
##          is not a leg. The vertex shader displaces along the body's forward
##          axis by `weight * amplitude * sin(phase + offset)`.
##   UV2.y  that leg's phase offset in the footfall pattern, 0..1.
##
## and the per-instance custom data carries the phase, the swing amplitude and
## the footfall pattern. So the run cycle is a vertex-shader displacement, the
## gait is one float per instance, and the draw-call count does not move.
##
## The vertical of a bound is NOT in the shader — it is in the instance
## transform, because a leap has to move the whole animal and cast its shadow
## from a different place than its feet.
##

## The footfall patterns this mesh's UV2 leg indices are looked up in live in
## `scripts/gait.gd`, next to the displacement that consumes them.


## `skip` lists face indices (0:+x 1:-x 2:+y 3:-y 4:+z 5:-z) to leave out, so a
## box can be split across two surfaces.
static func _box(st: SurfaceTool, c: Vector3, half: Vector3, swing: float, offset: float,
		skip: Array = []) -> void:
	var faces := [
		[Vector3(1, 1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1)],     # +x
		[Vector3(-1, 1, -1), Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1)], # -x
		[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],     # +y
		[Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)], # -y
		[Vector3(-1, 1, 1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1)],     # +z
		[Vector3(1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1)], # -z
	]
	for fi in range(faces.size()):
		if skip.has(fi):
			continue
		var f: Array = faces[fi]
		var p: Array = []
		for s: Vector3 in f:
			p.push_back(c + Vector3(s.x * half.x, s.y * half.y, s.z * half.z))
		var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		##
		## Godot's front face is the CLOCKWISE winding — the engine's own
		## `BoxMesh` emits triangles whose `(p1-p0) x (p2-p0)` *opposes* the
		## vertex normal, and `tests.gd` asserts that against a real `BoxMesh`
		## rather than trusting this comment. The quads above are listed
		## counter-clockwise about `n`, so they are emitted reversed.
		##
		## They used to be emitted `[0,1,2], [0,2,3]`, i.e. facing inward, and
		## that is the whole of the "the deadfall blocks are black and blink
		## when I move the camera" report: every outward face of every obstacle
		## was culled by the default `cull_back`, leaving only the far interior
		## faces, whose normals point away from the camera and therefore catch
		## no sun. Which interior faces won the depth test changed with the
		## view, so the patches flickered. The animals were exempt only because
		## `ui/animals.gdshader` is `render_mode cull_disabled`, which is why a
		## bug this total hid in one kind of object.
		##
		for tri: Array in [[0, 2, 1], [0, 3, 2]]:
			for k: int in tri:
				st.set_normal(n)
				st.set_uv2(Vector2(swing, offset))
				st.add_vertex(p[k])


##
## One animal, facing -Z (Godot's forward), standing on y = 0.
##
## `deer` gets a longer neck carried high and a short pale tail; the wolf's head
## runs level with the spine and its tail is long and low. From a 45-degree
## camera at this size that neck is the whole difference between the two
## silhouettes, which is why it is the one proportion that is exaggerated.
##
static func build(deer: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body_len := 3.4 if deer else 3.1
	var body_w := 1.05 if deer else 1.15
	var body_h := 1.0 if deer else 1.05
	var leg_len := 1.7 if deer else 1.25
	var leg_w := 0.20 if deer else 0.26
	var hip := leg_len + body_h * 0.5

	# barrel
	_box(st, Vector3(0, hip, 0), Vector3(body_w * 0.5, body_h * 0.5, body_len * 0.5), 0.0, 0.0)
	# shoulders, a touch taller than the hindquarters on both
	_box(st, Vector3(0, hip + 0.16, -body_len * 0.28),
		Vector3(body_w * 0.52, body_h * 0.42, body_len * 0.22), 0.0, 0.0)

	# neck and head
	var neck_z := -body_len * 0.5
	var neck_top := hip + (1.15 if deer else 0.30)
	_box(st, Vector3(0, (hip + neck_top) * 0.5, neck_z - 0.30),
		Vector3(0.30 if deer else 0.40, absf(neck_top - hip) * 0.5 + 0.30, 0.34), 0.0, 0.0)
	_box(st, Vector3(0, neck_top, neck_z - (0.75 if deer else 0.95)),
		Vector3(0.30, 0.28, 0.55 if deer else 0.60), 0.0, 0.0)
	# ears / antlers
	for sx: float in [-1.0, 1.0]:
		if deer:
			_box(st, Vector3(sx * 0.34, neck_top + 0.60, neck_z - 0.62), Vector3(0.07, 0.42, 0.07), 0.0, 0.0)
			_box(st, Vector3(sx * 0.52, neck_top + 0.92, neck_z - 0.50), Vector3(0.06, 0.06, 0.30), 0.0, 0.0)
		else:
			_box(st, Vector3(sx * 0.24, neck_top + 0.34, neck_z - 0.66), Vector3(0.10, 0.24, 0.10), 0.0, 0.0)

	# tail
	if deer:
		_box(st, Vector3(0, hip + 0.30, body_len * 0.5 + 0.22), Vector3(0.20, 0.34, 0.22), 0.0, 0.0)
	else:
		_box(st, Vector3(0, hip - 0.18, body_len * 0.5 + 0.55), Vector3(0.14, 0.14, 0.62), 0.0, 0.0)

	# legs. Two segments each, so the swing bends at the knee rather than
	# pivoting the whole limb like a stick.
	var i := 0
	for fore: bool in [true, false]:
		for sx: float in [-1.0, 1.0]:
			var z: float = (-body_len * 0.30) if fore else (body_len * 0.32)
			var x: float = sx * body_w * 0.42
			var offset := float(i) / 4.0     # replaced per-instance; see the shader
			_box(st, Vector3(x, hip - body_h * 0.5 - leg_len * 0.28, z),
				Vector3(leg_w, leg_len * 0.30, leg_w), 0.35, offset)
			_box(st, Vector3(x, leg_len * 0.30, z),
				Vector3(leg_w * 0.85, leg_len * 0.32, leg_w * 0.85), 0.75, offset)
			_box(st, Vector3(x, 0.09, z + 0.06),
				Vector3(leg_w, 0.09, leg_w * 1.5), 1.0, offset)
			i += 1

	st.index()
	return st.commit()


##
## A brush patch: a slab plus a scatter of fallen trunks, deterministic in the
## patch index so the field looks the same every run.
##
## Three surfaces, not one, and that is a legibility decision: surface 0 is the
## slab's sides, surface 1 its top cap and surface 2 the fallen trunks, so
## `ui/field.gd` can paint the top a step lighter than the sides and the wood a
## step darker than either. Without that a deadfall from a 45-degree camera is a
## flat warm rectangle lying on the grass; with it, the lit top and the darker
## sides give it a height and the trunks say what it is made of, which is what
## the top-edge note in the brief was asking for.
##
## `BASE_Y` is the other half of the block fix. The slab used to sit with its
## underside at exactly y = 0, coplanar with the ground plane, and two coplanar
## surfaces at 225 m from the camera are a depth-precision coin toss that comes
## up differently every time the view moves — the second, independent source of
## the flicker, underneath the winding bug. It is now lifted clear.
##
const BASE_Y := 0.05
const SLAB_H := 0.30


static func brush(w: float, d: float, idx: int) -> ArrayMesh:
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)

	var slab_c := Vector3(0, BASE_Y + SLAB_H * 0.5, 0)
	var slab_h := Vector3(w * 0.5, SLAB_H * 0.5, d * 0.5)
	_box(body, slab_c, slab_h, 0.0, 0.0, [2])        # every face but the top
	_box(top, slab_c, slab_h, 0.0, 0.0, [0, 1, 3, 4, 5])

	var s := 7919 + idx * 104729
	var rnd := func() -> float:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		return float(s) / float(0x7FFFFFFF)
	for i in range(14):
		var x: float = (rnd.call() - 0.5) * (w - 2.0)
		var z: float = (rnd.call() - 0.5) * (d - 2.0)
		var a: float = rnd.call() * PI
		var ln: float = 1.6 + rnd.call() * 3.2
		var half := Vector3(0.16, 0.16, ln * 0.5)
		# a trunk lying at angle a, approximated by its axis-aligned span —
		# the mesh is welded once and never transformed per instance
		_box(wood, Vector3(x, BASE_Y + SLAB_H + 0.10, z),
			Vector3(maxf(half.x, absf(sin(a)) * half.z), half.y, maxf(half.x, absf(cos(a)) * half.z)), 0.0, 0.0)
	body.index()
	top.index()
	wood.index()
	var mesh: ArrayMesh = body.commit()
	top.commit(mesh)
	wood.commit(mesh)
	return mesh
