extends RefCounted
##
## The energy and gait model, ported from `pack-hunt/src/energy.ts`.
##
## Every number here is derived in `specs/pack-hunt-energy.md`, which was
## written from the field literature before either implementation existed. The
## derivation, in full:
##
##   power (W/kg)  = cost of transport (J/kg/m) x speed (m/s)
##   drain   /s    = (power - ceiling) / tank            when power >  ceiling
##   recover /s    = (ceiling - power) * eta / tank      when power <= ceiling
##   canSustain(s) = 1 / drain                           (infinite if it recovers)
##
## The tables are computed here rather than transcribed, from the same
## physiology constants the JS build uses, so the two cannot drift apart
## silently: `tests.gd` asserts every entry against the JS values.
##

const TICKS_PER_SEC := 30.0
const METRES_PER_UNIT := 0.25
## m/s -> sim units per tick
const MPS_TO_UNITS := 1.0 / METRES_PER_UNIT / TICKS_PER_SEC

enum { WALK, TROT, GALLOP, SPRINT, BOUND, STOT }
const GAIT_NAMES := ["walk", "trot", "gallop", "sprint", "bound", "stot"]
## The four that must stay monotonic in speed and in cost, for both species.
const LADDER := [WALK, TROT, GALLOP, SPRINT]

enum { WOLF, DEER }

## ceiling (W/kg, sustainable — not VO2max), tank (J/kg), eta, rest power
const WOLF_CEILING := 18.0
const WOLF_TANK := 1200.0
const WOLF_ETA := 0.35
const WOLF_REST := 2.2

const DEER_CEILING := 11.0
const DEER_TANK := 1775.0
const DEER_ETA := 0.25
const DEER_REST := 2.0

## m/s and W/kg per gait. -1 marks a gait the species does not have.
##                     walk  trot  gallop sprint bound stot
const WOLF_MPS   := [  1.3,  2.2,   9.5,  16.1,  -1.0, -1.0]
const WOLF_POWER := [  5.7,  6.6,  20.9, 151.33, -1.0, -1.0]
const DEER_MPS   := [  1.3,  3.0,  13.5,  15.6,   7.0,  3.0]
const DEER_POWER := [  6.2,  9.9,  32.4, 208.22,  82.0, 82.0]

## Speeds in sim units per tick, costs in energy units per second.
static var speed := [PackedFloat64Array(), PackedFloat64Array()]
static var cost := [PackedFloat64Array(), PackedFloat64Array()]
static var sustain := [PackedFloat64Array(), PackedFloat64Array()]
static var _built := false


static func build() -> void:
	if _built:
		return
	_built = true
	for sp in [WOLF, DEER]:
		var mps: Array = WOLF_MPS if sp == WOLF else DEER_MPS
		var pw: Array = WOLF_POWER if sp == WOLF else DEER_POWER
		var ceiling: float = WOLF_CEILING if sp == WOLF else DEER_CEILING
		var tank: float = WOLF_TANK if sp == WOLF else DEER_TANK
		var eta: float = WOLF_ETA if sp == WOLF else DEER_ETA
		var sv := PackedFloat64Array()
		var cv := PackedFloat64Array()
		var uv := PackedFloat64Array()
		sv.resize(6)
		cv.resize(6)
		uv.resize(6)
		for g in range(6):
			if mps[g] < 0.0:
				sv[g] = 0.0
				cv[g] = 0.0
				uv[g] = INF
				continue
			sv[g] = mps[g] * MPS_TO_UNITS
			var p: float = pw[g]
			var c := (p - ceiling) / tank if p > ceiling else -((ceiling - p) * eta) / tank
			cv[g] = c
			uv[g] = (1.0 / c) if c > 0.0 else INF
		speed[sp] = sv
		cost[sp] = cv
		sustain[sp] = uv


## The five per-species numbers the UI sliders move.
class Settings extends RefCounted:
	var max_energy := 1.0
	var sprint_cost := 0.0
	var gallop_cost := 0.0
	var recovery_rate := 0.0
	var fatigue_threshold := 0.5
	var fatigue_penalty_max := 0.45

	func duplicate_settings() -> Settings:
		var s := Settings.new()
		s.max_energy = max_energy
		s.sprint_cost = sprint_cost
		s.gallop_cost = gallop_cost
		s.recovery_rate = recovery_rate
		s.fatigue_threshold = fatigue_threshold
		s.fatigue_penalty_max = fatigue_penalty_max
		return s


static func field_data(sp: int) -> Settings:
	build()
	var s := Settings.new()
	var ceiling: float = WOLF_CEILING if sp == WOLF else DEER_CEILING
	var tank: float = WOLF_TANK if sp == WOLF else DEER_TANK
	var eta: float = WOLF_ETA if sp == WOLF else DEER_ETA
	var rest: float = WOLF_REST if sp == WOLF else DEER_REST
	s.max_energy = 1.0
	s.sprint_cost = cost[sp][SPRINT]
	s.gallop_cost = cost[sp][GALLOP]
	s.recovery_rate = (ceiling - rest) * eta / tank
	s.fatigue_threshold = 0.5
	s.fatigue_penalty_max = 0.45 if sp == WOLF else 0.55
	return s


static func cost_of(sp: int, gait: int, s: Settings) -> float:
	if gait == SPRINT:
		return s.sprint_cost
	if gait == GALLOP:
		return s.gallop_cost
	return cost[sp][gait]


##
## Speed lost to an emptying tank. Zero above the threshold, rising linearly to
## `fatigue_penalty_max` at zero — 0.55 for a deer, which is the stumble. The
## threshold is 0.50, so the penalty starts once half the tank is gone: an
## oxygen debt degrades performance immediately and progressively, and a cliff
## at 0.30 made a sprint free in small doses.
##
static func fatigue_penalty(energy: float, s: Settings) -> float:
	if s.max_energy <= 0.0 or s.fatigue_threshold <= 0.0:
		return 0.0
	var frac := energy / s.max_energy
	if frac >= s.fatigue_threshold:
		return 0.0
	return (1.0 - frac / s.fatigue_threshold) * s.fatigue_penalty_max


static func gait_speed(sp: int, gait: int, energy: float, s: Settings) -> float:
	return speed[sp][gait] * (1.0 - fatigue_penalty(energy, s))


## One tick of energy accounting. `resting` overrides the gait with rest recovery.
static func step_energy(energy: float, sp: int, gait: int, s: Settings, resting: bool) -> float:
	var per_sec := -s.recovery_rate if resting else cost_of(sp, gait, s)
	var next_e := energy - per_sec / TICKS_PER_SEC
	if next_e < 0.0:
		return 0.0
	if next_e > s.max_energy:
		return s.max_energy
	return next_e
