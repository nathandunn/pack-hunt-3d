shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

//
// The gait, in the vertex shader.
//
// A MultiMesh gives every instance one transform, so limbs cannot be posed per
// instance from GDScript. What each vertex carries instead is UV2:
//
//   UV2.x  swing weight — 0 at the shoulder, 1 at the foot, 0 on anything that
//          is not a leg
//   UV2.y  that leg's index, 0/0.25/0.5/0.75, used to look its footfall offset
//          up in `FOOTFALL`
//
// and each instance carries, in INSTANCE_CUSTOM:
//
//   .x  phase through the stride, 0..1
//   .y  swing amplitude, in local units — this is what makes a sprint reach
//       further than a walk
//   .z  footfall pattern index: 0 walk, 1 trot, 2 gallop, 3 bound
//   .w  body flex, the gather-and-extend of a gallop
//
// So a running wolf and a bounding deer are the same draw call, and the whole
// animation costs four floats per instance.
//

const float FOOTFALL[16] = float[](
	0.0, 0.5, 0.25, 0.75,     // walk: each foot a quarter-cycle behind the last
	0.0, 0.5, 0.5, 0.0,       // trot: diagonal pairs
	0.0, 0.12, 0.55, 0.67,    // gallop: fore pair, then hind pair
	0.0, 0.0, 0.0, 0.0        // bound: together
);

void vertex() {
	float weight = UV2.x;
	int leg = int(round(UV2.y * 4.0));
	int pattern = int(round(INSTANCE_CUSTOM.z));
	float off = FOOTFALL[clamp(pattern, 0, 3) * 4 + clamp(leg, 0, 3)];
	float ph = fract(INSTANCE_CUSTOM.x + off);
	float swing = sin(ph * TAU) * INSTANCE_CUSTOM.y;

	// the leg swings fore and aft along the body's own forward axis, and lifts
	// as it comes through — a limb that stays on the floor reads as a skid
	VERTEX.z += weight * swing;
	VERTEX.y += weight * max(0.0, sin(ph * TAU)) * INSTANCE_CUSTOM.y * 0.22;

	// the spine gathers and extends. Applied to everything that is not a leg,
	// scaled by how far up the body the vertex is, so the shoulders move and
	// the feet do not.
	float flex = INSTANCE_CUSTOM.w * sin(ph * TAU + 1.2);
	VERTEX.z += (1.0 - weight) * sign(VERTEX.z) * flex;
	VERTEX.y += (1.0 - weight) * flex * 0.35;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
}
