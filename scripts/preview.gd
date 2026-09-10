extends SceneTree
##
## A software-rasterised still of the animals, for looking at.
##
##   godot --headless --script res://scripts/preview.gd -- --preview docs/facing.png
##
## Why this exists: the "animals run backwards" bug was a sign in a rotation, and
## a sign in a rotation is invisible in every number the suite prints. What made
## the equivalent war-sim glyph bug obvious was a PNG, so this draws one.
##
## Why it is a rasteriser and not a screenshot: `--headless` gives Godot the
## dummy rendering driver, so there is no viewport to capture and no GLSL to run.
## The mesh, the gait displacement and — the point of the exercise — the instance
## basis are therefore taken from exactly the code the app ships:
## `Meshes.build`, `Gait.displace`, `Field.facing_basis`. The only thing invented
## here is the camera and the triangle fill. If the app faces the wrong way, so
## does this picture.
##
## Layout: four panels. Columns are wolf, deer; rows are two headings. Each panel
## draws a green velocity arrow along `Field.travel_dir(h)` and puts a magenta
## dot on the animal's nose. Nose at the arrowhead is the whole test.
##

const Meshes := preload("res://scripts/meshes.gd")
const Gait := preload("res://scripts/gait.gd")
const Field := preload("res://ui/field.gd")

const W := 1000
const H := 660
const COLS := 2
const ROWS := 2
const FOV := deg_to_rad(38.0)

## Eye and aim, per panel, in the animal's own metres. Three-quarter view from
## above and behind-right: the angle the game's camera actually sits at.
const EYE := Vector3(6.0, 4.7, 9.2)
const AIM := Vector3(0.0, 2.05, 0.0)

const BG := Color(0.055, 0.065, 0.048)
const GROUND := Color(0.105, 0.135, 0.085)
const SUN := Vector3(-0.42, -0.78, -0.46)
const ARROW := Color(0.42, 0.92, 0.40)
const NOSE := Color(0.95, 0.25, 0.75)
const RULE := Color(0.20, 0.24, 0.18)

var _img: Image
var _z: PackedFloat32Array


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "docs/facing.png"
	for i in range(args.size()):
		if args[i] == "--preview" and i + 1 < args.size():
			path = args[i + 1]
	_render(path)
	quit(0)


func _render(path: String) -> void:
	_img = Image.create(W, H, false, Image.FORMAT_RGB8)
	_img.fill(BG)
	_z = PackedFloat32Array()
	_z.resize(W * H)
	_z.fill(INF)

	# wolf gallop mid-swing, deer bound at the apex — both the gaits the report
	# was about, both at a phase where a foot is off the ground
	var panels := [
		{"deer": false, "h": 0.0, "gait": 2, "phase": 0.18},
		{"deer": true, "h": 0.0, "gait": 4, "phase": 0.50},
		{"deer": false, "h": 2.35, "gait": 3, "phase": 0.62},
		{"deer": true, "h": -1.05, "gait": 2, "phase": 0.30},
	]
	var pw := W / COLS
	var ph := H / ROWS
	for i in range(panels.size()):
		var p: Dictionary = panels[i]
		var rect := Rect2i((i % COLS) * pw, (i / COLS) * ph, pw, ph)
		_panel(rect, p["deer"], p["h"], p["gait"], p["phase"])
		print("  panel %d  %-5s h=%+.2f rad  gait=%d phase=%.2f  travel=%s"
			% [i, "deer" if p["deer"] else "wolf", p["h"], p["gait"], p["phase"],
			str(Field.travel_dir(p["h"]))])

	# panel rules, so the four reads as four
	for x in range(W):
		_img.set_pixel(x, ph, RULE)
	for y in range(H):
		_img.set_pixel(pw, y, RULE)

	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := _img.save_png(path)
	if err != OK:
		printerr("could not write %s (%d)" % [path, err])
		return
	print("preview -> %s  %dx%d  (green arrow = travel, magenta dot = nose)" % [path, W, H])


