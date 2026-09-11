extends SceneTree
##
## Headless assertions. No browser, no display: everything the exported page
## runs, run here.
##
##   ./test.sh                 the suite
##   ./test.sh --perf          tick cost at 100 animals against the 16.67 ms budget
##   ./test.sh --parity N      the six-seed table against the canvas build
##

const World := preload("res://scripts/world.gd")
const Data := preload("res://scripts/data.gd")
const Energy := preload("res://scripts/energy.gd")
const Batch := preload("res://scripts/batch.gd")
const Rng := preload("res://scripts/rng.gd")
const Gait := preload("res://scripts/gait.gd")
const Field := preload("res://ui/field.gd")
const Meshes := preload("res://scripts/meshes.gd")
const Palette := preload("res://scripts/palette.gd")
const Raster := preload("res://scripts/raster.gd")
const Cam := preload("res://ui/camera.gd")

var _pass := 0
var _fail := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what)


func near(a: float, b: float, tol: float, what: String) -> void:
	ok(absf(a - b) <= tol, "%s (%.12f vs %.12f)" % [what, a, b])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "--perf":
		_perf()
		quit(0)
		return
	if args.size() > 0 and args[0] == "--parity":
		_parity(int(args[1]) if args.size() > 1 else 6)
		quit(0)
		return
	Energy.build()
	_test_rng()
	_test_energy_tables()
	_test_determinism()
	_test_movement()
	_test_terrain()
	_test_candidates()
	_test_outcomes()
	_test_backcompat()
	_test_batch()
	_test_balance()
	_test_facing()
	_test_gait_cycle()
	_test_shader_matches_gait()
	_test_winding()
	_test_obstacle_geometry()
	_test_palette_contrast()
	_test_camera_is_fixed()
	print("%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


##
## The Rng is compared as raw 32-bit generator words against vectors generated
## from node, not as printed decimals: a decimal comparison hides a last-bit
## difference that would eventually separate two runs completely.
##
func _test_rng() -> void:
	var r := Rng.new(12345)
	var want := [4207900869, 1317490944, 2079646450, 3513001552,
		2187978186, 1492380277, 316786230, 3291647763]
	for i in range(want.size()):
		ok(int(r.next() * 4294967296.0) == want[i], "rng word %d for seed 12345" % i)
	var r2 := Rng.new(1)
	for w in [2693262067, 11749833, 2265367787, 4213581821]:
		ok(int(r2.next() * 4294967296.0) == w, "rng word for seed 1")


## The gait tables, against the values the canvas build computes.
func _test_energy_tables() -> void:
	var w_speed := [0.173333333333, 0.293333333333, 1.266666666667, 2.146666666667, 0.0, 0.0]
	var w_cost := [-0.003587500000, -0.003325000000, 0.002416666667, 0.111108333333, 0.0, 0.0]
	var d_speed := [0.173333333333, 0.400000000000, 1.800000000000, 2.080000000000, 0.933333333333, 0.400000000000]
	var d_cost := [-0.000676056338, -0.000154929577, 0.012056338028, 0.111109859155, 0.040000000000, 0.040000000000]
	for g in range(4):
		near(Energy.speed[Energy.WOLF][g], w_speed[g], 1e-11, "wolf speed %d" % g)
		near(Energy.cost[Energy.WOLF][g], w_cost[g], 1e-11, "wolf cost %d" % g)
	for g in range(6):
		near(Energy.speed[Energy.DEER][g], d_speed[g], 1e-11, "deer speed %d" % g)
		near(Energy.cost[Energy.DEER][g], d_cost[g], 1e-11, "deer cost %d" % g)
	near(Energy.field_data(Energy.WOLF).recovery_rate, 0.004608333333, 1e-11, "wolf recovery")
	near(Energy.field_data(Energy.DEER).recovery_rate, 0.001267605634, 1e-11, "deer recovery")

	# monotonicity: sprint > gallop > trot > walk in speed and in cost
	for sp in [Energy.WOLF, Energy.DEER]:
		for i in range(1, Energy.LADDER.size()):
			var lo: int = Energy.LADDER[i - 1]
			var hi: int = Energy.LADDER[i]
			ok(Energy.speed[sp][hi] > Energy.speed[sp][lo], "speed ladder %d>%d" % [hi, lo])
			ok(Energy.cost[sp][hi] > Energy.cost[sp][lo], "cost ladder %d>%d" % [hi, lo])
		ok(Energy.cost[sp][Energy.WALK] < 0.0, "a walk recovers")
		ok(Energy.cost[sp][Energy.TROT] < 0.0, "a trot recovers - the 10-hours-a-day figure")
	# 9 s of top speed: the peak-velocity window, not the 25 s Wingate window
	near(Energy.sustain[Energy.WOLF][Energy.SPRINT], 9.0, 0.5, "wolf sprint window")
	near(Energy.sustain[Energy.DEER][Energy.SPRINT], 9.0, 0.5, "deer sprint window")
	# bound sits off the ladder on purpose (Lingle 2002)
	ok(Energy.speed[Energy.DEER][Energy.BOUND] < Energy.speed[Energy.DEER][Energy.GALLOP],
		"a bound is slower than a gallop")
	ok(Energy.cost[Energy.DEER][Energy.BOUND] > Energy.cost[Energy.DEER][Energy.GALLOP] * 2.5,
		"and several times dearer")
	ok(Energy.speed[Energy.DEER][Energy.STOT] == Energy.speed[Energy.DEER][Energy.TROT],
		"a stot is a display: bound's cost at trot's speed")
	# the field data, not the old 2x rule
	var ratio: float = Energy.speed[Energy.DEER][Energy.SPRINT] / Energy.speed[Energy.WOLF][Energy.SPRINT]
	ok(ratio > 0.9 and ratio < 1.0, "top-speed ratio ~0.93, not 2.0")
	# fatigue
	var s := Energy.field_data(Energy.DEER)
	ok(Energy.fatigue_penalty(1.0, s) == 0.0, "no fatigue on a full tank")
	near(Energy.fatigue_penalty(0.0, s), 0.55, 1e-12, "an empty deer stumbles at 45% speed")
	ok(s.fatigue_threshold == 0.5, "the penalty starts once half the tank is gone")


func _frames_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var fa: Dictionary = a[i]
		var fb: Dictionary = b[i]
		if fa["wolves"].size() != fb["wolves"].size() or fa["deer"].size() != fb["deer"].size():
			return false
		for j in range(fa["wolves"].size()):
			for k in ["x", "y", "h", "gait", "action", "energy"]:
				if fa["wolves"][j][k] != fb["wolves"][j][k]:
					return false
		for j in range(fa["deer"].size()):
			for k in ["x", "y", "h", "gait", "action", "energy", "alive", "escaped"]:
				if fa["deer"][j][k] != fb["deer"][j][k]:
					return false
	return true


func _test_determinism() -> void:
	var a := Data.archetypes()
	var f1 := []
	var f2 := []
	var r1 := World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 42, World.MAX_TICKS, f1)
	var r2 := World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 42, World.MAX_TICKS, f2)
	ok(r1["ticks"] == r2["ticks"] and r1["winner"] == r2["winner"], "same seed, same result")
	ok(_frames_equal(f1, f2), "same seed, identical frame log")
	# an unrelated hunt in between changes nothing
	World.run_hunt(a["attacker"], a["wildcard"], 7, 2, 999)
	var f3 := []
	World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 42, World.MAX_TICKS, f3)
	ok(_frames_equal(f1, f3), "an unrelated hunt in between changes nothing")
	var f4 := []
	World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 43, World.MAX_TICKS, f4)
	ok(not _frames_equal(f1, f4), "a different seed is a different hunt")


