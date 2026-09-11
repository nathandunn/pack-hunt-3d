extends SceneTree
##
## The deadfall render check: three camera angles, one PNG, and an assertion
## that the blocks are there and are not black.
##
##   godot --headless --script res://scripts/blocks.gd -- --png docs/blocks-after.png
##   godot --headless --script res://scripts/blocks.gd -- --legacy --png docs/blocks-before.png
##
## The report this exists for was "the obstacle blocks render black and blink in
## and out when the camera rotates", and it was two things at once:
##
##   1. `Meshes._box` emitted counter-clockwise triangles. Godot's front face is
##      the clockwise winding, so `StandardMaterial3D`'s default `cull_back`
##      threw away every outward face of every deadfall patch and left the far
##      interior ones — normals pointing away from the sun, hence black, and a
##      different subset winning the depth test from every angle, hence
##      blinking. The animals were exempt only because their shader is
##      `render_mode cull_disabled`.
##   2. The slab's underside sat at exactly y = 0, coplanar with the ground
##      plane. Two coplanar surfaces 200 m from the camera are a depth-precision
##      coin toss that comes up differently as the view moves.
##
## `--legacy` rebuilds both faults — inward winding, base on the floor, the old
## dark-olive tint — so the before and after PNGs come out of one renderer and
## the difference in them is the fix and nothing else.
##
## The assertions are the part that keeps working after today. From each of the
## three angles: every patch must put pixels on the screen (not absent); no
## obstacle pixel may fall below a brightness floor (not black); and the bulk of
## them must clear WCAG 3:1 against the ground.
##
## "The bulk", not "all", and the slack is named rather than fudged: the sides
## of a slab that face away from the sun sit at ambient, and a face in shadow
## being darker than the sunlit grass is how a solid reads as a solid. What the
## bar is for is the *material*, and the material-level check — every palette
## entry against `Palette.GROUND` — is in `scripts/tests.gd`, where it is exact.
## Here the top cap and the two lit sides are ~95% of what the eye gets from a
## 45-degree camera, so 90% is the line.
##

const Meshes := preload("res://scripts/meshes.gd")
const Palette := preload("res://scripts/palette.gd")
const World := preload("res://scripts/world.gd")
const Raster := preload("res://scripts/raster.gd")

const M := 0.25
const W := 1320
const H := 480
## The three angles. The app's camera is fixed at 45 degrees now, but the bug
## was angle-dependent, so the check is not: these sweep the yaw the old orbit
## control could reach.
const ANGLES := [-90.0, -34.0, -146.0]
const PITCH := 45.0
const FOV := deg_to_rad(42.0)
const DIST := 170.0
const SUN := Vector3(-0.42, -0.78, -0.46)
## Stand-in for the scene's ambient light, as a fraction of full albedo.
const AMBIENT := 0.5

## "not black": a drawn obstacle pixel must be at least this bright, and the
## patch as a whole must clear this much contrast against the ground.
const MIN_VALUE := 0.20
const MIN_CONTRAST := 3.0
## fraction of obstacle pixels that must clear MIN_CONTRAST
const MIN_CLEAR := 0.90
## and "not absent": each of the five patches must cover at least this many
## pixels in each panel.
const MIN_PIXELS := 150

var legacy := false
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	for i in range(args.size()):
		if args[i] == "--legacy":
			legacy = true
		elif args[i] == "--png" and i + 1 < args.size():
			path = args[i + 1]

	var ground: Color = Color("#1a2015") if legacy else Palette.GROUND
	var side: Color = Color("#333a1f") if legacy else Palette.OBSTACLE
	var cap: Color = Color("#333a1f") if legacy else Palette.OBSTACLE_TOP
	var trunk: Color = Color("#333a1f") if legacy else Palette.OBSTACLE_TRUNK
	var bg: Color = Color("#141810") if legacy else Palette.SKY

	var r := Raster.new(W, H, bg)
	var pw := W / ANGLES.size()
	print("deadfall render check — %s" % ("LEGACY (pre-fix)" if legacy else "current"))
	for i in range(ANGLES.size()):
		_panel(r, Rect2i(i * pw, 0, pw, H), ANGLES[i], ground, side, cap, trunk)

	for x in range(W):
		if x % pw == 0 and x > 0:
			for y in range(H):
				r.img.set_pixel(x, y, Color(0.5, 0.5, 0.5))
	if path != "":
		r.save(path)
		print("  -> %s  %dx%d" % [path, W, H])

	if failures > 0:
		printerr("FAIL: %d block assertion(s)" % failures)
		quit(1)
		return
	print("  ok")
	quit(0)


