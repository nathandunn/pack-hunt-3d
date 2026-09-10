extends RefCounted
##
## Pack Hunt v0.5 in GDScript — the simulation.
##
## A port of `pack-hunt/src/sim.ts`, formula for formula, plus the sim-core
## pieces it stands on: the mulberry32 Rng (`rng.gd`), `utilityDecide`
## (`engine.gd`) and the two geometry primitives it uses (`seg_rect_t` and
## `push_out_circle`, below). The canvas build is the source of truth; where
## the two differ the difference is recorded in the README under "Formula
## divergences", and there is nothing in this file that was invented here.
##
## The game: the deer spawns near the RIGHT edge and must reach the LEFT edge.
## Wolves spawn as a loose cordon between it and the goal. Reaching the left
## edge is a deer win; a wolf getting within TOUCH_R is a wolf win. MAX_TICKS
## is an infinite-loop backstop and counts as a deer win.
##
## The energy model is in `energy.gd` and the derivation in
## `specs/pack-hunt-energy.md`. The short version: SPEC v0.4 fixed the deer at
## exactly 2x wolf speed, the field data does not support that (a grey wolf
## sprints at 58-61 km/h and a white-tailed deer at 56), and the real asymmetry
## is cost rather than pace — a wolf's trot is free, a deer's escape gait is
## not, and a deer refills its tank 3.6 times slower.
##

const Rng := preload("res://scripts/rng.gd")
const Energy := preload("res://scripts/energy.gd")
const Engine_ := preload("res://scripts/engine.gd")
const Data := preload("res://scripts/data.gd")

const FIELD_W := 900.0
const FIELD_H := 520.0
const TOUCH_R := 12.0
const GOAL_X := 6.0
const MAX_TICKS := 3000
const WOLF_R := 9.0
const DEER_R := 9.0
const TAU_ := TAU

##
## Deadfall and brush, as [x, y, w, h]. A deer at the `bound` gait crosses
## these at full speed (and 25% faster inside one); every other gait, and every
## wolf, goes around. Static — deriving them from the Rng would add draws and
## break the stream. Identical to the canvas build's `OBSTACLES`.
##
static var OBSTACLES: Array[PackedFloat64Array] = [
	PackedFloat64Array([168.0, 52.0, 112.0, 132.0]),
	PackedFloat64Array([196.0, 318.0, 132.0, 142.0]),
	PackedFloat64Array([430.0, 172.0, 122.0, 150.0]),
	PackedFloat64Array([604.0, 38.0, 100.0, 122.0]),
	PackedFloat64Array([618.0, 352.0, 112.0, 132.0]),
]

## Balance knobs. Same names, same values as the canvas build's `TUNING`.
const T_DEER_SPAWN_X := FIELD_W - 36.0
const T_CORDON_X := 330.0
const T_CORDON_LEAD := 165.0
const T_GUARD_X := 44.0
const T_DEER_TURN := 0.14
const T_WOLF_TURN := 0.34
const T_DEER_DECIDE := 8
const T_WOLF_DECIDE := 8
const T_CORDON_SPACING_MIN := 26.0
const T_CORDON_SPACING_SPAN := 42.0
const T_GAP_NOISE := 55.0
const T_PANIC_BASE := 50.0
const T_PANIC_SPAN := 46.0
const T_PANIC_K := 2.4
const T_REFLEX_R := 40.0
const T_REFLEX_K := 3.0
const T_GAP_BAND := 300.0
const T_DETECT_BASE := 150.0
const T_DETECT_SPAN := 260.0
const T_STOT_DETER_TICKS := 240
const T_BRUSH_LOOK := 190.0
const T_BOUND_BONUS := 1.25
const T_CHASE_ENGAGE := 210.0
const T_CLOSE_IN := 0.40
const T_GIVE_UP_BASE := 450.0
const T_GIVE_UP_SPAN := 900.0
const T_GIVE_UP_FADE := 500.0

const HOLD_EPS := 3.0
const WALL := 34.0


static func clampf_(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


## Signed smallest angle from a to b, in (-PI, PI].
static func ang_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU_)
	if d > PI:
		d -= TAU_
	if d <= -PI:
		d += TAU_
	return d