func _test_movement() -> void:
	var a := Data.archetypes()
	var deer_steps := 0
	var wolf_steps := 0
	var wolf_holds := 0
	var fatigued := 0
	var margin: float = Energy.speed[Energy.DEER][Energy.SPRINT] + 1.0
	var wolf_e := Energy.field_data(Energy.WOLF)
	var deer_e := World.scale_for_stamina(Energy.field_data(Energy.DEER), 0.5)
	for seed_v in range(8):
		var f := []
		World.run_hunt(a["teamplayer"], a["defender"], 5, 1, seed_v, World.MAX_TICKS, f)
		for i in range(1, f.size()):
			var pd: Dictionary = f[i - 1]["deer"][0]
			var cd: Dictionary = f[i]["deer"][0]
			var in_field := func(e: Dictionary) -> bool:
				return e["x"] > margin and e["x"] < World.FIELD_W - margin \
					and e["y"] > margin and e["y"] < World.FIELD_H - margin
			var near_brush := func(e: Dictionary) -> bool:
				for o: PackedFloat64Array in World.OBSTACLES:
					if e["x"] > o[0] - 26.0 and e["x"] < o[0] + o[2] + 26.0 \
						and e["y"] > o[1] - 26.0 and e["y"] < o[1] + o[3] + 26.0:
						return true
				return false
			if pd["alive"] and not pd["escaped"] and cd["alive"] and not cd["escaped"] \
				and in_field.call(pd) and not near_brush.call(pd):
				var step := sqrt(pow(cd["x"] - pd["x"], 2.0) + pow(cd["y"] - pd["y"], 2.0))
				var want: float = Energy.speed[Energy.DEER][cd["gait"]] * (1.0 - pd["fatigue"])
				ok(absf(step - want) < 1e-9, "deer step at gait %d" % cd["gait"])
				if pd["fatigue"] > 0.0:
					fatigued += 1
				deer_steps += 1
				# and the energy accounting, to the tick
				var wanted: float = pd["energy"] - Energy.cost[Energy.DEER][cd["gait"]] / Energy.TICKS_PER_SEC
				wanted = clampf(wanted, 0.0, deer_e.max_energy)
				ok(absf(cd["energy"] - wanted) < 1e-9, "deer energy after gait %d" % cd["gait"])
			for wi in range(f[i]["wolves"].size()):
				var pw: Dictionary = f[i - 1]["wolves"][wi]
				var cw: Dictionary = f[i]["wolves"][wi]
				if not in_field.call(pw) or near_brush.call(pw):
					continue
				var st := sqrt(pow(cw["x"] - pw["x"], 2.0) + pow(cw["y"] - pw["y"], 2.0))
				if st > 1e-9:
					var wantw: float = Energy.speed[Energy.WOLF][cw["gait"]] * (1.0 - pw["fatigue"])
					ok(absf(st - wantw) < 1e-9, "wolf step at gait %d" % cw["gait"])
					wolf_steps += 1
				else:
					wolf_holds += 1
	ok(deer_steps > 500, "measured many deer steps in flight (%d)" % deer_steps)
	ok(wolf_steps > 500, "measured many wolf steps in flight (%d)" % wolf_steps)
	ok(wolf_holds > 0, "at least one wolf held its post - patience made visible")
	ok(fatigued > 0, "at least one step taken by a fatigued animal")
	ok(wolf_e.max_energy == 1.0, "wolf tank")