func _panel(rect: Rect2i, deer: bool, h: float, gait: int, phase: float) -> void:
	var cam := Transform3D(Basis.IDENTITY, EYE).looking_at(AIM, Vector3.UP)
	var inv := cam.affine_inverse()
	var f := (float(rect.size.y) * 0.5) / tan(FOV * 0.5)
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cy := float(rect.position.y) + float(rect.size.y) * 0.5

	var basis: Basis = Field.facing_basis(h)
	var air: float = Field.AIR[gait] * maxf(0.0, sin(phase * PI))
	var xform := Transform3D(basis, Vector3(0.0, air, 0.0))

	# the ground, so the feet have something to be on
	var g := 26.0
	for tri in [[Vector3(-g, 0, -g), Vector3(g, 0, -g), Vector3(g, 0, g)],
			[Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(-g, 0, g)]]:
		_tri(rect, inv, f, cx, cy, tri[0], tri[1], tri[2], GROUND)

	var custom := Color(phase, Field.SWING[gait], float(Field.PATTERN[gait]), Field.FLEX[gait])
	var tint: Color = Field.DEER_TINT if deer else Field.WOLF_TINT
	var arrays: Array = Meshes.build(deer).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# displace once per vertex, then transform — same order as the shader
	var world := PackedVector3Array()
	world.resize(verts.size())
	var nose := 0
	for i in range(verts.size()):
		world[i] = xform * Gait.displace(verts[i], uv2[i], custom)
		if verts[i].z < verts[nose].z:
			nose = i

	var light := SUN.normalized()
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var n: Vector3 = (basis * norms[a]).normalized()
		var lit: float = 0.34 + 0.66 * maxf(0.0, n.dot(-light))
		_tri(rect, inv, f, cx, cy, world[a], world[b], world[c],
			Color(tint.r * lit, tint.g * lit, tint.b * lit))

	# the two overlays, drawn last and on top of the depth buffer on purpose:
	# they are annotation, not scenery
	var d: Vector3 = Field.travel_dir(h)
	# the arrow floats above the animal so it cannot sit on top of the nose dot
	var tail := Vector3(0.0, 3.6, 0.0) - d * 0.6
	_arrow(rect, inv, f, cx, cy, tail, tail + d * 3.6)
	var np := _project(inv, f, cx, cy, world[nose])
	if np.z > 0.0:
		_disc(rect, int(np.x), int(np.y), 5, NOSE)


func _project(inv: Transform3D, f: float, cx: float, cy: float, p: Vector3) -> Vector3:
	var c := inv * p
	var depth := -c.z
	if depth < 0.02:
		return Vector3(0, 0, -1)
	return Vector3(cx + c.x / depth * f, cy - c.y / depth * f, depth)


func _edge(a: Vector3, b: Vector3, px: float, py: float) -> float:
	return (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)


func _tri(rect: Rect2i, inv: Transform3D, f: float, cx: float, cy: float,
		p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	var a := _project(inv, f, cx, cy, p0)
	var b := _project(inv, f, cx, cy, p1)
	var c := _project(inv, f, cx, cy, p2)
	if a.z < 0.0 or b.z < 0.0 or c.z < 0.0:
		return                      # no near-plane clipping: nothing here crosses it
	var area := _edge(a, b, c.x, c.y)
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
			var o := y * W + x
			if z < _z[o]:
				_z[o] = z
				_img.set_pixel(x, y, col)


func _disc(rect: Rect2i, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r:
				continue
			if not rect.has_point(Vector2i(x, y)):
				continue
			_img.set_pixel(x, y, col)


func _arrow(rect: Rect2i, inv: Transform3D, f: float, cx: float, cy: float,
		from_w: Vector3, to_w: Vector3) -> void:
	var a := _project(inv, f, cx, cy, from_w)
	var b := _project(inv, f, cx, cy, to_w)
	if a.z < 0.0 or b.z < 0.0:
		return
	_line(rect, Vector2(a.x, a.y), Vector2(b.x, b.y), 3)
	var d := (Vector2(b.x, b.y) - Vector2(a.x, a.y)).normalized()
	var n := Vector2(-d.y, d.x)
	var tip := Vector2(b.x, b.y)
	_line(rect, tip, tip - d * 13.0 + n * 8.0, 3)
	_line(rect, tip, tip - d * 13.0 - n * 8.0, 3)


func _line(rect: Rect2i, a: Vector2, b: Vector2, w: int) -> void:
	var steps := int(maxf(2.0, a.distance_to(b)) * 2.0)
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		_disc(rect, int(round(p.x)), int(round(p.y)), w / 2, ARROW)
