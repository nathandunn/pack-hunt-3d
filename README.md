# Pack Hunt 3D

Wolves and deer with an energy and gait model, in 3D. Godot 4 / GDScript,
exported to WebAssembly.

A **second, independent implementation** of
[`nathandunn/pack-hunt`](https://github.com/nathandunn/pack-hunt) — same design
spec, same constants, same utility weights, different language and engine. The
canvas/TypeScript build is the source of truth; this one is ported from it
formula for formula and the divergences are listed below.

Live: <https://pack-hunt-3d.apps.precogsoftwareservices.com>

## The game

A deer spawns near the right edge of a 225 m x 130 m plain and must reach the
left edge. Five wolves spawn as a loose cordon between it and the goal.
Reaching the left edge is a deer win; a wolf getting within twelve sim units
(3 m) is a wolf win.

## Energy and gaits

Derived in [`specs/pack-hunt-energy.md`](specs/pack-hunt-energy.md), which was
written from the field literature before either implementation existed. The
one hard measurement underneath it is Bryce & Williams 2017 (*J. Exp. Biol.*
220:312) — cost of transport for northern-breed dogs, whose hip angle is
statistically indistinguishable from a grey wolf's.

| | speed (units/tick) | cost/s | a full tank lasts |
|---|---|---|---|
| wolf walk | 0.173 | −0.0036 | ∞ (refills in 279 s) |
| wolf trot | 0.293 | −0.0033 | ∞ (refills in 301 s) |
| wolf gallop | 1.267 | +0.0024 | 414 s |
| wolf sprint | 2.147 | +0.1111 | **9 s** |
| deer walk | 0.173 | −0.0007 | ∞ |
| deer trot | 0.400 | −0.0002 | ∞ |
| deer bound | 0.933 | +0.0400 | 25 s |
| deer gallop | 1.800 | +0.0121 | 83 s |
| deer sprint | 2.080 | +0.1111 | **9 s** |

Two things fall out of that table which are the whole model:

* **The deer is slightly *slower* than the wolf flat out** — 56 km/h against
  58–61. SPEC v0.4's fixed 2× ratio is gone; the asymmetry that makes the game
  is cost, not pace.
* **A wolf refills its tank in 217 s and a deer needs 789.** A wolf that empties
  itself is trotting again in four minutes. A deer that empties itself may not
  recover at all — that is what the capture-myopathy literature says happens to
  an over-exerted cervid.

`bound` is deliberately **slower than a gallop and four times dearer**, because
Lingle 2002 found that stotting does not outrun a coursing predator on open
ground. It only pays on broken terrain, so the five deadfall patches — which a
bounding deer crosses and every wolf must go around — are the only thing that
makes it rational.

## Formula divergences from the canvas build

1. **Transcendentals.** `exp` (softmax), `sin`/`cos`/`atan2` (steering, cover
   incidence) come from V8 there and from libm here. The softmax draw is a
   threshold on an accumulated probability, so a last-ulp difference eventually
   separates two runs completely. **Bit-identical replay across the two
   implementations is not available at all**, and no amount of care elsewhere
   would recover it.
2. **`Math.hypot` vs `sqrt(x*x+y*y)`** — same formula, computed the plain way.
3. **No `Vector2` anywhere in the simulation.** Godot's `Vector2` is float32 in
   a standard build. Routing a position through one silently rounded it to
   seven digits and put every deer step 6.5e-7 units off its gait speed — a
   divergence with nothing to do with libm. The geometry helpers return through
   module-level `OUT_X`/`OUT_Y` doubles instead.
4. **Consideration order is per candidate.** The TS build sums each candidate's
   considerations by walking `Object.entries`, which is the order the keys were
   written in that object literal — and in Pack Hunt that order differs between
   candidates. Floating-point addition is not associative, so each candidate
   here carries its own (trait, weight) list in the JS literal's order.
5. **No sim-core, no agent-forge.** The mulberry32 Rng, `utilityDecide` and the
   two geometry primitives are ported into `scripts/`. `simulate`'s trial loop
   is in `scripts/batch.gd`, using agent-forge's `seedBase + i` numbering, so
   batches line up trial for trial.

## Rendering

Two `MultiMeshInstance3D`s — one per species — and two draw calls at any animal
count. Both animals are built in code (`scripts/meshes.gd`): a handful of boxes
welded into one `ArrayMesh` each. Nothing is imported from outside this repo.

The gait animation is a **vertex-shader displacement**, because a MultiMesh
gives every instance one transform and limbs cannot be posed per instance from
GDScript. Every vertex carries its swing weight and leg index in `UV2`; every
instance carries phase, swing amplitude, footfall pattern and body flex in four
floats of custom data. So a walking wolf, a galloping wolf and a bounding deer
are all the same draw call.

The **vertical of a bound is not in the shader** — it is in the instance
transform, because a leap has to move the whole animal and cast its shadow from
somewhere other than its feet.

## Camera

45° elevation looking at the herd by default.

* **mouse** — left-drag orbits, right/middle-drag pans, wheel zooms
* **touch** — one finger orbits, two fingers pinch to zoom and drag to pan
* **Home view** puts it back

Pitch is clamped just short of straight down and just above the horizon.

## Parity with the canvas build

Sixty trials, `teamplayer` wolves against a `defender` deer, 5v1, seeds
20260910-69, both run headless. `./test.sh --parity 60` here and
`node tools/parity.mjs 60 20260910` there print these fields in this order.

| | Godot | JS | |
|---|---|---|---|
| deer win rate | 0.767 | 0.750 | +2% |
| kill rate | 0.233 | 0.250 | −7% |
| mean hunt (ticks) | 1440 | 1526 | −6% |
| mean chase (ticks) | 1223 | 1308 | −6% |
| deer energy at the outcome | 0.236 | 0.218 | +8% |
| pack energy at the outcome | 0.962 | 0.967 | −0.5% |
| wolf trot / gallop share | 0.158 / 0.831 | 0.149 / 0.841 | within 1 pp |
| deer gallop / sprint / bound share | 0.858 / 0.042 / 0.035 | 0.859 / 0.040 / 0.033 | within 0.3 pp |
| decided by a deer gallop | 43 of 60 | 41 of 60 | |
| decided by a wolf gallop | 12 of 60 | 14 of 60 | |
| runs stopped by the backstop cap | 1 | 2 | |

The gait shares are the interesting row: they agree to within a percentage
point on every gait including the rare ones, which is what says the two builds
are running the same energy model and not merely landing on similar win rates.

## Performance

`./test.sh --perf`, mean cost of one simulation tick on the hub against the
16.67 ms a 60 Hz frame allows:

| animals | ms/tick |
|---|---|
| 5 wolves + 1 deer | 0.37 |
| 80 wolves + 20 deer | 8.14 |
| 50 wolves + 50 deer | 9.27 |

**These are native numbers — the in-browser figure is not measured**, because
there is no browser on the build host. Built in for that: the playback loop
runs whole ticks from the frame delta with a hard catch-up cap, so a slow
device plays the hunt back in slow motion rather than skipping it, and simulate
mode slices its trials across frames on a 9 ms budget so the tab never blocks.

## Build and test

```bash
./test.sh                # the headless suite
./test.sh --perf         # tick cost at 100 animals against the 16.67 ms budget
./test.sh --parity 6     # the table this README's parity section quotes
./build.sh               # web export into dist/
```

Needs Godot 4.7.2 and the matching web export templates —
`hub-orchestrator/scripts/godot-install.sh` installs both.