func _test_terrain() -> void:
	var a := Data.archetypes()
	var deer_in_brush := 0
	for seed_v in range(40):
		var f := []
		World.run_hunt(a["attacker"], a["opportunist"], 5, 1, seed_v, World.MAX_TICKS, f)
		for fr in f:
			for w in fr["wolves"]:
				ok(not World.in_brush(w["x"], w["y"]), "a wolf is never inside the deadfall")
			for d in fr["deer"]:
				if not d["alive"] or d["escaped"]:
					continue
				if World.in_brush(d["x"], d["y"]):
					ok(d["gait"] == Energy.BOUND, "only a bounding deer is inside the deadfall")
					deer_in_brush += 1
			for e in fr["wolves"] + fr["deer"]:
				ok(e["x"] >= 0.0 and e["x"] <= World.FIELD_W and e["y"] >= 0.0 and e["y"] <= World.FIELD_H,
					"everything stays inside the field")
	ok(deer_in_brush > 0, "at least one deer bounded through a patch (%d ticks)" % deer_in_brush)


func _test_candidates() -> void:
	var p := Data.Personality.make("t", {})
	var full := Data.wolf_candidates(p, 1.0, true, 1.0, 1.0, 0.0, 0.0, 0.0, World.T_CLOSE_IN)
	var empty := Data.wolf_candidates(p, 1.0, true, 0.0, 1.0, 0.0, 0.0, 0.0, World.T_CLOSE_IN)
	var has := func(c, g: int) -> bool:
		for i in range(c.gaits.size()):
			if c.gaits[i] == g:
				return true
		return false
	ok(has.call(full, Energy.SPRINT), "a fresh wolf can sprint")
	ok(not has.call(empty, Energy.SPRINT), "an empty wolf cannot")
	var fresh := Data.deer_candidates(p, 1.0, 1.0, 1.0, 1.0, 0.0)
	var spent := Data.deer_candidates(p, 1.0, 0.0, 1.0, 1.0, 0.0)
	for g in [Energy.SPRINT, Energy.BOUND, Energy.STOT]:
		ok(has.call(fresh, g), "a fresh deer can use gait %d" % g)
		ok(not has.call(spent, g), "an empty deer cannot use gait %d" % g)
	var open_ground := Data.deer_candidates(p, 0.4, 1.0, 0.0, 0.0, 0.0)
	var has_act := func(c, act: int) -> bool:
		for i in range(c.acts.size()):
			if c.acts[i] == act:
				return true
		return false
	ok(not has_act.call(open_ground, Data.BOUND), "no bound without deadfall to bound over")
	ok(not has_act.call(open_ground, Data.STOT), "no stot without a predator far enough off")
	# every candidate list is still a valid decide() input
	ok(full.offsets.size() == full.bases.size() + 1, "offsets line up with bases")
	ok(full.offsets[full.offsets.size() - 1] == full.trait_vals.size(), "offsets cover the trait list")