static func turn_toward(h: float, want: float, rate: float) -> float:
	return h + clampf_(ang_diff(h, want), -rate, rate)


## True when (x,y) is strictly inside one of the brush patches.
static func in_brush(x: float, y: float) -> bool:
	for o: PackedFloat64Array in OBSTACLES:
		if x > o[0] and x < o[0] + o[2] and y > o[1] and y < o[1] + o[3]:
			return true
	return false


## sim-core `segRectT`: first hit parameter of a segment against an AABB, or INF.
static func seg_rect_t(x0: float, y0: float, x1: float, y1: float, o: PackedFloat64Array) -> float:
	var dx := x1 - x0
	var dy := y1 - y0
	var tmin := 0.0
	var tmax := 1.0
	if absf(dx) < 1e-12:
		if x0 < o[0] or x0 > o[0] + o[2]:
			return INF
	else:
		var t1: float = (o[0] - x0) / dx
		var t2: float = (o[0] + o[2] - x0) / dx
		if t1 > t2:
			var s := t1
			t1 = t2
			t2 = s
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return INF
	if absf(dy) < 1e-12:
		if y0 < o[1] or y0 > o[1] + o[3]:
			return INF
	else:
		var t1b: float = (o[1] - y0) / dy
		var t2b: float = (o[1] + o[3] - y0) / dy
		if t1b > t2b:
			var s2 := t1b
			t1b = t2b
			t2b = s2
		tmin = maxf(tmin, t1b)
		tmax = minf(tmax, t2b)
		if tmin > tmax:
			return INF
	return tmin


##
## Route a straight line around the deadfall.
##
## The target is moved, not the body. Pushing a body out of a patch and leaving
## it there pins it against the face forever, because its target is still on
## the far side and it walks back into the same wall every tick — measured, a
## deer spent 2800 of 3000 ticks parked one body radius off the east face of
## the middle patch. Only corners the animal can reach without crossing the
## same patch are candidates; without that filter it picks the far corner,
## walks back into the face, and oscillates.
##
##
## Results come back through module-level `OUT_X` / `OUT_Y` rather than a
## Vector2, and that is not a style choice. Godot's `Vector2` is float32 in a
## standard build; the simulation is float64 throughout, and routing a position
## through a Vector2 silently rounded it to seven digits. Measured, that put
## every deer step 6.5e-7 units off the gait speed it was supposed to be — a
## divergence from the canvas build that had nothing to do with libm and would
## have grown into a different battle. sim-core's own geometry returns through
## module-scoped outputs for a different reason (allocation), but the shape is
## the same.
##
static var OUT_X := 0.0
static var OUT_Y := 0.0


static func detour(x: float, y: float, tx: float, ty: float, r: float) -> void:
	var block := PackedFloat64Array()
	var best_t := INF
	for o: PackedFloat64Array in OBSTACLES:
		var t := seg_rect_t(x, y, tx, ty, o)
		if t < best_t:
			best_t = t
			block = o
	if block.is_empty() or is_inf(best_t):
		OUT_X = tx
		OUT_Y = ty
		return
	var m := r + 7.0
	var bx := tx
	var by := ty
	var best_d := INF
	var any_d := INF
	var ax := tx
	var ay := ty
	for cx: float in [block[0] - m, block[0] + block[2] + m]:
		for cy: float in [block[1] - m, block[1] + block[3] + m]:
			var px := clampf_(cx, 2.0, FIELD_W - 2.0)
			var py := clampf_(cy, 2.0, FIELD_H - 2.0)
			var d := sqrt((px - x) * (px - x) + (py - y) * (py - y)) \
				+ sqrt((tx - px) * (tx - px) + (ty - py) * (ty - py))
			if d < any_d:
				any_d = d
				ax = px
				ay = py
			if not is_inf(seg_rect_t(x, y, px, py, block)):
				continue
			if d < best_d:
				best_d = d
				bx = px
				by = py
	OUT_X = ax if is_inf(best_d) else bx
	OUT_Y = ay if is_inf(best_d) else by


