extends RefCounted
##
## Personalities and the (action, gait) candidate tables, ported from
## `pack-hunt/src/sim.ts`.
##
## The candidate lists are the JS literals transcribed in order, considerations
## included — see `engine.gd` for why the order matters. Anything the JS build
## filters out of the list is filtered out here at the same point and for the
## same reason: a gait an animal cannot pay for is not a low-scoring option, it
## is absent, because softmax temperature is `0.02 + randomness * 1.5` and a
## wildcard personality would otherwise buy a sprint it has no tank for.
##

const Energy := preload("res://scripts/energy.gd")

enum { CHASE, INTERCEPT, CORDON, GUARD, FLANK, RELAY }
const WOLF_ACTIONS := ["chase", "intercept", "cordon", "guard", "flank", "relay"]
enum { DASH, THREAD, ARC, JINK, BOUND, STOT }
const DEER_ACTIONS := ["dash", "thread", "arc", "jink", "bound", "stot"]

const SPRINT_FLOOR := 1e-9
const RELAY_ENERGY := 0.70


class Personality extends RefCounted:
	var id := ""
	var traits := {}
	var randomness := 0.15

	func get_trait(k: String) -> float:
		return traits[k] if traits.has(k) else 0.5

	static func make(pid: String, t: Dictionary, r: float = 0.15) -> Personality:
		var p := Personality.new()
		p.id = pid
		p.randomness = r
		p.traits = {
			"aggression": 0.5, "caution": 0.5, "cooperation": 0.5,
			"patience": 0.5, "risk": 0.5, "focus": 0.5,
		}
		for k in t:
			p.traits[k] = t[k]
		return p


## sim-core's five archetypes, verbatim.
static func archetypes() -> Dictionary:
	return {
		"attacker": Personality.make("attacker", {"aggression": 0.9, "caution": 0.2, "risk": 0.8, "patience": 0.2}),
		"defender": Personality.make("defender", {"aggression": 0.2, "caution": 0.9, "risk": 0.2, "patience": 0.8}),
		"opportunist": Personality.make("opportunist", {"aggression": 0.6, "caution": 0.4, "risk": 0.7, "focus": 0.8}),
		"teamplayer": Personality.make("teamplayer", {"cooperation": 0.95, "aggression": 0.4, "focus": 0.6}),
		"wildcard": Personality.make("wildcard", {"risk": 0.9, "focus": 0.3}, 0.6),
	}


##
## A built candidate set: parallel arrays ready for `engine.decide`, plus the
## (action, gait) each surviving row maps back to.
##
class Candidates extends RefCounted:
	var bases := PackedFloat64Array()
	var offsets := PackedInt32Array()
	var trait_vals := PackedFloat64Array()
	var weights := PackedFloat64Array()
	var acts := PackedInt32Array()
	var gaits := PackedInt32Array()

	func _init() -> void:
		offsets.push_back(0)

	func add(base: float, act: int, gait: int, p: Personality, cons: Array) -> void:
		bases.push_back(base)
		acts.push_back(act)
		gaits.push_back(gait)
		# cons is [name, weight, name, weight, ...] in the JS literal's order
		var i := 0
		while i < cons.size():
			trait_vals.push_back(p.get_trait(cons[i]))
			weights.push_back(cons[i + 1])
			i += 2
		offsets.push_back(trait_vals.size())