func _test_outcomes() -> void:
	var a := Data.archetypes()
	var escapes := 0
	var catches := 0
	var capped := 0
	var gaits := {}
	for seed_v in range(60):
		var f := []
		var r := World.run_hunt(a["teamplayer"], a["defender"], 5, 1, seed_v, World.MAX_TICKS, f)
		if r["capped"]:
			capped += 1
			continue
		gaits[r["decided_by"]] = true
		var last: Dictionary = f[f.size() - 1]
		if r["winner"] == "deer":
			escapes += 1
			ok(last["deer"][0]["escaped"], "a deer win is a recorded escape")
			ok(last["deer"][0]["x"] <= World.GOAL_X, "an escaped deer is at the goal line")
			ok(r["decided_by"].begins_with("deer "), "decided_by names the deer's gait")
		else:
			catches += 1
			ok(not last["deer"][0]["alive"], "a wolf win is a recorded catch")
			ok(r["decided_by"].begins_with("wolf "), "decided_by names the wolf's gait")
			var ev: Dictionary = last["caught"][0]
			var w: Dictionary = last["wolves"][ev["wolf"]]
			var d: Dictionary = last["deer"][ev["deer"]]
			var dist := sqrt(pow(w["x"] - d["x"], 2.0) + pow(w["y"] - d["y"], 2.0))
			ok(dist <= World.TOUCH_R + 1e-9, "a catch only happens inside the touch radius")
		ok(r["ticks"] == f.size(), "tick count matches the frame log")
		ok(r["chase_ticks"] > 0 and r["chase_ticks"] <= r["ticks"], "the chase clock ran")
	ok(escapes > 0 and catches > 0, "both win conditions fire (%d escapes, %d catches)" % [escapes, catches])
	ok(gaits.size() >= 2, "more than one deciding gait")
	ok(float(capped) / 60.0 < 0.10, "the backstop is a backstop (%d of 60)" % capped)
	# the cap counts as a deer win
	var rc := World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 7, 3)
	ok(rc["capped"] and rc["winner"] == "deer" and rc["ticks"] == 3, "the tick cap is a deer win")


func _test_backcompat() -> void:
	# A v0.4 personality carries only the core six. Every property this build
	# added must default to 0.5 through the same lookup, so writing them out
	# explicitly must change nothing.
	var bare := Data.Personality.make("v04", {"aggression": 0.4, "cooperation": 0.95, "focus": 0.6})
	var explicit := Data.Personality.make("v04", {"aggression": 0.4, "cooperation": 0.95, "focus": 0.6,
		"persistence": 0.5, "cohesion": 0.5})
	var bare_d := Data.Personality.make("v04d", {"aggression": 0.2, "caution": 0.9, "risk": 0.2, "patience": 0.8})
	var exp_d := Data.Personality.make("v04d", {"aggression": 0.2, "caution": 0.9, "risk": 0.2, "patience": 0.8,
		"vigilance": 0.5, "panic": 0.5, "herdCohesion": 0.5, "stamina": 0.5})
	for seed_v in [3, 11, 29]:
		var f1 := []
		var f2 := []
		World.run_hunt(bare, bare_d, 5, 1, seed_v, World.MAX_TICKS, f1)
		World.run_hunt(explicit, exp_d, 5, 1, seed_v, World.MAX_TICKS, f2)
		ok(_frames_equal(f1, f2), "the new properties default to 0.5 (seed %d)" % seed_v)


func _test_batch() -> void:
	var a := Data.archetypes()
	var whole := Batch.run_series(a["teamplayer"], a["defender"], 5, 1, 40, 900)
	var sliced := Batch.Stats.new()
	var i := 0
	while i < 40:
		Batch.run_slice(sliced, a["teamplayer"], a["defender"], 5, 1, i, mini(i + 7, 40), 900)
		i += 7
	ok(whole.deer_wins == sliced.deer_wins and whole.ticks == sliced.ticks,
		"a sliced batch equals a single-pass one")
	# the sliders bite
	var cfg := {"wolf": Energy.field_data(Energy.WOLF), "deer": Energy.field_data(Energy.DEER)}
	cfg["deer"].max_energy = 0.15
	var starved := Batch.run_series(a["teamplayer"], a["defender"], 5, 1, 60, 9600, cfg)
	var base := Batch.run_series(a["teamplayer"], a["defender"], 5, 1, 60, 9600)
	ok(starved.kill_rate() > base.kill_rate(),
		"a starved deer is caught more (%.2f vs %.2f)" % [starved.kill_rate(), base.kill_rate()])


func _test_balance() -> void:
	var a := Data.archetypes()
	var s := Batch.run_series(a["teamplayer"], a["defender"], 5, 1, 150, 900)
	ok(s.deer_win_rate() >= 0.50 and s.deer_win_rate() <= 0.90,
		"the default 5v1 lands in the band (%.3f)" % s.deer_win_rate())
	# stamina is the vulnerable-individual dial
	var weak := Data.Personality.make("weak", {"aggression": 0.2, "caution": 0.9, "risk": 0.2,
		"patience": 0.8, "stamina": 0.0})
	var strong := Data.Personality.make("strong", {"aggression": 0.2, "caution": 0.9, "risk": 0.2,
		"patience": 0.8, "stamina": 1.0})
	var kw := Batch.run_series(a["teamplayer"], weak, 5, 1, 120, 8500).kill_rate()
	var ks := Batch.run_series(a["teamplayer"], strong, 5, 1, 120, 8500).kill_rate()
	ok(kw > ks, "a weak deer is caught more often (%.2f vs %.2f)" % [kw, ks])