## sim-core `pushOutCircle`, applied to every patch in turn. The backstop.
static func route_around(x: float, y: float, r: float) -> void:
	var px := x
	var py := y
	for o: PackedFloat64Array in OBSTACLES:
		var cx: float = clampf_(px, o[0], o[0] + o[2])
		var cy: float = clampf_(py, o[1], o[1] + o[3])
		var dx := px - cx
		var dy := py - cy
		var d2 := dx * dx + dy * dy
		if d2 >= r * r:
			continue
		if d2 > 1e-9:
			var d := sqrt(d2)
			var k := (r - d) / d + 1e-6
			px = px + dx * k
			py = py + dy * k
			continue
		var left: float = px - o[0]
		var right: float = o[0] + o[2] - px
		var top: float = py - o[1]
		var bot: float = o[1] + o[3] - py
		var mn: float = min(min(left, right), min(top, bot))
		if mn == left:
			px = o[0] - r - 1e-6
		elif mn == right:
			px = o[0] + o[2] + r + 1e-6
		elif mn == top:
			py = o[1] - r - 1e-6
		else:
			py = o[1] + o[3] + r + 1e-6
	OUT_X = px
	OUT_Y = py


##
## Closed-form intercept: earliest t where a pursuer at (wx,wy) at speed s can
## meet a target at (dx,dy) with velocity (vx,vy). Returns Vector2(INF, INF)
## when no solution exists within t_cap.
##
static func intercept_point(wx: float, wy: float, dx: float, dy: float,
		vx: float, vy: float, s: float, t_cap: float) -> bool:
	var rx := dx - wx
	var ry := dy - wy
	var a := vx * vx + vy * vy - s * s
	var b := 2.0 * (rx * vx + ry * vy)
	var c := rx * rx + ry * ry
	var t := NAN
	if absf(a) < 1e-9:
		if absf(b) > 1e-9:
			var tt := -c / b
			if tt > 1e-6:
				t = tt
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			if t1 > 1e-6:
				t = t1
			elif t2 > 1e-6:
				t = t2
	if is_nan(t) or t > t_cap:
		return false
	OUT_X = dx + vx * t
	OUT_Y = dy + vy * t
	return true


##
## How squarely a brush patch sits between the deer and the goal, 0..1.
## Sampled along the line of travel rather than by rect intersection, so a
## patch off to one side scores low even when it is close.
##
static func brush_on_line(x: float, y: float, look: float) -> float:
	var best := 0.0
	for i in range(1, 7):
		var t := float(i) / 6.0
		var sx := x - look * t
		if sx < GOAL_X:
			break
		if in_brush(sx, y):
			best = maxf(best, 1.0 - (t - 0.2) * 0.5)
	return clampf_(best, 0.0, 1.0)


## Corridors between the wolves ahead of the deer, plus the two wall gaps.
static func read_gaps(ys: Array) -> Array:
	var sorted := ys.duplicate()
	sorted.sort()
	sorted.push_back(FIELD_H)
	var gaps := []
	var prev := 0.0
	for y in sorted:
		gaps.push_back([(prev + y) / 2.0, (y - prev) / 2.0])
		prev = y
	return gaps


## `stamina` is the vulnerable-individual dial: it scales tank and recovery.
static func scale_for_stamina(base: Energy.Settings, stamina: float) -> Energy.Settings:
	var k := 0.65 + 0.7 * stamina
	var s := base.duplicate_settings()
	s.max_energy = base.max_energy * k
	s.recovery_rate = base.recovery_rate * k
	return s


