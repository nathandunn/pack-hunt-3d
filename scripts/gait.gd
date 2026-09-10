extends RefCounted
##
## The gait cycle, in one place.
##
## The run cycle is a vertex-shader displacement (`ui/animals.gdshader`) so that
## a hundred animals stay two draw calls. That means the maths lives in GLSL,
## where nothing headless can reach it — so it is written here too, in GDScript,
## and `scripts/tests.gd` asserts the two have not drifted apart by checking the
## shader source for the exact lines this file mirrors. The preview renderer
## (`scripts/preview.gd`) rasterises through THIS copy, which is what makes the
## preview PNG evidence about the shader rather than a second opinion.
##
## Vertex inputs, both here and there:
##   uv2.x  swing weight — 0 at the shoulder, 1 at the foot, 0 on anything that
##          is not a leg
##   uv2.y  that leg's index / 4 — 0, 0.25, 0.5, 0.75
## Instance inputs:
##   custom.x  phase through the stride, 0..1
##   custom.y  swing amplitude, in local units
##   custom.z  footfall pattern index
##   custom.w  body flex
##

## Footfall patterns, as four phase offsets — the canvas build's `footPhase`
## offsets, unchanged. Leg order is LF, RF, LH, RH.
const FOOTFALL := [
	[0.0, 0.5, 0.25, 0.75],   # walk: each foot a quarter-cycle behind the last
	[0.0, 0.5, 0.5, 0.0],     # trot: diagonal pairs
	[0.0, 0.12, 0.55, 0.67],  # gallop: fore pair, then hind pair
	[0.0, 0.0, 0.0, 0.0],     # bound: together
]


##
## One vertex through the gait, in the mesh's own space (nose toward -Z).
##
## The sign of the swing term is the thing to get right. A leg lifts while it
## swings FORWARD (the swing phase) and stays planted while it travels backward
## under the body (the stance phase); the lift is `max(0, sin)`, which is the
## first half of the cycle, so the fore-and-aft term has to be forward over that
## same half. Forward is -Z, so it is `VERTEX.z -= swing`. The build shipped
## `+=`, which put the lift on the stance half instead: the feet skated forward
## on the floor and picked up on the way back. Combined with the 180-degree
## basis error in `ui/field.gd` that read, correctly, as an animal moonwalking
## away from where it was going.
##
static func displace(vertex: Vector3, uv2: Vector2, custom: Color) -> Vector3:
	var weight := uv2.x
	var leg := int(round(uv2.y * 4.0))
	var pattern := int(round(custom.b))
	var off: float = FOOTFALL[clampi(pattern, 0, 3)][clampi(leg, 0, 3)]
	var ph := fposmod(custom.r + off, 1.0)
	var swing := sin(ph * TAU) * custom.g

	var v := vertex
	v.z -= weight * swing
	v.y += weight * maxf(0.0, sin(ph * TAU)) * custom.g * 0.22

	var flex := custom.a * sin(ph * TAU + 1.2)
	v.z += (1.0 - weight) * signf(v.z) * flex
	v.y += (1.0 - weight) * flex * 0.35
	return v