##
## Wolf (action, gait) utilities.
##
## `sprint` is deliberately NOT hard-gated on distance — it is priced by
## temperament, so an aggressive pack burns its nine seconds of top speed in
## the approach and a patient one still has it when the chase is decided.
##
static func wolf_candidates(p: Personality, near: float, ahead: bool, energy: float,
		lead: float, deter: float, post_far: float, weary: float, close_in: float) -> Candidates:
	var spent := energy < SPRINT_FLOOR
	var gate := -(1.0 - energy) * 0.85
	var off: float = max(deter, weary)
	var push := off * 1.4
	var hold := deter * 0.9 + weary * 0.35
	var c := Candidates.new()
	if not spent:
		c.add(-0.35 + 0.85 * near + gate - push, CHASE, Energy.SPRINT, p,
			["aggression", 0.9, "risk", 0.45, "persistence", 0.3, "caution", -0.7, "patience", -0.3])
	c.add(0.12 + 0.55 * near + (0.0 if ahead else 0.30) - push, CHASE, Energy.GALLOP, p,
		["aggression", 1.0, "persistence", 0.35, "patience", -0.35])
	c.add(0.36 + 0.22 * near - push, INTERCEPT, Energy.GALLOP, p,
		["focus", 0.85, "risk", 0.3, "persistence", 0.25, "cooperation", 0.35, "aggression", 0.15])
	if not spent:
		c.add(-0.55 + 0.80 * near + gate - push, INTERCEPT, Energy.SPRINT, p,
			["focus", 0.6, "risk", 0.7, "persistence", 0.25, "caution", -0.5])
	c.add(0.18 + 0.34 * near - push * 0.4, FLANK, Energy.GALLOP, p,
		["cooperation", 0.7, "focus", 0.5])
	c.add((0.62 if ahead else 0.02) - 1.00 * post_far - close_in * near + hold, CORDON, Energy.TROT, p,
		["cooperation", 1.1, "patience", 0.45, "aggression", -0.3])
	c.add((0.10 if ahead else 0.0) + 0.95 * post_far - close_in * 0.65 * near + hold * 0.5, CORDON, Energy.GALLOP, p,
		["cooperation", 1.0, "focus", 0.35, "patience", -0.15])
	c.add((0.16 if ahead else 0.0) - close_in * 0.78 * near + hold, GUARD, Energy.WALK, p,
		["patience", 0.7, "caution", 0.75, "risk", -0.2, "persistence", -0.2])
	if energy <= RELAY_ENERGY:
		c.add(-0.25 + 1.6 * (1.0 - energy) * lead, RELAY, Energy.TROT, p,
			["cohesion", 0.9, "cooperation", 0.4, "patience", 0.35, "aggression", -0.4, "persistence", -0.3])
	return c


##
## Deer (action, gait) utilities.
##
## `bound` is a bad idea on open ground — slower than a gallop and three times
## dearer — so it is only offered with brush on the line (Lingle 2002). `stot`
## is an honest signal: bound's cost at trot's speed, and a deer with an empty
## tank cannot afford the claim (FitzGibbon & Fanshawe 1988).
##
static func deer_candidates(p: Personality, near: float, energy: float, brush: float,
		far_threat: float, blocked: float) -> Candidates:
	var spent := energy < SPRINT_FLOOR
	var gate := -(1.0 - energy) * 0.9
	var c := Candidates.new()
	c.add(0.70, DASH, Energy.GALLOP, p, ["focus", 0.45, "patience", 0.2])
	if not spent:
		c.add(0.02 + 0.85 * near + gate, DASH, Energy.SPRINT, p,
			["focus", 0.35, "panic", 0.8, "stamina", 0.25, "caution", -0.45])
	c.add(0.14 + 0.30 * near, THREAD, Energy.GALLOP, p, ["risk", 1.0, "caution", -0.55])
	if not spent:
		c.add(-0.25 + 0.75 * near + gate, THREAD, Energy.SPRINT, p,
			["risk", 0.9, "panic", 0.6, "caution", -0.6])
	c.add(0.20 + 1.35 * blocked, ARC, Energy.GALLOP, p, ["caution", 0.9, "risk", -0.35])
	if energy <= 0.6:
		c.add(-0.60 + 0.40 * (1.0 - near) + 0.95 * (1.0 - energy), ARC, Energy.TROT, p,
			["caution", 0.35, "patience", 0.5, "panic", -0.5, "stamina", -0.3])
	c.add(0.04 + p.randomness * 0.5 + 0.28 * near, JINK, Energy.GALLOP, p, ["focus", -0.2])
	if energy > 0.0 and brush >= 0.15:
		c.add(-1.25 + 1.85 * brush + gate * 0.6, BOUND, Energy.BOUND, p,
			["risk", 0.35, "stamina", 0.4, "panic", 0.25])
	if energy > 0.0 and far_threat >= 0.05:
		c.add(-1.35 + 1.60 * far_threat - (1.0 - energy) * 1.2, STOT, Energy.STOT, p,
			["vigilance", 0.9, "caution", 0.4, "stamina", 0.35, "panic", -0.5])
	return c
