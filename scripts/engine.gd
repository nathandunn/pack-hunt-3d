extends RefCounted
##
## `utilityDecide`, ported from sim-core `engine.ts`.
##
## The TS original sums each candidate's considerations by walking
## `Object.entries(c.considerations)` — that is, in the order the keys were
## written in the object literal, and that order is DIFFERENT for every
## candidate in Pack Hunt (a `chase/sprint` lists aggression, risk,
## persistence, caution, patience; a `flank/gallop` lists cooperation, focus).
## Floating-point addition is not associative, so summing them in one fixed
## global order would put the two implementations on different numbers from the
## first decision. Each candidate therefore carries its own (trait, weight)
## list in the JS literal's order, and `decide` walks it exactly.
##
## `personality.traits[k] ?? 0.5` is reproduced by `Personality.get_trait`,
## which is what makes a v0.4 personality with only the core six run unchanged.
##
## One draw per call, whatever the candidate count. That is the RNG stream
## contract the whole port hangs on: the gait rides along inside the decision
## the animal was already making, so adding gaits cost no extra draws.
##

## Scratch, reused across calls — `decide` runs a few hundred times a second.
static var _scores := PackedFloat64Array()


##
## `bases` is one float per candidate. `trait_idx` / `weights` are ragged: for
## candidate i, its considerations run from `offsets[i]` to `offsets[i + 1]`.
## Returns the chosen candidate index.
##
static func decide(bases: PackedFloat64Array, offsets: PackedInt32Array,
		trait_vals: PackedFloat64Array, weights: PackedFloat64Array,
		randomness: float, rng: RefCounted) -> int:
	var n := bases.size()
	if _scores.size() != n:
		_scores.resize(n)
	var best := -INF
	for i in range(n):
		var s := bases[i]
		for j in range(offsets[i], offsets[i + 1]):
			s += trait_vals[j] * weights[j]
		_scores[i] = s
		if s > best:
			best = s
	var t := 0.02 + randomness * 1.5
	var z := 0.0
	for i in range(n):
		var w: float = exp((_scores[i] - best) / t)
		_scores[i] = w
		z += w
	var r: float = rng.next()
	var idx := 0
	while idx < n - 1:
		r -= _scores[idx] / z
		if r <= 0.0:
			break
		idx += 1
	return idx
