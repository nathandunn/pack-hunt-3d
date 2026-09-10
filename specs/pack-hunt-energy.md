# Pack Hunt — energy, gaits and the animals that use them

Research spec, written 2026-09-10, before any code. Sources are cited inline as
URLs. Everything the field data did **not** give me is marked **[guess]** with
the reasoning that produced the number, so a later reader can tell the measured
from the invented at a glance.

Supersedes SPEC v0.4's **fixed 2× deer:wolf speed ratio** — see
"[The 2× rule is wrong](#the-2-rule-is-wrong-and-that-is-the-most-useful-thing-the-research-said)"
below. Everything else in v0.4 (the crossing objective, continuous field,
determinism-by-seed, personality-driven action choice) stands.

---

## 1. What the field data actually says

### 1.1 Grey wolf — speed

| quantity | figure | source |
|---|---|---|
| travel / trot | **5 mph ≈ 8 km/h ≈ 2.2 m/s** | [International Wolf Center](https://wolf.org/wolf-info/basic-wolf-info/wolf-faqs/) — "Wolves will travel for long distances by trotting at about five miles per hour"; [NPS](https://www.nps.gov/articles/life-of-a-wolf.htm) — "they usually trot along at 5 mph" |
| how long the trot is held | **hours** — 30–50 miles/day | [NPS](https://www.nps.gov/articles/life-of-a-wolf.htm) "as far as 30 miles in a day"; [IWC](https://wolf.org/wolf-info/basic-wolf-info/wolf-faqs/) "may travel 50 miles or more each day". 50 mi at 5 mph is **10 hours of trotting** |
| sprint | **36–38 mph ≈ 58–61 km/h ≈ 16–17 m/s** | [IWC](https://wolf.org/wolf-info/basic-wolf-info/wolf-faqs/) — "36 to 38 miles per hour for short bursts while chasing prey" |
| sprint (higher figure) | 45 mph ≈ 72 km/h | [NPS](https://www.nps.gov/articles/life-of-a-wolf.htm) — "as high as 45 miles per hour for short distances". The two agency sources disagree by 20%; this spec uses the IWC figure and notes the spread |
| how long the sprint is held | **"short bursts"** — no agency source gives seconds | see §1.5 |
| gallop | **not found in any source** | **[guess]** — see §2.2 |

### 1.2 Grey wolf — energetics

The one hard measurement in this whole spec:

> Bryce, C. M. & Williams, T. M. (2017). *Comparative locomotor costs of
> domestic dogs reveal energetic economy of wolf-like breeds.*
> **J. Exp. Biol. 220(2): 312–321.**
> <https://journals.biologists.com/jeb/article/220/2/312/18618/Comparative-locomotor-costs-of-domestic-dogs>

23 dogs >20 kg, three breed groups, treadmill + level transect at *preferred
steady-state gaits*. Total cost of transport, J kg⁻¹ m⁻¹:

| breed group | trot | gallop | per stride |
|---|---|---|---|
| **northern breeds** (the wolf proxy) | **3.0** | **2.1** | 3.5 J kg⁻¹ stride⁻¹ |
| retrievers | 3.8 | 3.0 | 4.0 |
| hounds | 4.2 | 3.4 | 5.0 |

Also from that paper, and used below:

* Resting metabolic rate **≈ 6–8 ml O₂ kg⁻¹ min⁻¹** (≈ **2.2 W kg⁻¹** at
  20.1 J per ml O₂).
* Northern-breed hip angle **109.4 ± 1.1°** is statistically indistinguishable
  from grey wolf **108.8 ± 1.7°** (P = 0.99) — which is the paper's own
  justification for reading northern-breed numbers as wolf numbers, and mine.
* Hounds and retrievers transition trot→gallop **18–26% faster than body mass
  predicts**; northern breeds do not. The wolf-shaped animal changes up
  *earlier* and runs its gaits *economically*, rather than stretching one gait.
  **This is the single most load-bearing fact in the whole model:** gaits are
  discrete economic regimes, not a speed dial.

Cross-check on the mass scaling, used in §1.4 to move these numbers onto a deer:
net cost of transport scales as body mass **M⁻⁰·³²** (Taylor, Heglund & Maloiy
1982, *J. Exp. Biol.* 97: 1–21, <https://pubmed.ncbi.nlm.nih.gov/7086334/>;
exponent confirmed via
<https://www.nature.com/articles/s41598-018-36565-z>). **[flag]** I could not
retrieve the original paper's coefficient, only the exponent, so this spec uses
the exponent as a *ratio* between the two species and never as an absolute.

And the reason a gait table is the right abstraction at all: Hoyt, D. F. &
Taylor, C. R. (1981), *Gait and the energetics of locomotion in horses*,
**Nature 292: 239–240**, <https://www.nature.com/articles/292239a0> — oxygen
consumption against speed is **U-shaped within each gait**, each gait has its
own minimum, and animals left to themselves pick the gait that minimises cost at
the speed they want. A simulation that models speed as continuous and cost as
linear is modelling something no quadruped does.

### 1.3 How a wolf chase is actually decided

> Wikenros, C., Sand, H., Wabakken, P., Liberg, O. & Pedersen, H. C. (2009).
> *Wolf predation on moose and roe deer: chase distances and outcome of
> encounters.* **Acta Theriologica 54: 207–218.**
> <https://link.springer.com/article/10.4098/j.at.0001-7051.082.2008>
> **[flag]** paywalled; figures below are from the indexed abstract, not from
> the full text.

| finding | figure |
|---|---|
| effort behind it | 4200 km of snow tracking, 28 wolf territories, 1997–2003 |
| attacks recorded | 252 on moose, 64 on roe deer |
| **mean chase distance** | **76 m (moose), 237 m (roe deer)** |
| hunting success | **43% (moose), 47% (roe deer)** — no difference between species |
| what predicts a short chase | greater snow depth; and, for moose only, a *successful* attack |
| model fit | prey species + outcome + snow depth explains only **15–19%** of the variance in chase distance |

**A wolf chase is two hundred metres, not two kilometres.** This is the result
that most changes the design, and it contradicts the folklore — repeated by
nearly every popular page returned in this research — that wolves win by running
prey down over miles. They win in the first few hundred metres or they stop.

The 43–47% success figure is Scandinavian wolves on moose and roe deer. Popular
sources put wolf hunting success far lower (3–14%) for large prey like bison and
elk. **[flag]** I did not find a primary source for a grey-wolf-on-white-tailed-deer
success rate, and the two ranges are not comparable, so no success rate is used
as a calibration target.

The other half of the answer is that wolves do not pick a random deer:

* Wolves "most often select prey that is weaker and more vulnerable … injured,
  sick, old, very young"
  (<https://www.livingwithwolves.org/how-wolves-hunt/>); this is the standard
  Mech-and-Peterson account of wolf–ungulate coexistence.

And a wolf pack's coordination needs less machinery than it looks:

> Muro, C., Escobedo, R., Spector, L. & Coppinger, R. P. (2011). *Wolf-pack
> (Canis lupus) hunting strategies emerge from simple rules in computational
> simulations.* **Behavioural Processes 88(3): 192–197.**
> <https://www.sciencedirect.com/science/article/abs/pii/S0376635711001884>

Two decentralised rules — (1) close on the prey until a minimum safe distance,
(2) once at that distance, move away from other wolves that are also at it —
reproduce tracking, pursuit, encirclement, **relay-running** and ambush. No
communication and no hierarchy required. That is the licence for modelling
`flank` and `relay` as per-wolf utility actions rather than a pack-level
choreographer.

### 1.4 Deer — speed, gaits and how a deer wins

| quantity | figure | source |
|---|---|---|
| white-tailed deer top speed | **35 mph ≈ 56 km/h ≈ 15.6 m/s** | [Maryland DNR](https://dnr.maryland.gov/wildlife/pages/hunt_trap/wtdeerfacts.aspx) — "reported to run at speeds reaching 35 miles per hour" |
| how long that is held | **"cannot be maintained for long distances"** — no agency source gives seconds | see §1.5 |
| standing jump | **clears a 7-foot fence** | [Maryland DNR](https://dnr.maryland.gov/wildlife/pages/hunt_trap/wtdeerfacts.aspx) |
| running jump | **clears an 8-foot fence** | [Maryland DNR](https://dnr.maryland.gov/wildlife/pages/hunt_trap/wtdeerfacts.aspx) |
| mule deer bound | leaps of **up to 8 yards (≈7.3 m)**, all four feet landing together; ~45 mph in short bursts | <https://www.desertusa.com/animals/mule-deer.html> **[flag]** popular source, no primary found |

**The two deer species escape differently, and the difference is a gait:**

> Lingle, S. (2002). *Coyote predation and habitat segregation of white-tailed
> deer and mule deer.* **Ecology 83(7): 2037–2048.**
> <https://esajournals.onlinelibrary.wiley.com/doi/abs/10.1890/0012-9658(2002)083%5B2037:CPAHSO%5D2.0.CO;2>

* Mule deer **stot** (bound); white-tailed deer **gallop**.
* **Stotting is ineffective as flight from a coursing predator.** Mule deer that
  stot on gentle ground do not get away from coyotes; they take to rugged,
  broken terrain and high ground, where the gait pays.
* **Galloping works for white-tails — but only on gentle terrain** that permits
  unobstructed movement.

This is the sharpest correction the research made to the handoff's brief, which
asked for "a bounding deer escapes through brush" as a scenario. That scenario
is right, but only *because of the brush*: on open ground a bounding deer is a
slower deer, and the sim must reproduce **both** halves or it is teaching the
wrong lesson. The obstacle patches are therefore not decoration — they are the
only thing that makes `bound` a rational action.

Detection is the other half of the deer's game:

> Lingle, S. & Wilson, W. F. / Lingle, S. (2001). *Detection and Avoidance of
> Predators in White-Tailed Deer (Odocoileus virginianus) and Mule Deer
> (O. hemionus).* **Ethology 107(2): 125–147.**
> <https://onlinelibrary.wiley.com/doi/abs/10.1046/j.1439-0310.2001.00647.x>
> **[flag]** paywalled; findings below from the indexed abstract.

* Mule deer alert to an approacher at **longer distances** than white-tails,
  even after controlling for confounds.
* Adult females of both species alert sooner than juveniles.
* **Coyote encounters with both species were more likely to escalate when the
  deer alerted at shorter distances.** Early detection is the deer's primary
  defence — before speed, before gait, before terrain.

And stotting as a *signal* rather than as flight:

> FitzGibbon, C. D. & Fanshawe, J. H. (1988). *Stotting in Thomson's gazelles:
> an honest signal of condition.* **Behavioral Ecology and Sociobiology
> 23(2): 69–74.** <https://link.springer.com/article/10.1007/BF00299889>

* Gazelles stot far more at **coursing** predators (wild dogs) than at
  **stalking** ones (cheetahs) — wolves are coursers, so this applies.
* Wild dogs **selected** gazelles that stotted at *lower* rates.
* Gazelles that were chased and **escaped** stotted more, and for longer, than
  those chased and killed.
* In the dry season, when condition is poor, gazelles stotted less.
* "Cheetahs abandon more hunts when their gazelle prey stots, and when they do
  give chase to a stotting gazelle, they are far less likely to make a kill"
  (<https://en.wikipedia.org/wiki/Stotting>).

So a stot is an **honest, expensive advertisement of a full tank**, and it works
by making the predator decline the chase. Cheap to fake would make it useless;
in the model it must cost real energy.

### 1.5 Why the sprint ends — and why the deer's ends worse

Neither agency source gives a duration for a top-speed run, so the duration has
to come from physiology.

* Phosphagen (ATP-PCr) supports maximal effort for **~10 s**; anaerobic
  glycolysis then carries it for roughly **80 s more at declining power**;
  all-out efforts are conventionally measured over **30 s** (the Wingate test).
  Peak velocity in an elite human sprinter is held for **6–8 s**.
  (<https://www.physio-pedia.com/Anaerobic_Capacity>,
  <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5466345/>)
* **[derived]** A quadruped's *top-speed* window therefore sits at
  **~20–30 s**, and this spec uses **25 s** for both species.

The asymmetry is not in the tank, it is in what happens after:

> Breed, D. *et al.* (2019). *Conserving wildlife in a changing world:
> understanding capture myopathy — a malignant outcome of stress during capture
> and translocation.* **Conservation Physiology 7(1): coz027.**
> <https://academic.oup.com/conphys/article/7/1/coz027/5528374>

Capture myopathy "can occur naturally when a deer is attempting to avoid
predation … the outcome … is a successful escape if the chase is of short
duration, but the disadvantage is that the probability is high for these
mechanisms to fail when over exerted"
(<https://www.researchgate.net/publication/378096128_Facts_about_Wildlife_Diseases_Capture_Myopathy_in_Farmed_White-Tailed_Deer_VM259_12024>).
Clinical signs appear "hours, days, or up to two months following" the event.

Against that, Bryce & Williams' framing of canids as "among nature's most elite
endurance athletes". **A deer that empties its tank may never refill it. A wolf
that empties its tank is trotting again in four minutes.** That single sentence
is the model.

---

## The 2× rule is wrong, and that is the most useful thing the research said

SPEC v0.4 fixed **deer speed = exactly 2 × wolf speed** and forbade tuning it.
The field data does not support it and is not close:

| | top speed |
|---|---|
| grey wolf | 58–61 km/h (IWC) — 72 km/h (NPS) |
| white-tailed deer | 56 km/h (Maryland DNR) |

**The deer is very slightly *slower* than the wolf flat out — roughly 0.93×, not
2×.** A deer does not escape a wolf by being twice as fast. It escapes because:

1. it detects the wolf early and starts with a lead (Lingle 2001),
2. the chase is decided inside ~240 m (Wikenros et al. 2009), and
3. inside that window the difference in speed is small enough that a lead, a
   terrain choice or one good angle settles it.

And the wolf's real edge — the one the 2× rule was standing in for — is not pace
at all, it is **cost**: the wolf's trot is free and the deer's escape gait is
not. So this spec **replaces the 2× speed rule with the energy model**: speeds
come from the sources (near-parity at the top), and the asymmetry that makes the
game moves into cost, sustain and recovery, where the evidence actually puts it.

That is a deliberate override of a "never tune this" line in an earlier spec,
recorded here so it is a decision and not an accident. It also *improves* the
crossing: under v0.4 an unobstructed deer simply outran everything; under this
spec an unobstructed deer still wins, but has to spend a finite resource to do
it, and the pack's job becomes making the crossing take longer than the tank
lasts.

---

## 2. The derived model

### 2.1 Sim units

| | |
|---|---|
| length | **1 sim unit = 0.25 m** → the 900 × 520 field is **225 m × 130 m** |
| crossing distance | 858 units = **214.5 m** — deliberately set near the 237 m mean roe-deer chase distance (Wikenros et al. 2009) |
| time | **30 ticks = 1 second** (unchanged, `TICKS_PER_SEC`) |
| speed conversion | `units/tick = (m/s) × 0.13333` |
| energy | **[0, 1]**, where 1.0 = the animal's full anaerobic tank |

### 2.2 Power estimates (W/kg), and where each came from

Power = cost of transport (J kg⁻¹ m⁻¹) × speed (m s⁻¹). The sourced COT figures
are Bryce & Williams' *preferred-gait* values, so applying them at chase speeds
is an extrapolation — flagged in the last column.

**Wolf** (≈40 kg):

| gait | speed | COT used | power | provenance |
|---|---|---|---|---|
| rest | — | — | 2.2 | **sourced** — RMR 6–8 ml O₂ kg⁻¹ min⁻¹ |
| walk | 1.3 m/s | 4.4 | 5.7 | **[guess]** speed and COT; COT above the trot value because total COT falls with speed (Bryce & Williams) |
| trot | **2.2 m/s** | **3.0** | **6.6** | **both sourced** — the only fully-sourced row in the table |
| gallop | 10 m/s | 2.2 | 22 | **[guess]** speed (no source found for a wolf gallop); COT extrapolated from the measured 2.1 at a preferred (~5 m/s) gallop |
| sprint | **16.1 m/s** | 4.0 | 65 | speed **sourced** (IWC 58 km/h); COT is a **[guess]** — 2.2 × the gallop value, for the collapse in muscle efficiency at maximal effort |

**Deer** (≈60 kg). No cervid locomotor-cost measurement was found at all, so
every COT here is transferred from the wolf by two multipliers:

* **mass**: (60/40)^−0.32 = **0.88** — sourced exponent (Taylor et al. 1982)
* **economy penalty**: **× 1.25** **[guess]** — a deer is not built for economical
  travel the way a wolf is; 1.25 is roughly the measured hound-vs-northern-breed
  penalty in Bryce & Williams (4.2/3.0 = 1.40 at trot, 3.4/2.1 = 1.62 at gallop),
  taken conservatively
* net: deer COT ≈ **1.10 ×** wolf COT

| gait | speed | COT used | power | provenance |
|---|---|---|---|---|
| rest | — | — | 2.0 | **[guess]** — wolf RMR scaled by M⁻⁰·²⁵ |
| walk | 1.3 m/s | 4.8 | 6.2 | **[guess]** |
| trot | 3.0 m/s | 3.3 | 9.9 | **[guess]** speed; COT transferred |
| gallop | 9 m/s | 2.4 | 21.6 | **[guess]** speed; COT transferred |
| **bound / stot** | 7 m/s | 6.0 | 42 | **[guess]** — 2.5 × gallop COT. A stiff-legged stot with a real vertical component recovers almost no elastic energy, and Lingle 2002 says it does not outrun a courser, so it must be **slower and dearer than a gallop** |
| sprint | **15.6 m/s** | 5.3 | 82 | speed **sourced** (Maryland DNR 35 mph); COT a **[guess]**, same 2.2× premium as the wolf |

### 2.3 Aerobic ceiling, tank and the drain formula

One formula does all of it:

```
drain/s   = (P_gait − ceiling) / tank        when P_gait > ceiling
recover/s = (ceiling − P_gait) × η / tank    when P_gait ≤ ceiling
canSustain(gait) = 1 / (drain/s)             seconds, ∞ when the gait recovers
```

`ceiling` is the **sustainable** aerobic power, not VO₂max — you cannot hold
VO₂max, and ~60% of it is the conventional sustainable fraction. `η` is
repayment efficiency: clearing an oxygen debt is slower than the arithmetic
suggests.

| parameter | wolf | deer | provenance |
|---|---|---|---|
| `ceiling` (W/kg) | **18** | **11** | **[guess]** both — ≈0.6 × an assumed VO₂max of 90 / 55 ml O₂ kg⁻¹ min⁻¹. The *ordering* is sourced (Bryce & Williams: canids are elite endurance athletes; capture myopathy: deer are not) |
| `tank` (J/kg) | **1200** | **1775** | **[derived]** — set so both species sprint for the 25 s of §1.5. The deer's is larger because its sprint power is higher, not because it is fitter |
| `η` | **0.35** | **0.25** | **[guess]** — the deer recovers worse. Grounded in the capture-myopathy literature: a deer that over-exerts may not recover at all |

Note what falls out without being asked for: **the wolf's trot (6.6) and the
deer's trot (9.9) are both under their ceilings**, so both animals trot for free
— which is what the 10-hours-a-day figure demands. And the wolf's gallop (22)
is barely over its ceiling (18) while the deer's gallop (21.6) is twice over
its (11). *The wolf can course; the deer cannot.*

### 2.4 The gait tables

Costs in **energy units per second**, energy ∈ [0, 1]. Negative = recovers.
`canSustain` is from a full tank.

**Wolf** — `maxEnergy 1.0`, `fatigueThreshold 0.30`, `fatiguePenaltyMax 0.45`

| gait | speed (m/s) | speed (u/tick) | cost/s | canSustain |
|---|---|---|---|---|
| `walk` | 1.3 | **0.173** | **−0.00359** | ∞ (refills in 279 s) |
| `trot` | 2.2 | **0.293** | **−0.00333** | ∞ (refills in 300 s) |
| `gallop` | 10.0 | **1.333** | **+0.00333** | **300 s** |
| `sprint` | 16.1 | **2.147** | **+0.03917** | **25.5 s** |

Recovery at rest: **+0.00461/s** → a flat wolf is full again in **217 s**.

**Deer** — `maxEnergy 1.0`, `fatigueThreshold 0.30`, `fatiguePenaltyMax 0.55`

| gait | speed (m/s) | speed (u/tick) | cost/s | canSustain |
|---|---|---|---|---|
| `walk` | 1.3 | **0.173** | **−0.000676** | ∞ (refills in 1479 s) |
| `trot` | 3.0 | **0.400** | **−0.000155** | ∞ (refills in 6452 s) |
| `bound` | 7.0 | **0.933** | **+0.017465** | **57 s** |
| `gallop` | 9.0 | **1.200** | **+0.005972** | **167 s** |
| `sprint` | 15.6 | **2.080** | **+0.04000** | **25 s** |

Recovery at rest: **+0.001268/s** → a flat deer is full again in **789 s**
(13 minutes) — **3.6× slower than the wolf**. That ratio is the game.

`stot` uses the `bound` cost and the `trot` speed: it is a display, not flight
(Lingle 2002). Deliberately, `bound` is **slower than `gallop` and three times
dearer** — so on open ground it is a mistake, and only the obstacle patches make
it pay. That is the Lingle result, encoded.

**Monotonicity.** In speed and in cost/s, for both species:
`sprint > gallop > trot > walk`. `bound` sits off that ladder on purpose
(slower than gallop, dearer than gallop) and is excluded from the monotonicity
test.

### 2.5 Fatigue

```
fatiguePenalty = energy >= fatigueThreshold
               ? 0
               : (1 − energy / fatigueThreshold) × fatiguePenaltyMax
speed = gaitSpeed × (1 − fatiguePenalty)
```

At `energy = 0` a deer moves at **45%** of its gait speed — the stumble — and a
wolf at **55%**. A gait whose cost the animal cannot pay is unavailable: at zero
energy `sprint` and `bound` cannot be selected, so an emptied deer drops to
`gallop`, then to `trot`. Nothing here draws from the RNG.

### 2.6 Behaviours

**Deer `bound`** — crosses an obstacle patch at full `bound` speed where a wolf
must route around it. Costs `bound` energy. On open ground it is strictly worse
than `gallop`. Rational only with an obstacle on the line to the goal.

**Deer `stot`** — chosen when a wolf is detected but still far off. Costs
`bound` energy for `trot` movement, and applies a deterrence to wolves inside
detection range scaled by `(1 − persistence)` of the wolf and by the deer's
**remaining energy** — an honest signal is one a tired animal cannot afford
(FitzGibbon & Fanshawe 1988). A deterred wolf drops to `trot` and gives ground.

**Wolf `relay`** — a wolf below its own energy threshold drops to `trot` to
recover and yields the lead to a pack-mate. Scaled by `cohesion`: an incohesive
pack will not hand off, so its lead wolf burns down. Licensed by Muro et al.
2011, in which relay-running is emergent rather than choreographed — so this is
a per-wolf utility action, never a pack-level scheduler.

**Wolf `flank`** — take the cutting angle rather than the tail. Same source,
rule (2): once at the safe distance, move away from the other wolves who are
also at it.

### 2.7 Personality properties

Extended traits, read through sim-core's `traitOf` with defaults, so every
existing `Personality` (core six + randomness) keeps working unchanged.

| side | trait | default | what it does |
|---|---|---|---|
| wolf | `persistence` | 0.5 | resistance to being deterred by a stot; willingness to keep paying for a long chase |
| wolf | `cohesion` | 0.5 | willingness to `relay` and to hold `flank` spacing |
| wolf | `aggression` | *core* | direct chase and the willingness to spend `sprint` early |
| wolf | `caution` | *core* | holds a gait in reserve; declines low-probability sprints |
| deer | `vigilance` | 0.5 | detection range — the Lingle 2001 result, the deer's first defence |
| deer | `panic` | 0.5 | bias toward `sprint` when a wolf is close, at the cost of the tank |
| deer | `herdCohesion` | 0.5 | how tightly multiple deer stay together |
| deer | `stamina` | 0.5 | scales `maxEnergy` and `recoveryRate` — the "vulnerable individual" dial that lets a pack pick the weak one (Mech & Peterson) |

### 2.8 UI sliders

Per species: `maxEnergy`, `sprintCost`, `gallopCost`, `recoveryRate`,
`fatigueThreshold`, defaulting to the table in §2.4, with a **"reset to field
data"** button restoring exactly those values.

---

## 3. Everything that is a guess, in one list

So nobody has to hunt for the **[guess]** tags:

1. **Wolf gallop speed (10 m/s).** No source found for a wolf's gallop, only for
   its trot and its sprint. Chosen between them, nearer the sprint.
2. **Walk speeds (1.3 m/s, both).** Standard quadruped walk; not sourced.
3. **Deer trot (3.0) and gallop (9.0) speeds.** Only the deer's *top* speed is
   sourced.
4. **Deer bound speed (7 m/s) and its 2.5× COT.** Sourced only in *direction*
   (Lingle 2002: bounding does not outrun a courser).
5. **The sprint COT premium (×2.2, both species).** No measurement of any animal
   sprinting flat out was found.
6. **Both aerobic ceilings (18 and 11 W/kg)** and the VO₂max figures behind them.
   Only the *ordering* is sourced.
7. **Both recovery efficiencies (0.35, 0.25).** Ordering sourced (capture
   myopathy vs. elite canid aerobic capacity); magnitudes invented.
8. **The 25 s sprint window.** From human/general anaerobic physiology, not from
   any wolf or deer.
9. **The deer economy penalty (×1.25).** Analogy from hounds vs northern breeds
   within Bryce & Williams — a within-dog comparison being asked to carry a
   dog-to-deer one.
10. **The 0.25 m sim unit.** Chosen so the crossing lands near the 237 m mean
    roe-deer chase distance; the field dimensions themselves are inherited.
11. **Deer rest metabolic rate (2.0 W/kg).** Wolf RMR scaled allometrically.
12. **Every personality-trait weight** in §2.7 — those are game design, and the
    research constrains only their sign.

## 4. What the research refused to give

* **No cost-of-transport measurement for any cervid.** The entire deer column is
  a transfer from dogs with two multipliers, one of them an outright guess.
* **No wolf gallop speed**, from any source, agency or academic.
* **No seconds-level duration** for either animal's top speed, from any source.
* **No grey-wolf-on-white-tailed-deer hunting success rate** from a primary
  source; the 43–47% figures are Scandinavian wolves on moose and roe deer.
* **The two US agency sources disagree by 20%** on the wolf's top speed
  (36–38 vs 45 mph). This spec uses the lower.
* **The stotting evidence is about gazelles and African wild dogs**, not deer
  and wolves. Lingle 2002 supplies the deer half — and it partly *contradicts*
  the naive reading, which is why §1.4 leads with it.