##
## Every animal faces the way it is going.
##
## This is the regression lock on the "deer and wolves run backwards" report.
## It is asserted twice, because the two statements fail differently:
##
##   1. Against the heading, exactly. `facing_basis(h)` must carry the mesh's
##      own forward (-Z, see `meshes.gd`) onto `travel_dir(h)`. A sign error in
##      the basis shows up here at 1e-12, whatever the simulation is doing.
##   2. Against the travel actually recorded, over a real hunt — the > 0.9 dot the
##      handoff asks for, over every moving animal in every frame of a five-wolf
##      chase.
##
##      Note the frame a heading belongs to. `world.gd` turns, then steps, then
##      records — so the `h` stored in frame N is the heading the animal travelled
##      on to REACH frame N, and the step to compare it against is the one out of
##      frame N-1. That is also why the renderer is right to point frame N's
##      animal along frame N's `h`: it is the direction it just came in on.
##
##      One class of tick is held out, and it is worth being precise about why.
##      `route_around` is a hard push-out: a step that lands inside a deadfall
##      patch is shoved back out along the patch's normal, and an animal grazing
##      an edge is therefore displaced sideways, or briefly backwards, while still
##      heading where it meant to go. The same goes for the field-edge clamp.
##      About 5% of ticks are in contact like that, and on the rest the dot is
##      exactly 1. So: contact ticks are excluded from the worst case and the
##      mean is asserted over everything, contact included — a facing that flips
##      cannot hide behind the exclusion, because it would take the mean with it.
##
func _test_facing() -> void:
	for i in range(24):
		var h := -PI + TAU * float(i) / 24.0
		var fwd: Vector3 = Field.facing_basis(h) * Vector3.FORWARD
		var want: Vector3 = Field.travel_dir(h)
		near(fwd.dot(want), 1.0, 1e-6, "mesh forward is the travel direction at h=%.3f" % h)
		near((Field.facing_basis(h) * Vector3.UP).dot(Vector3.UP), 1.0, 1e-6,
			"the animal stays upright at h=%.3f" % h)

	Energy.build()
	var a := Data.archetypes()
	var frames: Array = []
	World.run_hunt(a["teamplayer"], a["defender"], 5, 1, 7, 1200, frames)
	ok(frames.size() > 60, "the chase recorded frames to check (%d)" % frames.size())

	var worst := 1.0
	var total := 0.0
	var checked := 0
	var contact := 0
	for i in range(frames.size() - 1):
		for key: String in ["wolves", "deer"]:
			var now: Array = frames[i][key]
			var next: Array = frames[i + 1][key]
			var r: float = World.WOLF_R if key == "wolves" else World.DEER_R
			for j in range(now.size()):
				var e: Dictionary = next[j]
				if key == "deer" and (e["escaped"] or not e["alive"]):
					continue
				# world space: sim x -> +X, sim y -> +Z (field.gd's `M` cancels)
				var d := Vector3(e["x"] - now[j]["x"], 0.0, e["y"] - now[j]["y"])
				if d.length() < 0.05:
					continue          # standing still has no direction to face
				var fwd: Vector3 = Field.facing_basis(e["h"]) * Vector3.FORWARD
				var dot := fwd.dot(d.normalized())
				checked += 1
				total += dot
				if _shoved(e["x"], e["y"], r) or _shoved(now[j]["x"], now[j]["y"], r):
					contact += 1
				else:
					worst = minf(worst, dot)
	ok(checked > 2000, "checked a real number of moving animals (%d)" % checked)
	ok(contact < checked / 8, "the deadfall push-out is a minority of ticks (%d/%d)" % [contact, checked])
	ok(worst > 0.9, "body-forward . velocity stays above 0.9 (worst %.4f)" % worst)
	ok(worst > 0.999, "and clear of the deadfall it is exact (worst %.6f)" % worst)
	ok(total / float(checked) > 0.95,
		"the mean over every tick, push-out included, is %.5f" % (total / float(checked)))


## True where `route_around` or the field-edge clamp can displace a step off its
## heading: within a body radius of a deadfall patch, or against a wall.
func _shoved(x: float, y: float, r: float) -> bool:
	if x < 1.0 or y < 1.0 or x > World.FIELD_W - 1.0 or y > World.FIELD_H - 1.0:
		return true
	for o: PackedFloat64Array in World.OBSTACLES:
		var cx := clampf(x, o[0], o[0] + o[2])
		var cy := clampf(y, o[1], o[1] + o[3])
		if (x - cx) * (x - cx) + (y - cy) * (y - cy) < (r + 1.0) * (r + 1.0):
			return true
	return false


