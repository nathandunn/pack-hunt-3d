extends RefCounted
##
## Seeded batches, in place of agent-forge's `runBatch`.
##
## Trial i gets `seed_base + i`, which is agent-forge's own numbering, so a
## batch here lines up trial for trial with a batch there. `run_slice` exists
## because the browser build cannot block the main thread for 300 hunts:
## simulate mode runs a few trials per frame and `tests.gd` asserts that a
## sliced batch equals a single-pass one exactly.
##

const World := preload("res://scripts/world.gd")
const Energy := preload("res://scripts/energy.gd")


class Stats extends RefCounted:
	var n := 0
	var deer_wins := 0
	var wolf_wins := 0
	var ticks := 0
	var chase := 0
	var deer_e := 0.0
	var wolf_e := 0.0
	var decided := {}
	var wolf_gait := PackedInt32Array()
	var deer_gait := PackedInt32Array()
	var wolf_action := PackedInt32Array()
	var deer_action := PackedInt32Array()

	func _init() -> void:
		wolf_gait.resize(6)
		deer_gait.resize(6)
		wolf_action.resize(6)
		deer_action.resize(6)

	func add(r: Dictionary) -> void:
		n += 1
		if r["winner"] == "deer":
			deer_wins += 1
		else:
			wolf_wins += 1
		ticks += r["ticks"]
		chase += r["chase_ticks"]
		deer_e += r["deer_energy"]
		wolf_e += r["wolf_energy"]
		var k: String = r["decided_by"]
		decided[k] = decided.get(k, 0) + 1
		for g in range(6):
			wolf_gait[g] += r["wolf_gait_ticks"][g]
			deer_gait[g] += r["deer_gait_ticks"][g]
			wolf_action[g] += r["wolf_action_ticks"][g]
			deer_action[g] += r["deer_action_ticks"][g]

	func deer_win_rate() -> float:
		return float(deer_wins) / float(maxi(n, 1))

	func kill_rate() -> float:
		return float(wolf_wins) / float(maxi(n, 1))

	func gait_share(a: PackedInt32Array) -> PackedFloat64Array:
		var tot := 0
		for v in a:
			tot += v
		var out := PackedFloat64Array()
		out.resize(6)
		for i in range(6):
			out[i] = float(a[i]) / float(maxi(tot, 1))
		return out


static func run_series(wolf_p, deer_p, n_wolves: int, n_deer: int, trials: int,
		seed_base: int = 900, cfg: Dictionary = {}) -> Stats:
	var s := Stats.new()
	for i in range(trials):
		s.add(World.run_hunt(wolf_p, deer_p, n_wolves, n_deer, seed_base + i, World.MAX_TICKS, [], cfg))
	return s


## Run trials [from, to) into an existing Stats — the sliced form.
static func run_slice(st: Stats, wolf_p, deer_p, n_wolves: int, n_deer: int,
		from_i: int, to_i: int, seed_base: int, cfg: Dictionary = {}) -> void:
	for i in range(from_i, to_i):
		st.add(World.run_hunt(wolf_p, deer_p, n_wolves, n_deer, seed_base + i, World.MAX_TICKS, [], cfg))
