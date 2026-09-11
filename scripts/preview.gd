extends SceneTree
##
## A software-rasterised still of the animals, for looking at.
##
##   godot --headless --script res://scripts/preview.gd -- --preview docs/facing.png
##   godot --headless --script res://scripts/preview.gd -- --legacy --preview docs/palette-before.png
##
## `--legacy` swaps in the colours the app shipped with — a dark grey-brown wolf
## and a mid-brown deer on near-black grass, all three under 2 : 1 against each
## other — so the palette change has a before picture taken through the same
## lens as the after one.
##
## Why this exists: the "animals run backwards" bug was a sign in a rotation, and
## a sign in a rotation is invisible in every number the suite prints. What made
## the equivalent war-sim glyph bug obvious was a PNG, so this draws one.
##
## Why it is a rasteriser and not a screenshot: `--headless` gives Godot the
## dummy rendering driver, so there is no viewport to capture and no GLSL to run.
## The mesh, the gait displacement and — the point of the exercise — the instance
## basis are therefore taken from exactly the code the app ships:
## `Meshes.build`, `Gait.displace`, `Field.facing_basis`, and the colours from
## `Palette`. The only thing invented here is the camera. The fill is shared
## with `scripts/blocks.gd` in `scripts/raster.gd`.
##
## Back-face culling is **off** here and on there, and that is not an oversight:
## the animals are drawn by `ui/animals.gdshader`, which is `render_mode
## cull_disabled` because the legs are thin enough to be worth seeing from
## either side. The obstacles are `StandardMaterial3D` and are culled. Each
## picture reproduces its own subject's pipeline.
##
## Layout: four panels. Columns are wolf, deer; rows are two headings. Each panel
## draws a green velocity arrow along `Field.travel_dir(h)` and puts a magenta
## dot on the animal's nose. Nose at the arrowhead is the whole test.
##

const Meshes := preload("res://scripts/meshes.gd")
const Gait := preload("res://scripts/gait.gd")
const Field := preload("res://ui/field.gd")
const Palette := preload("res://scripts/palette.gd")
const Raster := preload("res://scripts/raster.gd")

const W := 1000
const H := 660
const COLS := 2
const ROWS := 2
const FOV := deg_to_rad(38.0)

## Eye and aim, per panel, in the animal's own metres. Three-quarter view from
## above and behind-right: the angle the game's camera actually sits at.
const EYE := Vector3(6.0, 4.7, 9.2)
const AIM := Vector3(0.0, 2.05, 0.0)

const BG := Palette.SKY
const GROUND := Palette.GROUND
const SUN := Vector3(-0.42, -0.78, -0.46)
## Annotation, not scenery, so these two are deliberately outside the palette:
## they have to shout over whatever the palette is.
const ARROW := Color(0.42, 0.92, 0.40)
const NOSE := Color(0.95, 0.25, 0.75)
const RULE := Color(0.55, 0.58, 0.52)

## The pre-palette colours, kept only so `--legacy` can draw the before shot.
const LEGACY := {
	"bg": Color(0.055, 0.065, 0.048),
	"ground": Color(0.105, 0.135, 0.085),
	"wolf": Color(0.42, 0.38, 0.32),
	"deer": Color(0.60, 0.44, 0.27),
}

var _legacy := false
var _r: Raster
var _img: Image


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "docs/facing.png"
	for i in range(args.size()):
		if args[i] == "--legacy":
			_legacy = true
		elif args[i] == "--preview" and i + 1 < args.size():
			path = args[i + 1]
	_render(path)
	quit(0)


func _render(path: String) -> void:
	_r = Raster.new(W, H, LEGACY["bg"] if _legacy else BG)
	_r.cull_back = false            # the animals shader is cull_disabled
	_img = _r.img

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

	_r.save(path)
	print("preview -> %s  %dx%d  (green arrow = travel, magenta dot = nose)" % [path, W, H])


func _panel(rect: Rect2i, deer: bool, h: float, gait: int, phase: float) -> void:
	var inv := Raster.view(EYE, AIM)
	var f := (float(rect.size.y) * 0.5) / tan(FOV * 0.5)
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cy := float(rect.position.y) + float(rect.size.y) * 0.5

	var basis: Basis = Field.facing_basis(h)
	var air: float = Field.AIR[gait] * maxf(0.0, sin(phase * PI))
	var xform := Transform3D(basis, Vector3(0.0, air, 0.0))

	# the ground, so the feet have something to be on
	var g := 26.0
	for t in [[Vector3(-g, 0, -g), Vector3(g, 0, -g), Vector3(g, 0, g)],
			[Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(-g, 0, g)]]:
		_r.tri(rect, inv, f, t[0], t[1], t[2], _ground(), false)

	var custom := Color(phase, Field.SWING[gait], float(Field.PATTERN[gait]), Field.FLEX[gait])
	var tint: Color = _tint(deer)
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
		_r.tri(rect, inv, f, world[a], world[b], world[c],
			Color(tint.r * lit, tint.g * lit, tint.b * lit), false)

	# the two overlays, drawn last and on top of the depth buffer on purpose:
	# they are annotation, not scenery
	var d: Vector3 = Field.travel_dir(h)
	# the arrow floats above the animal so it cannot sit on top of the nose dot
	var tail := Vector3(0.0, 3.6, 0.0) - d * 0.6
	_arrow(rect, inv, f, cx, cy, tail, tail + d * 3.6)
	var np := _r.project(inv, f, cx, cy, world[nose])
	if np.z > 0.0:
		_disc(rect, int(np.x), int(np.y), 5, NOSE)


func _ground() -> Color:
	return LEGACY["ground"] if _legacy else GROUND


func _tint(deer: bool) -> Color:
	if _legacy:
		return LEGACY["deer"] if deer else LEGACY["wolf"]
	return Field.DEER_TINT if deer else Field.WOLF_TINT


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
	var a := _r.project(inv, f, cx, cy, from_w)
	var b := _r.project(inv, f, cx, cy, to_w)
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