func _panel(r: Raster, rect: Rect2i, yaw_deg: float, ground: Color, side: Color, cap: Color,
		trunk: Color) -> void:
	var fw := World.FIELD_W * M
	var fh := World.FIELD_H * M
	var centre := Vector3(fw * 0.5, 0, fh * 0.5)
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(PITCH)
	var eye := centre + Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)) * DIST
	var inv := Raster.view(eye, centre)
	var f := r.focal(FOV)
	var light := SUN.normalized()

	# the plain, as two triangles wound the way the engine winds PlaneMesh
	var g := [Vector3(0, 0, 0), Vector3(fw, 0, 0), Vector3(fw, 0, fh), Vector3(0, 0, fh)]
	var lit: float = AMBIENT + (1.0 - AMBIENT) * maxf(0.0, Vector3.UP.dot(-light))
	var gc := Color(ground.r * lit, ground.g * lit, ground.b * lit)
	for t in [[0, 2, 1], [0, 3, 2]]:
		r.tri(rect, inv, f, g[t[0]], g[t[1]], g[t[2]], gc, false)

	##
	## Draw the five patches, counting the obstacle pixels each one adds. A
	## pixel is "obstacle" when it is neither the sky nor the one flat shade
	## the ground is filled with, which is exact here because this rasteriser
	## flat-shades and the ground is a single plane.
	##
	var drawn_all := 0
	var tints := [side, cap, trunk]
	var bg := r.img.get_pixel(rect.position.x, rect.position.y)
	for i in range(World.OBSTACLES.size()):
		var o: PackedFloat64Array = World.OBSTACLES[i]
		var mesh := _brush(o[2] * M, o[3] * M, i)
		var xf := Transform3D(Basis.IDENTITY,
			Vector3((o[0] + o[2] * 0.5) * M, 0.0, (o[1] + o[3] * 0.5) * M))
		var before: int = _stats(r, rect, bg, gc)["n"]
		var n := 0
		for si in range(mesh.get_surface_count()):
			n += r.mesh_surface(rect, inv, f, mesh, si, xf, tints[si], light, AMBIENT)
		drawn_all += n
		var px: int = _stats(r, rect, bg, gc)["n"] - before
		if px < MIN_PIXELS:
			printerr("  yaw %+.0f patch %d: only %d obstacle pixels (%d triangles survived the cull)"
				% [yaw_deg, i, px, n])
			failures += 1

	var st := _stats(r, rect, bg, gc, ground)
	var total: int = st["n"]
	if total == 0:
		printerr("  yaw %+.0f: no obstacle pixels at all" % yaw_deg)
		failures += 1
		return
	if st["dark"] > 0:
		printerr("  yaw %+.0f: %d/%d obstacle pixels below value %.2f — the blocks are black"
			% [yaw_deg, st["dark"], total, MIN_VALUE])
		failures += 1
	var clear := 1.0 - float(st["low"]) / float(total)
	if clear < MIN_CLEAR:
		printerr("  yaw %+.0f: only %.1f%% of obstacle pixels clear %.1f:1 against the ground"
			% [yaw_deg, clear * 100.0, MIN_CONTRAST])
		failures += 1
	print("  yaw %+5.0f  %6d obstacle px  %3d triangles lit  darkest %.3f  %.1f%% clear %.0f:1"
		% [yaw_deg, total, drawn_all, st["darkest"], clear * 100.0, MIN_CONTRAST])


##
## Classify the panel: how many pixels are obstacle, how many of those are
## below the brightness floor, how many are under the contrast bar, and the
## worst of each.
##
func _stats(r: Raster, rect: Rect2i, bg: Color, gc: Color, ground: Color = Color.BLACK) -> Dictionary:
	var n := 0
	var dark := 0
	var low := 0
	var darkest := 1.0
	var worst := 21.0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c := r.img.get_pixel(x, y)
			if _near(c, bg) or _near(c, gc):
				continue
			n += 1
			var v := maxf(c.r, maxf(c.g, c.b))
			darkest = minf(darkest, v)
			if v < MIN_VALUE:
				dark += 1
			if ground != Color.BLACK:
				var k := Palette.contrast(c, ground)
				worst = minf(worst, k)
				if k < MIN_CONTRAST:
					low += 1
	return {"n": n, "dark": dark, "low": low, "darkest": darkest, "worst": worst}


func _brush(w: float, d: float, idx: int) -> ArrayMesh:
	if not legacy:
		return Meshes.brush(w, d, idx)
	# the pre-fix slab: one surface, wound inward, underside flat on the ground
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_legacy_box(st, Vector3(0, 0.12, 0), Vector3(w * 0.5, 0.12, d * 0.5))
	st.index()
	return st.commit()


static func _legacy_box(st: SurfaceTool, c: Vector3, half: Vector3) -> void:
	var faces := [
		[Vector3(1, 1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1)],
		[Vector3(-1, 1, -1), Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1)],
		[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
		[Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)],
		[Vector3(-1, 1, 1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1)],
		[Vector3(1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1)],
	]
	for fc: Array in faces:
		var p: Array = []
		for s: Vector3 in fc:
			p.push_back(c + Vector3(s.x * half.x, s.y * half.y, s.z * half.z))
		var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		for t: Array in [[0, 1, 2], [0, 2, 3]]:     # the bug: inward
			for k: int in t:
				st.set_normal(n)
				st.set_uv2(Vector2.ZERO)
				st.add_vertex(p[k])


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004