##
## Run one hunt. `record` is an optional Array that gets a frame Dictionary per
## tick; the 3D view renders from those, exactly as the canvas build does.
##
static func run_hunt(wolf_p: Data.Personality, deer_p: Data.Personality, n_wolves: int, n_deer: int, seed_value: int,
		max_ticks: int = MAX_TICKS, record: Array = [], cfg: Dictionary = {}) -> Dictionary:
	Energy.build()
	var rng := Rng.new(seed_value)
	var wolf_e: Energy.Settings = cfg.get("wolf", Energy.field_data(Energy.WOLF))
	var deer_e: Energy.Settings = scale_for_stamina(cfg.get("deer", Energy.field_data(Energy.DEER)),
		deer_p.get_trait("stamina"))
	var persistence: float = wolf_p.get_trait("persistence")
	var vigilance: float = deer_p.get_trait("vigilance")
	var detect_r := T_DETECT_BASE + vigilance * T_DETECT_SPAN

	# Spawn. Two draws per wolf and two per deer, in this order — the stream is
	# the canvas build's, tick for tick.
	var wx := PackedFloat64Array()
	var wy := PackedFloat64Array()
	var wh := PackedFloat64Array()
	var wlane := PackedFloat64Array()
	var wact := PackedInt32Array()
	var wgait := PackedInt32Array()
	var wen := PackedFloat64Array()
	var wdet := PackedInt32Array()
	var wphase := PackedFloat64Array()
	for i in range(n_wolves):
		var lane_y := (float(i) + 0.5) * FIELD_H / float(n_wolves)
		wx.push_back(clampf_(T_CORDON_X + (rng.next() * 2.0 - 1.0) * 26.0, TOUCH_R, FIELD_W - TOUCH_R))
		wy.push_back(clampf_(lane_y + (rng.next() * 2.0 - 1.0) * 24.0, TOUCH_R, FIELD_H - TOUCH_R))
		wh.push_back(0.0)
		wlane.push_back(lane_y)
		wact.push_back(Data.CORDON)
		wgait.push_back(Energy.TROT)
		wen.push_back(wolf_e.max_energy)
		wdet.push_back(0)
		wphase.push_back(0.0)

	var dx_ := PackedFloat64Array()
	var dy_ := PackedFloat64Array()
	var dh := PackedFloat64Array()
	var dalive := []
	var descaped := []
	var dact := PackedInt32Array()
	var dgait := PackedInt32Array()
	var den := PackedFloat64Array()
	var dtx := PackedFloat64Array()
	var dty := PackedFloat64Array()
	var dphase := PackedFloat64Array()
	for i in range(n_deer):
		dx_.push_back(T_DEER_SPAWN_X - rng.next() * 18.0)
		dy_.push_back(FIELD_H * (0.18 + 0.64 * rng.next()))
		dh.push_back(PI)
		dalive.push_back(true)
		descaped.push_back(false)
		dact.push_back(Data.DASH)
		dgait.push_back(Energy.GALLOP)
		den.push_back(deer_e.max_energy)
		dtx.push_back(GOAL_X)
		dty.push_back(dy_[i])
		dphase.push_back(0.0)

	var wolf_gait_ticks := PackedInt32Array()
	wolf_gait_ticks.resize(6)
	var deer_gait_ticks := PackedInt32Array()
	deer_gait_ticks.resize(6)
	var wolf_action_ticks := PackedInt32Array()
	wolf_action_ticks.resize(6)
	var deer_action_ticks := PackedInt32Array()
	deer_action_ticks.resize(6)
	var engaged_at := -1
	var decided_by := "none"

	var tick := 0
	var capped := false

	while true:
		var unresolved := false
		for i in range(n_deer):
			if dalive[i] and not descaped[i]:
				unresolved = true
				break
		if not unresolved:
			break
		if tick >= max_ticks:
			capped = true
			break

		# Which wolf is closest to a live deer — the one paying the most, and
		# therefore the one with a reason to relay (Muro et al. 2011).
		var lead_idx := -1
		var lead_d := INF
		for i in range(n_wolves):
			for j in range(n_deer):
				if not dalive[j] or descaped[j]:
					continue
				var dd := sqrt(pow(dx_[j] - wx[i], 2.0) + pow(dy_[j] - wy[i], 2.0))
				if dd < lead_d:
					lead_d = dd
					lead_idx = i
		if engaged_at < 0 and lead_d <= T_CHASE_ENGAGE:
			engaged_at = tick
		var weary := 0.0
		if engaged_at >= 0:
			weary = clampf_((float(tick - engaged_at) - (T_GIVE_UP_BASE + persistence * T_GIVE_UP_SPAN))
				/ T_GIVE_UP_FADE, 0.0, 1.0)

		# ── wolves ────────────────────────────────────────────────
		for i in range(n_wolves):
			var mark := -1
			var mark_d := INF
			for j in range(n_deer):
				if not dalive[j] or descaped[j]:
					continue
				var dd := sqrt(pow(dx_[j] - wx[i], 2.0) + pow(dy_[j] - wy[i], 2.0))
				if dd < mark_d:
					mark_d = dd
					mark = j
			if mark < 0:
				break
			var ahead := wx[i] < dx_[mark]

			var spacing: float = T_CORDON_SPACING_MIN + wolf_p.get_trait("cooperation") * T_CORDON_SPACING_SPAN
			var line_x0 := clampf_(dx_[mark] - T_CORDON_LEAD, T_GUARD_X, T_CORDON_X)
			var post_y0 := clampf_(dy_[mark] + (float(i) - float(n_wolves - 1) / 2.0) * spacing,
				12.0, FIELD_H - 12.0)
			var post_far := clampf_(sqrt(pow(line_x0 - wx[i], 2.0) + pow(post_y0 - wy[i], 2.0)) / 220.0, 0.0, 1.0)

			if (tick + i * 3) % T_WOLF_DECIDE == 0:
				var near := clampf_(1.0 - mark_d / 260.0, 0.0, 1.0)
				var deter := 0.0
				if wdet[i] > 0:
					deter = (float(wdet[i]) / float(T_STOT_DETER_TICKS)) * (1.0 - persistence)
				var c := Data.wolf_candidates(wolf_p, near, ahead,
					(wen[i] / wolf_e.max_energy) if wolf_e.max_energy > 0.0 else 0.0,
					1.0 if i == lead_idx else 0.0, deter, post_far, weary, T_CLOSE_IN)
				var pick := Engine_.decide(c.bases, c.offsets, c.trait_vals, c.weights,
					wolf_p.randomness, rng)
				wact[i] = c.acts[pick]
				wgait[i] = c.gaits[pick]
			if wdet[i] > 0:
				wdet[i] -= 1

			var mark_speed := Energy.gait_speed(Energy.DEER, dgait[mark], den[mark], deer_e)
			var vx := cos(dh[mark]) * mark_speed
			var vy := sin(dh[mark]) * mark_speed
			var give: float = max(weary, (float(wdet[i]) / float(T_STOT_DETER_TICKS)) * (1.0 - persistence) if wdet[i] > 0 else 0.0)
			var floor_x := T_GUARD_X + give * (T_CORDON_X - T_GUARD_X)
			var line_x := clampf_(dx_[mark] - T_CORDON_LEAD, floor_x, T_CORDON_X)
			var ttl: float = max(0.0, (dx_[mark] - line_x) / max(0.8, -vx))
			var pred_y := clampf_(dy_[mark] + vy * minf(ttl, 50.0), 0.0, FIELD_H)
			var fence_y := clampf_(
				(pred_y + (float(i) - float(n_wolves - 1) / 2.0) * spacing) * (1.0 - weary) + wlane[i] * weary,
				12.0, FIELD_H - 12.0)
			var speed := Energy.gait_speed(Energy.WOLF, wgait[i], wen[i], wolf_e)
			var tx := 0.0
			var ty := 0.0
			match wact[i]:
				Data.CHASE:
					tx = dx_[mark]
					ty = dy_[mark]
				Data.INTERCEPT:
					var t_cap: float = 40.0 + wolf_p.get_trait("risk") * 260.0
					var got := intercept_point(wx[i], wy[i], dx_[mark], dy_[mark], vx, vy, maxf(speed, 1e-6), t_cap)
					if not got:
						var lead_dist: float = 60.0 + wolf_p.get_trait("risk") * 180.0
						tx = maxf(T_GUARD_X, dx_[mark] - lead_dist)
						var tt := (dx_[mark] - tx) / maxf(0.6, -vx)
						ty = clampf_(dy_[mark] + vy * tt, 0.0, FIELD_H)
					else:
						tx = OUT_X
						ty = OUT_Y
				Data.FLANK:
					var away := 0.0
					for j in range(n_wolves):
						if j == i:
							continue
						var ddy := wy[i] - wy[j]
						var dd2 := absf(ddy) + 1e-6
						if dd2 < 150.0:
							away += (ddy / dd2) * (150.0 - dd2)
					var side := 1.0 if away >= 0.0 else -1.0
					tx = maxf(T_GUARD_X, dx_[mark] - 70.0)
					ty = clampf_(dy_[mark] + side * (60.0 + spacing), 10.0, FIELD_H - 10.0)
				Data.RELAY:
					var back: float = min(60.0, sqrt(pow(dx_[mark] - wx[i], 2.0) + pow(dy_[mark] - wy[i], 2.0)))
					var away_a := atan2(wy[i] - dy_[mark], wx[i] - dx_[mark])
					tx = clampf_(wx[i] + cos(away_a) * back, T_GUARD_X, T_CORDON_X)
					ty = clampf_(wy[i] + sin(away_a) * back, 12.0, FIELD_H - 12.0)
				Data.CORDON:
					tx = line_x
					ty = fence_y
				Data.GUARD:
					tx = T_GUARD_X
					ty = clampf_(pred_y + (float(i) - float(n_wolves - 1) / 2.0) * spacing * 0.6, 12.0, FIELD_H - 12.0)

			detour(wx[i], wy[i], tx, ty, WOLF_R)
			tx = OUT_X
			ty = OUT_Y
			var dist_t := sqrt((tx - wx[i]) * (tx - wx[i]) + (ty - wy[i]) * (ty - wy[i]))
			var holding := ((wact[i] == Data.CORDON or wact[i] == Data.GUARD) and dist_t < HOLD_EPS) \
				or (wact[i] == Data.RELAY and mark_d > T_CORDON_LEAD * 0.6)
			if holding:
				pass
			elif dist_t > 1e-9:
				wh[i] = turn_toward(wh[i], atan2(ty - wy[i], tx - wx[i]), T_WOLF_TURN)
				var nx := clampf_(wx[i] + cos(wh[i]) * speed, 0.0, FIELD_W)
				var ny := clampf_(wy[i] + sin(wh[i]) * speed, 0.0, FIELD_H)
				route_around(nx, ny, WOLF_R)
				wx[i] = clampf_(OUT_X, 0.0, FIELD_W)
				wy[i] = clampf_(OUT_Y, 0.0, FIELD_H)
			wen[i] = Energy.step_energy(wen[i], Energy.WOLF, wgait[i], wolf_e, holding)
			wphase[i] += speed
			wolf_gait_ticks[wgait[i]] += 1
			wolf_action_ticks[wact[i]] += 1

		# ── deer ──────────────────────────────────────────────────
		for i in range(n_deer):
			if not dalive[i] or descaped[i]:
				continue
			var near_d := INF
			for j in range(n_wolves):
				near_d = minf(near_d, sqrt(pow(wx[j] - dx_[i], 2.0) + pow(wy[j] - dy_[i], 2.0)))

			var margin: float = 14.0 + deer_p.get_trait("caution") * 46.0
			if (tick + i) % T_DEER_DECIDE == 0:
				var noise: float = (1.0 - deer_p.get_trait("focus")) * T_GAP_NOISE
				var ys := []
				for j in range(n_wolves):
					# draw ALWAYS -> stable rng stream, whatever the filter says
					var y_n := clampf_(wy[j] + (rng.next() * 2.0 - 1.0) * noise, 0.0, FIELD_H)
					if wx[j] < dx_[i] + 30.0 and wx[j] > dx_[i] - T_GAP_BAND:
						ys.push_back(y_n)
				var gaps := read_gaps(ys)
				var dash_gap: Array = gaps[0]
				var dash_score := -INF
				var thread_gap: Array = gaps[0]
				var thread_dev := INF
				var widest := 0.0
				for g in gaps:
					if g[1] > widest:
						widest = g[1]
					var sc: float = min(g[1] - margin, 120.0) - 0.35 * absf(g[0] - dy_[i])
					if sc > dash_score:
						dash_score = sc
						dash_gap = g
					if g[1] > 8.0 and absf(g[0] - dy_[i]) < thread_dev:
						thread_dev = absf(g[0] - dy_[i])
						thread_gap = g
				var edge: Array = gaps[0] if gaps[0][1] >= gaps[gaps.size() - 1][1] else gaps[gaps.size() - 1]
				var jink_sign := -1.0 if rng.next() < 0.5 else 1.0
				var jink_amt := 80.0 + rng.next() * 70.0

				var near := clampf_(1.0 - near_d / 200.0, 0.0, 1.0)
				var far_threat := 0.0
				if near_d < detect_r and near_d > detect_r * 0.42:
					far_threat = clampf_((near_d - detect_r * 0.42) / (detect_r * 0.35), 0.0, 1.0)
				var brush := brush_on_line(dx_[i], dy_[i], T_BRUSH_LOOK)
				var want: float = margin + TOUCH_R
				var blocked := clampf_((want - widest) / want, 0.0, 1.0)
				var c := Data.deer_candidates(deer_p, near,
					(den[i] / deer_e.max_energy) if deer_e.max_energy > 0.0 else 0.0,
					brush, far_threat, blocked)
				var pick := Engine_.decide(c.bases, c.offsets, c.trait_vals, c.weights,
					deer_p.randomness, rng)
				dact[i] = c.acts[pick]
				dgait[i] = c.gaits[pick]
				var look_x := maxf(GOAL_X, dx_[i] - 320.0)
				match dact[i]:
					Data.DASH:
						dtx[i] = look_x
						dty[i] = dash_gap[0]
					Data.THREAD:
						dtx[i] = look_x
						dty[i] = thread_gap[0]
					Data.ARC:
						dtx[i] = maxf(GOAL_X, dx_[i] - 180.0)
						dty[i] = clampf_(edge[0], WALL, FIELD_H - WALL)
					Data.JINK:
						dtx[i] = dx_[i] - 50.0
						dty[i] = clampf_(dy_[i] + jink_sign * jink_amt, WALL, FIELD_H - WALL)
					Data.BOUND:
						dtx[i] = maxf(GOAL_X, dx_[i] - T_BRUSH_LOOK)
						dty[i] = dy_[i]
					Data.STOT:
						dtx[i] = maxf(GOAL_X, dx_[i] - 120.0)
						dty[i] = dy_[i]
				if dact[i] == Data.STOT:
					# an honest signal, and it only lands on a wolf that can see
					# it. A tired deer's claim is not believed for as long.
					var conviction: float = (den[i] / deer_e.max_energy) if deer_e.max_energy > 0.0 else 0.0
					for j in range(n_wolves):
						if sqrt(pow(wx[j] - dx_[i], 2.0) + pow(wy[j] - dy_[i], 2.0)) <= detect_r:
							wdet[j] = maxi(wdet[j], int(round(float(T_STOT_DETER_TICKS) * conviction)))

			var bounding := dgait[i] == Energy.BOUND
			if bounding:
				OUT_X = dtx[i]
				OUT_Y = dty[i]
			else:
				detour(dx_[i], dy_[i], dtx[i], dty[i], DEER_R)
			var ax := OUT_X - dx_[i]
			var ay := OUT_Y - dy_[i]
			var al := sqrt(ax * ax + ay * ay)
			if al == 0.0:
				al = 1.0
			ax /= al
			ay /= al
			var panic_r: float = T_PANIC_BASE + deer_p.get_trait("caution") * T_PANIC_SPAN
			for j in range(n_wolves):
				var rx := dx_[i] - wx[j]
				var ry := dy_[i] - wy[j]
				var dd := sqrt(rx * rx + ry * ry)
				if dd > 1e-6 and dd < panic_r:
					var k := pow((panic_r - dd) / panic_r, 2.0) * T_PANIC_K
					ax += (rx / dd) * k
					ay += (ry / dd) * k
				# a reflex, not a strategy: caution sets how much room a deer
				# likes, but no deer of any temperament runs into a wolf it can
				# touch
				if dd > 1e-6 and dd < T_REFLEX_R:
					var k2 := pow((T_REFLEX_R - dd) / T_REFLEX_R, 2.0) * T_REFLEX_K
					ax += (rx / dd) * k2
					ay += (ry / dd) * k2
			if dy_[i] < WALL:
				ay += ((WALL - dy_[i]) / WALL) * 1.1
			if dy_[i] > FIELD_H - WALL:
				ay -= ((dy_[i] - (FIELD_H - WALL)) / WALL) * 1.1

			var dspeed := Energy.gait_speed(Energy.DEER, dgait[i], den[i], deer_e)
			if bounding and in_brush(dx_[i], dy_[i]):
				dspeed *= T_BOUND_BONUS
			dh[i] = turn_toward(dh[i], atan2(ay, ax), T_DEER_TURN)
			var nx2 := clampf_(dx_[i] + cos(dh[i]) * dspeed, 0.0, FIELD_W)
			var ny2 := clampf_(dy_[i] + sin(dh[i]) * dspeed, 0.0, FIELD_H)
			if bounding:
				dx_[i] = nx2
				dy_[i] = ny2
			else:
				route_around(nx2, ny2, DEER_R)
				dx_[i] = clampf_(OUT_X, 0.0, FIELD_W)
				dy_[i] = clampf_(OUT_Y, 0.0, FIELD_H)
			den[i] = Energy.step_energy(den[i], Energy.DEER, dgait[i], deer_e, false)
			dphase[i] += dspeed
			deer_gait_ticks[dgait[i]] += 1
			deer_action_ticks[dact[i]] += 1

		# ── resolution: catches first, then escapes ───────────────
		var caught_now := []
		var escaped_now := []
		for i in range(n_deer):
			if not dalive[i] or descaped[i]:
				continue
			for j in range(n_wolves):
				if sqrt(pow(wx[j] - dx_[i], 2.0) + pow(wy[j] - dy_[i], 2.0)) <= TOUCH_R:
					dalive[i] = false
					caught_now.push_back({"deer": i, "wolf": j, "gait": wgait[j]})
					if decided_by == "none":
						decided_by = "wolf " + Energy.GAIT_NAMES[wgait[j]]
					break
			if dalive[i] and dx_[i] <= GOAL_X:
				descaped[i] = true
				escaped_now.push_back(i)
				if decided_by == "none":
					decided_by = "deer " + Energy.GAIT_NAMES[dgait[i]]

		if record != null:
			var wf := []
			for i in range(n_wolves):
				wf.push_back({
					"x": wx[i], "y": wy[i], "h": wh[i], "action": wact[i], "gait": wgait[i],
					"energy": wen[i], "fatigue": Energy.fatigue_penalty(wen[i], wolf_e), "phase": wphase[i],
				})
			var df := []
			for i in range(n_deer):
				df.push_back({
					"x": dx_[i], "y": dy_[i], "h": dh[i], "alive": dalive[i], "escaped": descaped[i],
					"action": dact[i], "gait": dgait[i], "energy": den[i],
					"fatigue": Energy.fatigue_penalty(den[i], deer_e), "phase": dphase[i],
				})
			record.push_back({"tick": tick, "wolves": wf, "deer": df,
				"caught": caught_now, "escaped": escaped_now})

		tick += 1

	var caught := 0
	for i in range(n_deer):
		if not dalive[i]:
			caught += 1
	var escaped := n_deer - caught
	var wolf_energy := 1.0
	if n_wolves > 0:
		var sw := 0.0
		for i in range(n_wolves):
			sw += wen[i] / maxf(wolf_e.max_energy, 1e-9)
		wolf_energy = sw / float(n_wolves)
	var deer_energy := 1.0
	if n_deer > 0:
		var sd := 0.0
		for i in range(n_deer):
			sd += den[i] / maxf(deer_e.max_energy, 1e-9)
		deer_energy = sd / float(n_deer)
	if decided_by == "none":
		decided_by = "cap" if capped else "none"
	return {
		"winner": "deer" if escaped >= caught else "wolves",
		"caught": caught, "escaped": escaped, "total": n_deer,
		"ticks": tick, "capped": capped,
		"chase_ticks": 0 if engaged_at < 0 else tick - engaged_at,
		"deer_energy": deer_energy, "wolf_energy": wolf_energy,
		"decided_by": decided_by,
		"wolf_gait_ticks": wolf_gait_ticks, "deer_gait_ticks": deer_gait_ticks,
		"wolf_action_ticks": wolf_action_ticks, "deer_action_ticks": deer_action_ticks,
	}