##
## The leg cycle is not mirrored: a foot lifts while it swings forward.
##
## Forward is -Z. The lift is `max(0, sin(ph*TAU))`, so it is non-zero exactly
## on the first half of the cycle; over that half the foot must also be moving
## forward of where it rests. The shipped `+=` had it the other way round — the
## foot picked up on the back-swing and skated forward on the floor.
##
func _test_gait_cycle() -> void:
	var foot := Vector2(1.0, 0.0)             # uv2: full swing weight, leg 0
	var custom := Color(0.0, 1.0, 2.0, 0.0)   # phase 0, amplitude 1, gallop
	var lifted_forward := 0
	var planted := 0
	for i in range(32):
		var ph := float(i) / 32.0
		custom.r = ph
		var v: Vector3 = Gait.displace(Vector3.ZERO, foot, custom)
		if v.y > 1e-6:
			ok(v.z < 0.0, "a lifted foot is forward of the hip at ph=%.3f" % ph)
			lifted_forward += 1
		elif absf(v.z) > 1e-6:
			ok(v.z > 0.0, "a planted foot travels aft at ph=%.3f" % ph)
			planted += 1
	ok(lifted_forward >= 14, "the swing phase is about half the cycle (%d/32)" % lifted_forward)
	ok(planted >= 14, "the stance phase is about half the cycle (%d/32)" % planted)

	# the four legs are spread across the cycle, not stepping in unison, on any
	# gait but the bound
	for pattern in range(3):
		var seen := {}
		for leg in range(4):
			# 0.15 through the stride, not 0: a trot's two diagonal pairs are half
			# a cycle apart, and at phase 0 both halves sit on a zero of the sine
			var v: Vector3 = Gait.displace(Vector3.ZERO, Vector2(1.0, float(leg) / 4.0),
				Color(0.15, 1.0, float(pattern), 0.0))
			seen[snappedf(v.z, 0.0001)] = true
		ok(seen.size() >= 2, "pattern %d does not put all four feet in one place" % pattern)

	# the bound arc peaks mid-stride and touches down at both ends
	for gait in [4, 5]:
		var air := func(ph: float) -> float:
			return Field.AIR[gait] * maxf(0.0, sin(fposmod(ph, 1.0) * PI))
		near(air.call(0.0), 0.0, 1e-9, "gait %d starts the stride on the ground" % gait)
		near(air.call(0.999), 0.0, 0.01, "gait %d lands by the end of the stride" % gait)
		ok(air.call(0.5) > air.call(0.25) and air.call(0.5) > air.call(0.75),
			"gait %d peaks in the middle of the stride" % gait)


##
## `scripts/gait.gd` and `ui/animals.gdshader` say the same thing.
##
## The run cycle has to live in the vertex shader to stay at two draw calls, and
## nothing headless can run GLSL — so `gait.gd` mirrors it and everything above
## tests `gait.gd`. That is only worth anything while the two agree, so: read the
## shader and check the three displacement lines are still the ones mirrored. It
## is a text match on purpose. If someone edits the shader, this fails and they
## come here.
##
func _test_shader_matches_gait() -> void:
	var f := FileAccess.open("res://ui/animals.gdshader", FileAccess.READ)
	ok(f != null, "the shader source is readable")
	if f == null:
		return
	var src := f.get_as_text()
	for line in [
			"VERTEX.z -= weight * swing;",
			"VERTEX.y += weight * max(0.0, sin(ph * TAU)) * INSTANCE_CUSTOM.y * 0.22;",
			"VERTEX.z += (1.0 - weight) * sign(VERTEX.z) * flex;",
			"VERTEX.y += (1.0 - weight) * flex * 0.35;",
			"float swing = sin(ph * TAU) * INSTANCE_CUSTOM.y;",
			"float ph = fract(INSTANCE_CUSTOM.x + off);"]:
		ok(src.contains(line), "the shader still has `%s` (mirrored in gait.gd)" % line)
	for row in Gait.FOOTFALL:
		var parts := PackedStringArray()
		for v: float in row:
			parts.push_back(_glsl_float(v))
		var want := ", ".join(parts)
		ok(src.contains(want), "the shader's FOOTFALL still has the row [%s]" % want)


