extends RefCounted
class_name Raster
##
## A software triangle rasteriser, so the build host can look at its own output.
##
## `--headless` gives Godot the dummy rendering driver: there is no viewport to
## capture and no GLSL to run, so a screenshot test is not available on the hub
## and the browser is the only place the real renderer exists. That is exactly
## how two total rendering bugs — the animals facing backwards, and then the
## deadfall blocks rendering black — reached a phone.
##
## So this draws the scene from the same data the app draws it from: the meshes
## out of `scripts/meshes.gd`, the colours out of `scripts/palette.gd`, the
## instance basis out of `ui/field.gd`. The only things invented here are the
## camera and the fill.
##
## **It culls back faces the way the GPU culls them — on the projected winding,
## not on the vertex normal** — and that is the point of the class rather than
## an incidental detail. A mesh wound inside-out still carries correct normals;
## culling on the normal would draw it happily and the headless PNG would show
## a scene the browser does not. Culling on the signed screen area is what lets
## a PNG on a machine with no GPU catch the winding bug that made the deadfall
## blocks black. `scripts/tests.gd` pins the sign below against a real
## `BoxMesh`, so the convention is asserted rather than remembered.
##

var width: int
var height: int
var img: Image
var _z: PackedFloat32Array

## Sign of the projected signed area of a front-facing triangle, under the
## projection in `project()` (screen y downward). Measured against `BoxMesh`,
## asserted in `tests.gd::_test_winding`.
const FRONT_SIGN := 1.0

var cull_back := true


func _init(w: int, h: int, bg: Color) -> void:
	width = w
	height = h
	img = Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(bg)
	_z = PackedFloat32Array()
	_z.resize(w * h)
	_z.fill(INF)


## A view: eye at `eye`, looking at `aim`, vertical field of view `fov`.
static func view(eye: Vector3, aim: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, eye).looking_at(aim, Vector3.UP).affine_inverse()


func focal(fov: float) -> float:
	return (float(height) * 0.5) / tan(fov * 0.5)


func project(inv: Transform3D, f: float, cx: float, cy: float, p: Vector3) -> Vector3:
	var c := inv * p
	var depth := -c.z
	if depth < 0.02:
		return Vector3(0, 0, -1)
	return Vector3(cx + c.x / depth * f, cy - c.y / depth * f, depth)


static func _edge(a: Vector3, b: Vector3, px: float, py: float) -> float:
	return (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)


##
## One triangle, in world space, flat-shaded `col`. `normal` is the surface
## normal in world space and is what the back-face test uses — passing
## `Vector3.ZERO` disables the test for that triangle (the annotation overlays
## in `scripts/preview.gd` want that).
##
func tri(rect: Rect2i, inv: Transform3D, f: float, p0: Vector3, p1: Vector3, p2: Vector3,
		col: Color, cull: bool = true) -> void:
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cy := float(rect.position.y) + float(rect.size.y) * 0.5
	var a := project(inv, f, cx, cy, p0)
	var b := project(inv, f, cx, cy, p1)
	var c := project(inv, f, cx, cy, p2)
	if a.z < 0.0 or b.z < 0.0 or c.z < 0.0:
		return                      # no near-plane clipping: nothing here crosses it
	var area := _edge(a, b, c.x, c.y)
	if cull and cull_back and area * FRONT_SIGN <= 0.0:
		return
	if absf(area) < 1e-9:
		return
	var x0 := maxi(rect.position.x, int(floor(minf(a.x, minf(b.x, c.x)))))
	var x1 := mini(rect.position.x + rect.size.x - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var y0 := maxi(rect.position.y, int(floor(minf(a.y, minf(b.y, c.y)))))
	var y1 := mini(rect.position.y + rect.size.y - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			# dividing each edge function by the signed area makes the
			# barycentrics positive inside the triangle for either winding
			var w0 := _edge(b, c, px, py) / area
			if w0 < 0.0:
				continue
			var w1 := _edge(c, a, px, py) / area
			if w1 < 0.0:
				continue
			var w2 := 1.0 - w0 - w1
			if w2 < 0.0:
				continue
			var z := w0 * a.z + w1 * b.z + w2 * c.z
			var o := y * width + x
			if z < _z[o]:
				_z[o] = z
				img.set_pixel(x, y, col)


##
## Every triangle of `mesh`'s surface `si`, transformed by `xform`, lit by a
## single directional light and tinted `tint`.
##
## Returns the number of triangles that survived the back-face cull — the
## number the block test cares about, because zero means the object is wound
## inside-out and the viewer is looking through it.
##
func mesh_surface(rect: Rect2i, inv: Transform3D, f: float, mesh: ArrayMesh, si: int,
		xform: Transform3D, tint: Color, light: Vector3, ambient: float = 0.34) -> int:
	var arrays: Array = mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cy := float(rect.position.y) + float(rect.size.y) * 0.5
	var drawn := 0
	for t in range(0, idx.size(), 3):
		var p0: Vector3 = xform * verts[idx[t]]
		var p1: Vector3 = xform * verts[idx[t + 1]]
		var p2: Vector3 = xform * verts[idx[t + 2]]
		var a := project(inv, f, cx, cy, p0)
		var b := project(inv, f, cx, cy, p1)
		var c := project(inv, f, cx, cy, p2)
		if a.z < 0.0 or b.z < 0.0 or c.z < 0.0:
			continue
		if cull_back and _edge(a, b, c.x, c.y) * FRONT_SIGN <= 0.0:
			continue
		drawn += 1
		var n: Vector3 = (xform.basis * norms[idx[t]]).normalized()
		var lit: float = ambient + (1.0 - ambient) * maxf(0.0, n.dot(-light))
		tri(rect, inv, f, p0, p1, p2, Color(tint.r * lit, tint.g * lit, tint.b * lit))
	return drawn


func save(path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(path)
	if err != OK:
		printerr("could not write %s (%d)" % [path, err])