## `0.5` the way GLSL source writes it, not the way `%f` does.
##
## The winding, against the engine's own `BoxMesh`.
##
## This is the assertion the deadfall bug needed and did not have. Godot's
## front face is the CLOCKWISE winding, so a correctly wound triangle has
## `(p1-p0) x (p2-p0)` pointing AWAY from its own vertex normal. `Meshes._box`
## had it pointing along the normal — every box in the project was inside-out —
## and `StandardMaterial3D`'s default `cull_back` threw the outward faces away,
## leaving black interiors that changed with the view. The animals survived it
## only because their shader is `cull_disabled`.
##
## Rather than restate the convention, ask the engine for it: build a `BoxMesh`,
## measure its winding, and require ours to match.
##
func _test_winding() -> void:
	var reference := _winding_sign(BoxMesh.new().get_mesh_arrays())
	ok(reference == -1, "BoxMesh is wound against its normals (got %d)" % reference)
	for m: Dictionary in [
			{"n": "wolf", "m": Meshes.build(false)},
			{"n": "deer", "m": Meshes.build(true)},
			{"n": "brush", "m": Meshes.brush(24.0, 18.0, 0)}]:
		var mesh: ArrayMesh = m["m"]
		for si in range(mesh.get_surface_count()):
			ok(_winding_sign(mesh.surface_get_arrays(si)) == reference,
				"%s surface %d winds like BoxMesh" % [m["n"], si])

	##
	## And the other half: the rasteriser that draws the headless PNGs has to
	## cull the same faces the GPU culls, or the picture proves nothing. Project
	## a BoxMesh and check that the triangles whose normals face the eye are
	## exactly the ones with `Raster.FRONT_SIGN` screen area.
	##
	var arrays := BoxMesh.new().get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var eye := Vector3(6, 4, 7)
	var inv := Raster.view(eye, Vector3.ZERO)
	var agree := 0
	for t in range(0, idx.size(), 3):
		var p: Array = []
		for k in range(3):
			var c: Vector3 = inv * v[idx[t + k]]
			p.push_back(Vector2(c.x / -c.z, -c.y / -c.z))
		var area: float = (p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[1].y - p[0].y) * (p[2].x - p[0].x)
		var toward: bool = nn[idx[t]].dot(eye - v[idx[t]]) > 0.0
		if toward == (area * Raster.FRONT_SIGN > 0.0):
			agree += 1
	ok(agree == idx.size() / 3,
		"Raster.FRONT_SIGN culls what the GPU culls (%d/%d)" % [agree, idx.size() / 3])


## -1 if `(p1-p0) x (p2-p0)` opposes the vertex normal on every triangle,
## +1 if it agrees on every one, 0 if the surface is inconsistent.
func _winding_sign(arrays: Array) -> int:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var seen := 0
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var face: Vector3 = (v[idx[t + 1]] - v[a]).cross(v[idx[t + 2]] - v[a])
		if face.length() < 1e-9:
			continue
		var sgn := 1 if face.normalized().dot(n[a]) > 0.0 else -1
		if seen == 0:
			seen = sgn
		elif seen != sgn:
			return 0
	return seen


##
## The second cause of the flicker: the slab used to sit with its underside at
## exactly y = 0, coplanar with the ground plane, and coplanar surfaces 200 m
## from a camera are a depth-precision coin toss that resolves differently as
## the view moves. It has to be clear of the floor, and it has to have a top
## cap on its own surface so the top edge can be painted lighter than the sides.
##
func _test_obstacle_geometry() -> void:
	var mesh := Meshes.brush(24.0, 18.0, 0)
	ok(mesh.get_surface_count() == 3, "brush has sides, cap and trunks as separate surfaces")
	var aabb := mesh.get_aabb()
	ok(aabb.position.y > 0.02, "the slab is clear of the ground plane (base y = %.3f)" % aabb.position.y)
	ok(Meshes.BASE_Y > 0.0, "Meshes.BASE_Y is positive")
	# the cap is a flat lid at the top of the slab and nothing else
	var cap := mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var flat := true
	for p in cap:
		if absf(p.y - (Meshes.BASE_Y + Meshes.SLAB_H)) > 1e-5:
			flat = false
	ok(flat, "surface 1 is the top cap, all at one height")


##
## Legibility, as a number. Every element a viewer has to pick out has to clear
## WCAG 3:1 — the bar for non-text graphical objects — against the ground it
## sits on, at every fatigue level it can reach.
##
func _test_palette_contrast() -> void:
	var bar := 3.0
	for e: Array in [
			["wolf", Palette.WOLF], ["wolf spent", Palette.WOLF_SPENT],
			["deer", Palette.DEER], ["deer spent", Palette.DEER_SPENT],
			["deadfall", Palette.OBSTACLE], ["deadfall top", Palette.OBSTACLE_TOP],
			["goal strip", Palette.GOAL]]:
		var k: float = Palette.contrast(e[1], Palette.GROUND)
		ok(k >= bar, "%s is %.2f:1 against the ground (bar %.1f)" % [e[0], k, bar])

	# the whole fatigue ramp, not just its ends — `coat` must never dip under
	for i in range(21):
		var t := float(i) / 20.0
		var w: float = Palette.contrast(Palette.coat(Palette.WOLF, Palette.WOLF_SPENT, t), Palette.GROUND)
		var d: float = Palette.contrast(Palette.coat(Palette.DEER, Palette.DEER_SPENT, t), Palette.GROUND)
		ok(w >= bar, "wolf at fatigue %.2f is %.2f:1" % [t, w])
		ok(d >= bar, "deer at fatigue %.2f is %.2f:1" % [t, d])

	# and the two species have to be separable from each other, on hue if not
	# on luminance — a grey wolf and a tan deer, not two browns
	var hw := Palette.WOLF.h
	var hd := Palette.DEER.h
	ok(Palette.WOLF.s < 0.12, "the wolf is neutral (saturation %.3f)" % Palette.WOLF.s)
	ok(Palette.DEER.s > 0.45, "the deer is warm (saturation %.3f)" % Palette.DEER.s)
	ok(absf(hw - hd) > 0.02 or Palette.DEER.s - Palette.WOLF.s > 0.3,
		"wolf and deer separate on saturation/hue")

	# the constants file is the only place colours live: no literal Color(...)
	# with three or four numbers anywhere in the draw code
	for f: String in ["ui/field.gd", "ui/main.gd", "ui/camera.gd"]:
		var src := FileAccess.get_file_as_string("res://" + f)
		var re := RegEx.create_from_string("Color\\(\\s*[0-9]")
		var hits := []
		for m in re.search_all(src):
			var line := src.count("\n", 0, m.get_start()) + 1
			# the MultiMesh custom-data channel is a Color by type, not by
			# intent; so is the scrim, which is pure black at an alpha
			var ctx := src.substr(maxi(0, m.get_start() - 120), 200)
			if ctx.contains("set_instance_custom_data") or ctx.contains("_scrim.color"):
				continue
			hits.push_back(line)
		ok(hits.is_empty(), "%s has no literal colours (lines %s)" % [f, str(hits)])


##
## The camera is fixed at 45 degrees and there is no way to change that.
##
## The brief said "remove orbit entirely, don't just hide it", so the assertion
## is structural rather than behavioural: the elevation and heading are `const`,
## the script exposes no orbit entry point, and a synthetic one-finger drag pans
## instead of spinning.
##
func _test_camera_is_fixed() -> void:
	var src := FileAccess.get_file_as_string("res://ui/camera.gd")
	ok(src.contains("const PITCH"), "pitch is a constant")
	ok(src.contains("const YAW"), "yaw is a constant")
	ok(not src.contains("func _orbit"), "there is no orbit handler")
	ok(not src.contains("var yaw"), "yaw is not a variable")
	ok(not src.contains("var pitch"), "pitch is not a variable")
	near(Cam.PITCH, deg_to_rad(45.0), 1e-9, "the camera sits at 45 degrees")

	var cam: Camera3D = Cam.new()
	cam.setup(Vector3(112.0, 0.0, 65.0), 150.0)
	var before: Vector3 = cam.position - cam.target
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(400, 300)
	drag.relative = Vector2(60, -40)
	cam._unhandled_input(drag)
	var after: Vector3 = cam.position - cam.target
	near(before.angle_to(after), 0.0, 1e-6, "a one-finger drag does not rotate the view")
	ok(cam.target.distance_to(Vector3(112.0, 0.0, 65.0)) > 0.01, "a one-finger drag pans")
	cam.free()


func _glsl_float(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _perf() -> void:
	Energy.build()
	var a := Data.archetypes()
	# 100 animals: the handoff's target. 8 wolves is the UI's maximum, so the
	# count is made up on the deer side for the measurement.
	for counts in [[5, 1], [50, 50], [80, 20]]:
		var t0 := Time.get_ticks_usec()
		var ticks := 0
		for seed_v in range(3):
			var r := World.run_hunt(a["teamplayer"], a["defender"], counts[0], counts[1], seed_v, 900)
			ticks += r["ticks"]
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		print("  %3d wolves + %3d deer: %7.3f ms/tick over %d ticks (16.67 ms budget)"
			% [counts[0], counts[1], dt / float(maxi(ticks, 1)), ticks])


func _parity(n: int) -> void:
	Energy.build()
	var a := Data.archetypes()
	var s := Batch.run_series(a["teamplayer"], a["defender"], 5, 1, n, 20260910)
	var wg := s.gait_share(s.wolf_gait)
	var dg := s.gait_share(s.deer_gait)
	print("trials=%d seedBase=20260910 teamplayer vs defender 5v1" % n)
	print("deer_win_rate %.4f" % s.deer_win_rate())
	print("kill_rate %.4f" % s.kill_rate())
	print("mean_ticks %.2f" % (float(s.ticks) / float(n)))
	print("mean_chase_ticks %.2f" % (float(s.chase) / float(n)))
	print("mean_deer_energy %.4f" % (s.deer_e / float(n)))
	print("mean_wolf_energy %.4f" % (s.wolf_e / float(n)))
	print("wolf_gait_share walk=%.4f trot=%.4f gallop=%.4f sprint=%.4f" % [wg[0], wg[1], wg[2], wg[3]])
	print("deer_gait_share walk=%.4f trot=%.4f gallop=%.4f sprint=%.4f bound=%.4f stot=%.4f"
		% [dg[0], dg[1], dg[2], dg[3], dg[4], dg[5]])
	var keys := s.decided.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.push_back("%s=%d" % [k, s.decided[k]])
	print("decided_by " + " ".join(parts))
